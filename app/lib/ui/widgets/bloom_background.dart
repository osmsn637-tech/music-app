import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/album_colors.dart';
import '../../data/database/app_database.dart';
import '../../features/library/album_colors_provider.dart';
import '../../features/player/providers.dart';
import 'album_art.dart';

/// Heavily-blurred fullscreen artwork with three drifting colour blobs
/// painted in the cover's own dominant colours, plus a top-to-bottom
/// darkening overlay. The blobs also flow with the song: a 2-beat
/// cosine envelope phase-locked to the BPM gently swells radius, alpha,
/// and orbit width — more like a tide than a pulse. BPM comes from the
/// song row (synced from the server). When BPM is unknown we fall back
/// to a default that keeps the visual alive without pretending to track
/// the music.
class BloomBackground extends ConsumerStatefulWidget {
  const BloomBackground({
    super.key,
    required this.song,
    this.darkenStrength = 1.0,
  });

  final SongRow song;

  /// Multiplier (0–1) on the darkening gradient. The lyrics view bumps it
  /// up so the text reads cleanly on top of busy art.
  final double darkenStrength;

  @override
  ConsumerState<BloomBackground> createState() => _BloomBackgroundState();
}

class _BloomBackgroundState extends ConsumerState<BloomBackground>
    with SingleTickerProviderStateMixin {
  // Single ValueNotifier driving the painter. Replaces 3 AnimationControllers
  // + a separate beat ValueNotifier — those each fired a Listener at 60fps,
  // so the painter repainted every frame even though the drifts have
  // periods of 19/23/31 seconds. Now one ticker, throttled to ~30fps.
  final ValueNotifier<_BloomParams> _params =
      ValueNotifier<_BloomParams>(_BloomParams.zero);
  late final Ticker _ticker;
  Duration _lastTickAt = Duration.zero;

  // Drift periods in seconds — kept as constants so the per-frame math
  // stays branch-free.
  static const _periods = <double>[19, 23, 31];
  static const _frameInterval = Duration(milliseconds: 33);

  // Snapshot of the last known stream position + wallclock — same trick
  // the karaoke lyrics use to interpolate between coarse position events.
  Duration _streamPos = Duration.zero;
  DateTime _streamPosAt = DateTime.now();
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _params.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    if (elapsed - _lastTickAt < _frameInterval) return;
    _lastTickAt = elapsed;

    final t = elapsed.inMicroseconds / 1e6;
    final drifts = <double>[
      (t / _periods[0]) % 1.0,
      (t / _periods[1]) % 1.0,
      (t / _periods[2]) % 1.0,
    ];

    double beat = _params.value.beat;
    if (_isPlaying) {
      final pos = _streamPos + DateTime.now().difference(_streamPosAt);
      final bpm = (widget.song.bpm ?? 100).clamp(40, 240);
      final beatSec = 60.0 / bpm;
      final tSec = pos.inMicroseconds / 1e6;
      if (tSec >= 0) {
        // 2-beat cycle, smooth cosine envelope. Peaks (+1) on each
        // downbeat, troughs (-1) between them — a tide that ebbs and
        // flows rather than a percussive snap.
        final phase = (tSec / (beatSec * 2)) % 1.0;
        beat = math.cos(phase * 2 * math.pi);
      }
    } else if (beat.abs() > 0.005) {
      // Drain the flow toward zero when paused so the blobs settle into
      // a calm state rather than freezing mid-swell.
      beat = beat * 0.96;
    }

    _params.value = _BloomParams(drifts: drifts, beat: beat);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.darkenStrength.clamp(0.0, 1.0);
    final colors = ref
            .watch(albumColorsProvider(widget.song.localArtworkPath))
            .valueOrNull ??
        AlbumColors.fallback;

    // Hoist the entire bloom into its own RepaintBoundary so the per-frame
    // CustomPaint repaints don't bubble up into the Player/Lyrics tree.
    return RepaintBoundary(
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Tiny invisible Consumer that keeps the Ticker's interpolation
          // baseline fresh without forcing the Stack tree to rebuild every
          // time just_audio's position stream emits (~1Hz). Without this,
          // every position event would re-create BackdropFilter etc.
          _PlayerStateBridge(
            onPositionChange: (pos) {
              if (pos != _streamPos) {
                _streamPos = pos;
                _streamPosAt = DateTime.now();
              }
            },
            onPlayingChange: (playing) => _isPlaying = playing,
          ),
          // Blurred artwork. ImageFiltered blurs ITS CHILD without a
          // saveLayer, and the AlbumArt is rendered tiny then upscaled by
          // the Stack — so the blur cost is ~64x64 instead of fullscreen.
          Positioned.fill(
            child: ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: 60, sigmaY: 60),
              child: AlbumArt(
                artworkPath: widget.song.localArtworkPath,
                seed: widget.song.id,
                size: 64,
                radius: 0,
              ),
            ),
          ),
          // Animated dominant-colour blobs riding on top of the bloom.
          // Default srcOver blend (no saveLayer) — visually similar to
          // screen mode but without the per-frame compositing cost.
          Positioned.fill(
            child: RepaintBoundary(
              child: ValueListenableBuilder<_BloomParams>(
                valueListenable: _params,
                builder: (context, params, _) {
                  return CustomPaint(
                    painter: _ColorBlobsPainter(
                      colors: colors,
                      drifts: params.drifts,
                      beat: params.beat,
                    ),
                  );
                },
              ),
            ),
          ),
          // Dark vignette so foreground text/artwork stay legible.
          DecoratedBox(
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
        ],
      ),
    );
  }
}

