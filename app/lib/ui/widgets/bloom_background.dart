import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/album_colors.dart';
import '../../data/database/app_database.dart';
import '../../features/library/album_colors_provider.dart';
import '../../features/player/player_service.dart';
import '../../features/player/providers.dart';
import 'album_art.dart';

/// Now-playing background.
///
/// The approach: instead of a canvas-painted particle / spectrum
/// simulation (which never reads as smooth at 60fps and ends up
/// looking like a winamp visualiser), the bg here is a small set of
/// GPU-cheap transforms applied to the **blurred album art itself**:
///
///   1. Very slow rotation (one revolution / ~50s) — guarantees the
///      surface is never frozen even in silence.
///   2. Bass-reactive scale (1.00 ↔ 1.06) — kicks make the whole
///      ambient wash pulse outward and back.
///   3. Mid-reactive saturation lift via ColorFilter — vocals /
///      melody bloom the colour palette without affecting layout.
///   4. Two large drifting palette blobs on top — slow elliptical
///      paths give the depth a static blur lacks.
///
/// Every layer is `Transform`, `Opacity`, `ColorFiltered` or a
/// `Positioned` blob — all GPU-composited, no per-frame
/// `toImageSync`, no additive accumulation. Result is what Apple
/// Music / Spotify "Now Playing" actually look like: alive, polished,
/// always 60 fps, never bleached out.
class BloomBackground extends ConsumerStatefulWidget {
  const BloomBackground({
    super.key,
    required this.song,
    this.darkenStrength = 1.0,
    this.audioReactive = true,
  });

  final SongRow song;

  /// Vignette intensity multiplier. The lyrics view bumps this up so
  /// text reads cleanly against the bg.
  final double darkenStrength;

  /// When false, the FFT ticker + kick controllers stay idle — the bg
  /// still paints the album-tinted gradient, blurred art, and three
  /// static curtains, but they don't pulse to bass / snare. The
  /// expanded player passes `audioReactive: e >= 0.2` so the mini
  /// player's bloom stops grinding through 20 Hz FFT reads while the
  /// player is collapsed (the mini card is too small for the pulse to
  /// register anyway).
  final bool audioReactive;

  @override
  ConsumerState<BloomBackground> createState() => _BloomBackgroundState();
}

/// Warm brand-accent palette used as a vibrant fallback when there's
/// no extracted palette yet (cold start) or when the extracted palette
/// is fully neutral (greyscale cover). Keeps the bg from reading as a
/// flat grey wash; the cover artwork itself stays neutral in the
/// centre card.
final List<Color> _bloomWarmFallback = AlbumColors.fallback;

