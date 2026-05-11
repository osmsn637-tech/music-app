import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/player/now_playing_controller.dart';
import '../../features/player/providers.dart';
import '../theme/app_theme.dart';

/// Interactive multi-blob aurora background. Five gradient orbs drift on
/// independent slow loops, breathe in/out together, and gently gravitate
/// toward the user's pointer (touch or hover). When a song is playing,
/// the same 2-beat tide envelope used by the player's bloom subtly
/// modulates orbit width and opacity here too — so the home shell flows
/// with the music without ever feeling busy.
///
/// Colors come from [LumenTod] — five phases (dawn / day / golden /
/// dusk / night) blended at hour boundaries. Refreshed every 5 minutes
/// so an open app crosses phases without being relaunched.
///
/// `behavior: HitTestBehavior.translucent` on the gesture layer means
/// touches still reach the UI underneath — the blobs only *track* the
/// pointer; they don't consume gestures.
class LiveWallpaperBackground extends ConsumerStatefulWidget {
  const LiveWallpaperBackground({super.key, this.child});

  final Widget? child;

  @override
  ConsumerState<LiveWallpaperBackground> createState() =>
      _LiveWallpaperBackgroundState();
}

class _LiveWallpaperBackgroundState
    extends ConsumerState<LiveWallpaperBackground>
    with TickerProviderStateMixin {
  // Anchor + drift specs are color-agnostic — the painter pulls colors
  // from the active TOD phase at paint time. That keeps the same five
  // orbits stable across phase transitions; only the hue shifts.
  static const _specs = <_BlobSpec>[
    _BlobSpec(_BlobRole.warm, Alignment.topLeft, 0.62,
        driftAmpX: 0.20, driftAmpY: 0.14),
    _BlobSpec(_BlobRole.cool, Alignment.bottomRight, 0.66,
        driftAmpX: 0.18, driftAmpY: 0.16),
    _BlobSpec(_BlobRole.accent, Alignment.topRight, 0.50,
        driftAmpX: 0.22, driftAmpY: 0.12),
    _BlobSpec(_BlobRole.warm, Alignment.bottomLeft, 0.45,
        driftAmpX: 0.15, driftAmpY: 0.18),
    _BlobSpec(_BlobRole.cool, Alignment.centerLeft, 0.55,
        driftAmpX: 0.24, driftAmpY: 0.10),
  ];

  late final List<AnimationController> _drifts;
  late final AnimationController _pulse;
  final ValueNotifier<Offset?> _pointer = ValueNotifier(null);

  // Music-driven flow envelope, -1..1. Same shape as the bloom — a
  // 2-beat cosine tide. Smoothly settles to 0 when nothing is playing.
  final ValueNotifier<double> _flow = ValueNotifier(0.0);
  late final Ticker _flowTicker;

  Duration _streamPos = Duration.zero;
  DateTime _streamPosAt = DateTime.now();
  bool _isPlaying = false;
  int? _bpm;

  // Active TOD phase. Refreshed periodically so a long-running session
  // crosses dawn/day/dusk without needing a relaunch. We hold both the
  // active phase and the next one so the painter can lerp on hour
  // boundaries (smoother than snapping at 16:00 from day to golden).
  DateTime _now = DateTime.now();
  Timer? _phaseTick;

  @override
  void initState() {
    super.initState();
    _drifts = List.generate(_specs.length, (i) {
      // Prime numbers so the loops never line up — keeps the motion from
      // looking like a clock returning to its noon position.
      final secs = [23, 29, 31, 37, 41][i % 5];
      return AnimationController(
        vsync: this,
        duration: Duration(seconds: secs),
      )
        ..forward(from: i / _specs.length)
        ..repeat(reverse: false);
    });
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 7),
    )..repeat(reverse: true);
    _flowTicker = createTicker(_onFlowTick)..start();
    // Refresh the wallpaper's TOD phase every 5 minutes — gentle enough
    // to be invisible mid-phase, frequent enough to catch the boundary.
    _phaseTick = Timer.periodic(const Duration(minutes: 5), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _phaseTick?.cancel();
    _flowTicker.dispose();
    _flow.dispose();
    for (final c in _drifts) {
      c.dispose();
    }
    _pulse.dispose();
    _pointer.dispose();
    super.dispose();
  }

  void _onFlowTick(Duration _) {
    if (!_isPlaying || _bpm == null) {
      if (_flow.value.abs() > 0.005) {
        _flow.value = _flow.value * 0.96;
      }
      return;
    }
    final pos = _streamPos + DateTime.now().difference(_streamPosAt);
    final beatSec = 60.0 / _bpm!.clamp(40, 240);
    final tSec = pos.inMicroseconds / 1e6;
    if (tSec < 0) return;
    final phase = (tSec / (beatSec * 2)) % 1.0;
    final env = math.cos(phase * 2 * math.pi);
    if ((env - _flow.value).abs() > 0.003) {
      _flow.value = env;
    }
  }

  void _setPointer(Offset p) {
    final old = _pointer.value;
    // Throttle: only push a new value once the finger has moved >6px.
    // Without this every pixel of pointer movement would repaint the
    // canvas, which adds up on a slow device.
    if (old == null || (old - p).distance > 6) {
      _pointer.value = p;
    }
  }

  void _clearPointer() {
    _pointer.value = null;
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final blend = LumenTod.blendFor(_now, brightness: brightness);
    final phase = LumenTodPhase.lerp(blend.a, blend.b, blend.t);
    final blobOpacity = brightness == Brightness.light ? 0.45 : 0.32;

    return Container(
      color: phase.stage,
      child: Stack(
        children: [
          // Tiny invisible Consumer that keeps the Ticker's interpolation
          // baseline + BPM fresh without forcing the whole wallpaper tree
          // (LayoutBuilder, Listener, RepaintBoundary, AnimatedBuilder…)
          // to rebuild on every position emit.
          Positioned.fill(
            child: IgnorePointer(
              child: _MusicStateBridge(
                onPositionChange: (pos) {
                  if (pos != _streamPos) {
                    _streamPos = pos;
                    _streamPosAt = DateTime.now();
                  }
                },
                onPlayingChange: (playing) => _isPlaying = playing,
                onBpmChange: (bpm) => _bpm = bpm,
              ),
            ),
          ),
          Positioned.fill(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return Listener(
                  behavior: HitTestBehavior.translucent,
                  onPointerDown: (e) => _setPointer(e.localPosition),
                  onPointerMove: (e) => _setPointer(e.localPosition),
                  onPointerHover: (e) => _setPointer(e.localPosition),
                  onPointerUp: (_) => _clearPointer(),
                  onPointerCancel: (_) => _clearPointer(),
                  child: ClipRect(
                    child: RepaintBoundary(
                      child: ValueListenableBuilder<Offset?>(
                        valueListenable: _pointer,
                        builder: (context, pointer, _) {
                          return AnimatedBuilder(
                            animation: Listenable.merge(
                                [..._drifts, _pulse, _flow]),
                            builder: (context, _) {
                              return CustomPaint(
                                size: Size(
                                  constraints.maxWidth,
                                  constraints.maxHeight,
                                ),
                                painter: _BlobsPainter(
                                  specs: _specs,
                                  phase: phase,
                                  drifts:
                                      _drifts.map((c) => c.value).toList(),
                                  pulse: _pulse.value,
                                  flow: _flow.value,
                                  pointer: pointer,
                                  opacity: blobOpacity,
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          // Subtle bottom-vignette tint in the active phase color so glass
          // surfaces near the dock get a richer base to blur against —
          // matches the JSX kit's `linear-gradient(180deg, transparent → stage AA)`.
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      phase.stage.withValues(alpha: 0.55),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (widget.child != null) widget.child!,
        ],
      ),
    );
  }
}

/// Sub-tree-only Consumer that forwards Riverpod player state to the
/// wallpaper without rebuilding the visible tree.
class _MusicStateBridge extends ConsumerWidget {
  const _MusicStateBridge({
    required this.onPositionChange,
    required this.onPlayingChange,
    required this.onBpmChange,
  });

  final ValueChanged<Duration> onPositionChange;
  final ValueChanged<bool> onPlayingChange;
  final ValueChanged<int?> onBpmChange;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final song = ref.watch(nowPlayingProvider);
    final pos =
        ref.watch(playerPositionProvider).valueOrNull ?? Duration.zero;
    final playing =
        ref.watch(playerStateStreamProvider).valueOrNull?.playing ?? false;
    onPositionChange(pos);
    onPlayingChange(playing);
    onBpmChange(song?.bpm);
    return const SizedBox.shrink();
  }
}

enum _BlobRole { warm, cool, accent }

class _BlobSpec {
  const _BlobSpec(
    this.role,
    this.anchor,
    this.sizeFraction, {
    required this.driftAmpX,
    required this.driftAmpY,
  });

  final _BlobRole role;
  final Alignment anchor;
  final double sizeFraction; // radius as fraction of viewport shortest side
  final double driftAmpX; // horizontal drift amplitude as fraction of width
  final double driftAmpY; // vertical drift amplitude as fraction of height
}

class _BlobsPainter extends CustomPainter {
  _BlobsPainter({
    required this.specs,
    required this.phase,
    required this.drifts,
    required this.pulse,
    required this.flow,
    required this.pointer,
    required this.opacity,
  });

  final List<_BlobSpec> specs;
  final LumenTodPhase phase;
  final List<double> drifts;
  final double pulse;

  /// Music-driven flow, -1..1. Cosine of 2-beat cycle. Modulates orbit
  /// width and opacity so the wallpaper feels like it's moving with the
  /// song without obvious "thumps".
  final double flow;

  final Offset? pointer;
  final double opacity;

  static const _twoPi = math.pi * 2;

  Color _colorFor(_BlobRole role) {
    switch (role) {
      case _BlobRole.warm:
        return phase.warm;
      case _BlobRole.cool:
        return phase.cool;
      case _BlobRole.accent:
        return phase.accent;
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final shortest = math.min(w, h);

    // Subtle music-flow modulation — these are smaller than the bloom's
    // because this view sits behind the whole UI. Visible enough to
    // feel alive, gentle enough to read as ambient.
    final orbitFlow = 1.0 + flow * 0.15;
    final alphaFlow = opacity + flow * 0.05;

    for (var i = 0; i < specs.length; i++) {
      final spec = specs[i];
      final t = drifts[i];
      final color = _colorFor(spec.role);

      // Anchor in pixels (Alignment.x/y is -1..1).
      final ax = (spec.anchor.x + 1) / 2 * w;
      final ay = (spec.anchor.y + 1) / 2 * h;

      // Base drift: smooth Lissajous so x and y use different phases.
      // Orbit amplitude swells with the music's flow.
      var cx = ax +
          math.sin(t * _twoPi) * w * spec.driftAmpX * orbitFlow;
      var cy = ay +
          math.cos(t * _twoPi + i * 0.7) * h * spec.driftAmpY * orbitFlow;

      // Pointer gravity. Falls off with distance — strong near the finger,
      // ~zero past 480px. Capped to ~70px max pull so the blobs don't
      // pile onto the cursor.
      if (pointer != null) {
        final dx = pointer!.dx - cx;
        final dy = pointer!.dy - cy;
        final dist = math.sqrt(dx * dx + dy * dy).clamp(1.0, 480.0);
        final influence = 1 - dist / 480;
        final pull = influence * influence * 70; // squared falloff
        cx += dx / dist * pull;
        cy += dy / dist * pull;
      }

      // Breathing pulse — every blob shares the same phase so they inhale
      // together. Subtle (±6%) so it reads as ambient rather than busy.
      final scale = 1.0 + (pulse - 0.5) * 0.12;
      final radius = shortest * spec.sizeFraction * scale;

      final paint = Paint()
        ..shader = ui.Gradient.radial(
          Offset(cx, cy),
          radius,
          [
            color.withValues(alpha: alphaFlow),
            color.withValues(alpha: 0.0),
          ],
          const [0.0, 0.75],
        );
      canvas.drawCircle(Offset(cx, cy), radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _BlobsPainter old) {
    // The animation listenable already drives repaints; we only return
    // true here so the painter is recreated every frame the controller
    // ticks. Cheap — the painter holds tiny scalars.
    return true;
  }
}