/// Sub-tree-only Consumer used by [BloomBackground] to receive
/// position/state changes without rebuilding the whole bloom Stack. It
/// renders nothing — its only job is to forward Riverpod values to the
/// parent's mutable fields each time the providers tick.
class _PlayerStateBridge extends ConsumerWidget {
  const _PlayerStateBridge({
    required this.onPositionChange,
    required this.onPlayingChange,
  });

  final ValueChanged<Duration> onPositionChange;
  final ValueChanged<bool> onPlayingChange;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pos =
        ref.watch(playerPositionProvider).valueOrNull ?? Duration.zero;
    final playing =
        ref.watch(playerStateStreamProvider).valueOrNull?.playing ?? false;
    onPositionChange(pos);
    onPlayingChange(playing);
    return const SizedBox.shrink();
  }
}

/// Snapshot of every per-frame value the bloob painter needs. Held in a
/// single `ValueNotifier` so one tick produces one repaint, regardless of
/// how many sub-values changed.
class _BloomParams {
  const _BloomParams({required this.drifts, required this.beat});

  static const _BloomParams zero =
      _BloomParams(drifts: <double>[0, 0, 0], beat: 0);

  final List<double> drifts;
  final double beat;
}

class _ColorBlobsPainter extends CustomPainter {
  _ColorBlobsPainter({
    required this.colors,
    required this.drifts,
    required this.beat,
  });

  final List<Color> colors;
  final List<double> drifts;

  /// Smooth flow envelope, -1..1. +1 at the downbeat crest, -1 between
  /// beats. Used as a fluid modulator on radius / alpha / orbit.
  final double beat;

  static const _twoPi = math.pi * 2;
  static const _anchors = <Offset>[
    Offset(0.30, 0.32),
    Offset(0.72, 0.62),
    Offset(0.50, 0.85),
  ];
  static const _orbitX = <double>[0.22, 0.18, 0.20];
  static const _orbitY = <double>[0.18, 0.22, 0.16];
  static const _radii = <double>[0.85, 0.70, 0.65];

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final shortest = math.min(w, h);
    final n = math.min(colors.length, drifts.length);

    // Smooth fluid modulation. beat ∈ -1..1; map to gentle scalars so the
    // motion feels like a tide rather than a hit.
    final radiusFlow = 1.0 + beat * 0.08; // ±8% radius swell
    final alphaFlow = 0.55 + beat * 0.10; // ±0.10 brightness lift
    final orbitFlow = 1.0 + beat * 0.18; // ±18% orbit width swing

    for (var i = 0; i < n; i++) {
      final t = drifts[i];
      final anchor = _anchors[i % _anchors.length];
      final orbX = _orbitX[i % _orbitX.length] * orbitFlow;
      final orbY = _orbitY[i % _orbitY.length] * orbitFlow;
      final cx = anchor.dx * w +
          math.cos(t * _twoPi + i * 0.9) * w * orbX;
      final cy = anchor.dy * h +
          math.sin(t * _twoPi + i * 0.6) * h * orbY;
      final radius = shortest * _radii[i % _radii.length] * radiusFlow;

      // Plain srcOver — visually close enough to a screen blend at this
      // alpha range, but without the per-frame saveLayer cost screen mode
      // would force when this CustomPaint sits on top of the bloom.
      final paint = Paint()
        ..shader = ui.Gradient.radial(
          Offset(cx, cy),
          radius,
          [
            colors[i].withValues(alpha: alphaFlow),
            colors[i].withValues(alpha: 0.0),
          ],
          const [0.0, 0.75],
        );
      canvas.drawCircle(Offset(cx, cy), radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ColorBlobsPainter old) => true;
}