class _BloomBackgroundState extends ConsumerState<BloomBackground>
    with TickerProviderStateMixin {
  // ONE-SHOT kick controllers, one per band. Each is triggered with
  // `.forward(from: 0)` when the audio tick detects a transient
  // (rising edge of the band's envelope above a threshold). The
  // controller animates 0 → 1 over [_kickDuration]; the curtain
  // reads its value to drive a sharp shake + width + alpha pulse
  // that decays back to rest. When the controller finishes it
  // stops at 1 and stays there — ZERO per-frame cost between kicks.
  late final AnimationController _bassKick;
  late final AnimationController _midKick;
  static const _kickDuration = Duration(milliseconds: 320);

  // FFT reader — 20 Hz tick. Detects transients and fires the kick
  // controllers. The previous build also advanced a horizontal drift
  // phase here, but user feedback was that the constant horizontal
  // motion in the upper area read as "disturbing movement in the top
  // left". Drift is removed entirely; curtains now sit at fixed
  // anchors and only react to bass / snare onsets.
  late final Ticker _audioTicker;
  Duration _lastAudioTick = Duration.zero;
  static const _audioTickInterval = Duration(milliseconds: 50);

  // Per-band rolling peaks for auto-normalisation.
  double _bassPeak = 0.04;
  double _midPeak = 0.04;

  // Previous normalised band values for transient (rising-edge)
  // detection — kick fires only on a sharp onset, not a sustained
  // loud level, so the visual stays distinct beat-by-beat instead
  // of saturating during sustained bass.
  double _prevBassNorm = 0;
  double _prevMidNorm = 0;
  static const _kickThreshold = 0.14;

  PlayerService? _player;
  bool _isPlaying = false;
  List<Color>? _lastPalette;

  // Visibility tracking. When this bloom is fully covered by another
  // route (e.g. the lyrics view pushed on top of the player), the FFT
  // sampling and kick controllers stop — the bg below isn't drawn so
  // nothing reads its state until we come back. Lyrics renders its own
  // bloom on top, so pausing this one removes a duplicate animation
  // pipeline running for nothing.
  ModalRoute<Object?>? _route;
  bool _covered = false;

  @override
  void initState() {
    super.initState();
    _bassKick = AnimationController(vsync: this, duration: _kickDuration);
    _midKick = AnimationController(vsync: this, duration: _kickDuration);
    _audioTicker = createTicker(_onAudioTick);
    if (widget.audioReactive) _audioTicker.start();
  }

  @override
  void didUpdateWidget(covariant BloomBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.audioReactive != widget.audioReactive) {
      if (widget.audioReactive && !_covered) {
        if (!_audioTicker.isActive) _audioTicker.start();
      } else {
        if (_audioTicker.isActive) _audioTicker.stop();
        _bassKick.stop();
        _midKick.stop();
        _prevBassNorm = 0;
        _prevMidNorm = 0;
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (!identical(route, _route)) {
      _route?.secondaryAnimation?.removeListener(_recomputeCovered);
      _route = route;
      _route?.secondaryAnimation?.addListener(_recomputeCovered);
    }
    _recomputeCovered();
  }

  void _recomputeCovered() {
    final next = (_route?.secondaryAnimation?.value ?? 0) >= 0.97;
    if (next == _covered) return;
    _covered = next;
    if (next) {
      if (_audioTicker.isActive) _audioTicker.stop();
      _bassKick.stop();
      _midKick.stop();
    } else if (widget.audioReactive) {
      if (!_audioTicker.isActive) _audioTicker.start();
    }
  }

  @override
  void dispose() {
    _route?.secondaryAnimation?.removeListener(_recomputeCovered);
    _bassKick.dispose();
    _midKick.dispose();
    _audioTicker.dispose();
    super.dispose();
  }

  /// Sample bass + mid bands, detect rising-edge transients, fire
  /// the matching kick controller. Most ticks fire NOTHING — only
  /// genuine onsets trigger a kick, which keeps the visual sharp
  /// (each kick is a discrete event, not a continuous swell).
  void _onAudioTick(Duration elapsed) {
    if (elapsed - _lastAudioTick < _audioTickInterval) return;
    _lastAudioTick = elapsed;

    final player = _player;
    if (!_isPlaying || player == null) {
      _prevBassNorm = 0;
      _prevMidNorm = 0;
      return;
    }

    final fft = player.readFftSnapshot();
    if (fft == null || fft.isEmpty) return;

    // Band layout chosen to AVOID the vocal pitch range.
    //  - Bass:  bins 1-8   (~86-690 Hz)   kick drum + sub bass
    //  - Snare: bins 30-80 (~2.6-7 kHz)   snare crack + hat snap.
    //           NOT the previous bins 9-30, which sat directly on
    //           the vocal fundamental + first formant — any singing
    //           constantly tripped the kick.
    final bassRaw = _avgBand(fft, 1, 8);
    final snareRaw = _avgBand(fft, 30, 80);

    if (bassRaw > _bassPeak) _bassPeak = bassRaw * 1.10;
    _bassPeak *= 0.997;
    if (_bassPeak < 0.04) _bassPeak = 0.04;

    if (snareRaw > _midPeak) _midPeak = snareRaw * 1.10;
    _midPeak *= 0.997;
    if (_midPeak < 0.04) _midPeak = 0.04;

    final bassNorm = (bassRaw / _bassPeak).clamp(0.0, 1.0);
    final snareNorm = (snareRaw / _midPeak).clamp(0.0, 1.0);

    if (bassNorm > _prevBassNorm + _kickThreshold && bassNorm > 0.30) {
      _bassKick
        ..stop()
        ..forward(from: 0.0);
    }
    if (snareNorm > _prevMidNorm + _kickThreshold && snareNorm > 0.30) {
      _midKick
        ..stop()
        ..forward(from: 0.0);
    }
    _prevBassNorm = bassNorm;
    _prevMidNorm = snareNorm;
  }

  double _avgBand(Float32List fft, int lo, int hi) {
    final cap = hi.clamp(0, fft.length - 1);
    if (lo > cap) return 0.0;
    var sum = 0.0;
    var n = 0;
    for (var i = lo; i <= cap; i++) {
      sum += fft[i].abs();
      n++;
    }
    return sum / n;
  }

  @override
  Widget build(BuildContext context) {
    _player ??= ref.read(playerServiceProvider);

    // Palette resolution — prefer freshly-resolved, then last-known,
    // then the warm brand fallback. Substitute the warm fallback for
    // any fully-neutral palette so a greyscale cover doesn't make the
    // bg read as a cold grey wash.
    final resolved = ref
        .watch(albumColorsProvider(widget.song.localArtworkPath))
        .valueOrNull;
    if (resolved != null && !identical(resolved, AlbumColors.fallback)) {
      _lastPalette = resolved;
    }
    // Pass the extracted palette through as-is. Greyscale covers
    // (black / white / grey) correctly resolve to a neutral grey
    // palette via AlbumColors._neutralPalette — that's what the
    // listener should see for those albums, NOT the brand
    // pink/purple/blue identity. The warm fallback is reserved for
    // actual extraction failures (missing file, decode error), where
    // [resolved] comes back as the static `AlbumColors.fallback`
    // sentinel — that path naturally lands on the warm palette.
    final colors = resolved ?? _lastPalette ?? _bloomWarmFallback;
    final s = widget.darkenStrength.clamp(0.0, 1.0);

    final c0 = colors[0];
    final c1 = colors.length > 1 ? colors[1] : colors[0];
    final c2 = colors.length > 2 ? colors[2] : colors[0];

    return RepaintBoundary(
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Bridge — keeps the isPlaying snapshot fresh without
          // forcing the bg stack to rebuild every position tick.
          _PlayerStateBridge(
            onPlayingChange: (playing) => _isPlaying = playing,
          ),

          // 1. Dark night-sky base. The previous build painted the
          //    raw palette here at full saturation, which is why
          //    the dominant cover colour "crept in" and flooded the
          //    screen after a while. Now the base is a deep, lightly
          //    palette-tinted blue/black — the sky against which the
          //    aurora curtains read as light, not as additions to an
          //    already-saturated wash.
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color.lerp(c2, Colors.black, 0.75)!,
                    Color.lerp(c1, Colors.black, 0.85)!,
                    Color.lerp(c0, Colors.black, 0.80)!,
                  ],
                  stops: const [0.0, 0.5, 1.0],
                ),
              ),
            ),
          ),

          // 2. Heavily-blurred album art at low opacity — the song's
          //    "colour memory" without overpowering the night-sky
          //    base. No rotation: the rotation was a per-frame
          //    Transform.rotate composite that was contributing to
          //    lag on the lyrics page (which also mounts this bg).
          //    The aurora curtains below provide all the motion.
          _StaticBlurredArt(song: widget.song),

          // 3. Three aurora curtains — vertical-elliptical streaks
          //    of palette colour at FIXED horizontal anchors that
          //    SHAKE on bass / snare transients. Drift was removed
          //    (it read as "disturbing movement in the top left").
          //    Curtain 1 (palette[0]) — anchored 25 %, bass kick.
          //    Curtain 2 (palette[1]) — anchored 50 %, snare kick.
          //    Curtain 3 (palette[2]) — anchored 75 %, bass kick.
          _AuroraCurtain(
            color: c0,
            anchorX: 0.25,
            phase: 0,
            kick: _bassKick,
          ),
          _AuroraCurtain(
            color: c1,
            anchorX: 0.5,
            phase: 1,
            kick: _midKick,
          ),
          _AuroraCurtain(
            color: c2,
            anchorX: 0.75,
            phase: 2,
            kick: _bassKick,
          ),

          // 4. Vignette — keeps chrome text legible against the
          //    bg's brightest regions. Stronger at the bottom where
          //    the transport row + niche bar sit.
          IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.0),
                    Colors.black.withValues(alpha: 0.4 * s),
                    Colors.black.withValues(alpha: 0.7 * s),
                  ],
                  stops: const [0.0, 0.6, 1.0],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Heavily-blurred album art at low opacity, sitting between the dark
/// night-sky base and the aurora curtains. Pure cached layer — built
/// once per song, never rebuilt; the wrapping RepaintBoundary keeps
/// the blur out of the per-frame paint loop. No rotation or scale
/// animation: this is the song's "colour memory", not its motion.
class _StaticBlurredArt extends StatelessWidget {
  const _StaticBlurredArt({required this.song});

  final SongRow song;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: RepaintBoundary(
          // Blur dropped from σ=40 to σ=20. Cost of `ImageFilter.blur`
          // scales roughly with σ² on the texture size — this is a ~4×
          // cheaper first-paint, which is the cost that wasn't being
          // amortised by the surrounding RepaintBoundary (the layer is
          // re-rasterised whenever the song changes). Visually the blob
          // of colour reads identically; σ=40 was past the point of
          // diminishing returns on a heavily-darkened image.
          child: Opacity(
            opacity: 0.32,
            child: ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: AlbumArt(
                artworkPath: song.localArtworkPath,
                seed: song.id,
                size: double.infinity,
                radius: 0,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A vertical aurora-like glow of palette colour at a FIXED anchor.
/// Three of these layered at 25 % / 50 % / 75 % horizontal positions
/// form the "northern lights" composition.
///
/// Motion: NONE at rest. The previous build drifted curtains
/// horizontally on a slow sine; user feedback was that the constant
/// motion in the upper area read as "disturbing movement in the top
/// left". On each kick (bass or snare onset) the curtain pulses
/// alpha + width over 320 ms then settles — no positional change,
/// no horizontal shake. Result: paused = perfectly still bg; playing
/// = subtle pulse on each beat.
class _AuroraCurtain extends StatelessWidget {
  const _AuroraCurtain({
    required this.color,
    required this.anchorX,
    required this.phase,
    required this.kick,
  });

  /// Palette colour for this glow.
  final Color color;

  /// Horizontal centre as a fraction of canvas width (0 = left edge,
  /// 1 = right edge). The curtain's gradient centre lands at exactly
  /// this position — no per-frame drift offsets it.
  final double anchorX;

  /// Kept for backwards compatibility with the call sites; unused
  /// now that drift has been removed. Will be cleaned up next pass.
  // ignore: unused_element
  final int phase;

  /// One-shot kick controller fired by the audio tick on each
  /// rising-edge transient of this curtain's band.
  final AnimationController kick;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final w = constraints.maxWidth;
            final h = constraints.maxHeight;
            // Curtain bounding box. Tall + narrow → the RadialGradient
            // inside forms a vertical-ellipse, the aurora ribbon shape.
            final curtainW = w * 0.40;
            final curtainH = h * 1.30;
            // Convert anchorX (0..1 = left..right of the canvas) into
            // Align's coordinate system (-1..1 = left..right relative
            // to (parent − child) width). Solving:
            //   childCenterX = anchorX * w
            //   childCenterX = (1 + alignX)/2 * (w − curtainW) + curtainW/2
            // gives:
            //   alignX = (anchorX * w − curtainW/2) / ((w − curtainW)/2) − 1
            // which simplifies to (2*anchorX − 1) / (1 − curtainW/w).
            final alignX =
                (2 * anchorX - 1) / (1 - curtainW / w);

            return Align(
              alignment: Alignment(alignX, 0),
              child: SizedBox(
                width: curtainW,
                height: curtainH,
                // RepaintBoundary per curtain so a kick only invalidates
                // *this* curtain's compositing layer, not the entire
                // bloom stack (base gradient + blurred art + 2 sibling
                // curtains + vignette). All three curtains have their
                // own kicks, so without this the bloom's outer layer
                // dirties on almost every audio onset.
                child: RepaintBoundary(
                  child: AnimatedBuilder(
                    animation: kick,
                    builder: (context, _) {
                      // Ease-out quadratic kick decay over 320 ms.
                      // value=0 → punch=1 (peak); value=1 → punch=0.
                      final inv = 1.0 - kick.value;
                      final punch = inv * inv;
                      // Width breathes outward on each kick (1.0 → 1.35)
                      // and alpha pops (0.18 → 0.78). No horizontal
                      // translation — the curtain pulses in place.
                      final alpha = 0.18 + punch * 0.60;
                      final widthScale = 1.0 + punch * 0.35;
                      return Transform.scale(
                        scaleX: widthScale,
                        scaleY: 1.0,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: RadialGradient(
                              colors: [
                                color.withValues(alpha: alpha),
                                color.withValues(alpha: alpha * 0.45),
                                color.withValues(alpha: 0.0),
                              ],
                              stops: const [0.0, 0.45, 1.0],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Sub-tree-only Consumer that forwards isPlaying without rebuilding
/// the bg stack on every position tick.
class _PlayerStateBridge extends ConsumerWidget {
  const _PlayerStateBridge({required this.onPlayingChange});

  final ValueChanged<bool> onPlayingChange;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playing =
        ref.watch(playerStateStreamProvider).valueOrNull?.playing ?? false;
    onPlayingChange(playing);
    return const SizedBox.shrink();
  }
}
