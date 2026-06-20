import 'package:flutter/material.dart';

import '../../features/player/player_expansion_controller.dart';
import '../theme/app_theme.dart';

/// The pitch-black stage with two huge drifting radial-gradient blobs that
/// sit behind everything. Matches `.stage-bg` from styles.css.
class StageBackground extends StatefulWidget {
  const StageBackground({super.key, this.animated = true, this.child});

  final bool animated;
  final Widget? child;

  @override
  State<StageBackground> createState() => _StageBackgroundState();
}

class _StageBackgroundState extends State<StageBackground>
    with TickerProviderStateMixin {
  late final AnimationController _drift1 =
      AnimationController(vsync: this, duration: const Duration(seconds: 28))
        ..repeat(reverse: true);
  late final AnimationController _drift2 =
      AnimationController(vsync: this, duration: const Duration(seconds: 34))
        ..repeat(reverse: true);

  // When the full player is up or another route covers the home shell,
  // this background is invisible, so we can stop the drift loops.
  PlayerExpansionController? _expansion;
  ModalRoute<Object?>? _route;
  bool _covered = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final exp = PlayerExpansionScope.maybeRead(context);
    if (!identical(exp, _expansion)) {
      _expansion?.removeListener(_recomputeCovered);
      _expansion = exp;
      _expansion?.addListener(_recomputeCovered);
    }
    final route = ModalRoute.of(context);
    if (!identical(route, _route)) {
      _route?.secondaryAnimation?.removeListener(_recomputeCovered);
      _route = route;
      _route?.secondaryAnimation?.addListener(_recomputeCovered);
    }
    _recomputeCovered();
  }

  void _recomputeCovered() {
    final byPlayer = (_expansion?.value ?? 0) >= 0.97;
    final byRoute = (_route?.secondaryAnimation?.value ?? 0) >= 0.97;
    final next = byPlayer || byRoute;
    if (next == _covered) return;
    _covered = next;
    if (next) {
      _drift1.stop();
      _drift2.stop();
    } else if (widget.animated) {
      if (!_drift1.isAnimating) _drift1.repeat(reverse: true);
      if (!_drift2.isAnimating) _drift2.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant StageBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animated && !_drift1.isAnimating && !_covered) {
      _drift1.repeat(reverse: true);
      _drift2.repeat(reverse: true);
    } else if (!widget.animated && _drift1.isAnimating) {
      _drift1.stop();
      _drift2.stop();
    }
  }

  @override
  void dispose() {
    _expansion?.removeListener(_recomputeCovered);
    _route?.secondaryAnimation?.removeListener(_recomputeCovered);
    _drift1.dispose();
    _drift2.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final base = isLight ? LumenTokens.lightStageBg : LumenTokens.stageBg;

    return Container(
      color: base,
      child: Stack(
        children: [
          // Day/light mode is a flat neutral stage — the drifting colour
          // blobs only run in dark mode, where they read as ambient glow
          // instead of a washed-out pastel gradient.
          if (!isLight)
            AnimatedBuilder(
              animation: Listenable.merge([_drift1, _drift2]),
              builder: (context, _) {
                return Stack(
                  children: [
                    Positioned.fill(
                      child: _Blob(
                        color: LumenTokens.blobPurple,
                        opacity: 0.35,
                        driftX: _drift1.value,
                        driftY: _drift1.value,
                        anchor: Alignment.topLeft,
                      ),
                    ),
                    Positioned.fill(
                      child: _Blob(
                        color: LumenTokens.blobPink,
                        opacity: 0.35,
                        driftX: 1 - _drift2.value,
                        driftY: 1 - _drift2.value,
                        anchor: Alignment.bottomRight,
                      ),
                    ),
                  ],
                );
              },
            ),
          if (widget.child != null) widget.child!,
        ],
      ),
    );
  }
}

class _Blob extends StatelessWidget {
  const _Blob({
    required this.color,
    required this.opacity,
    required this.driftX,
    required this.driftY,
    required this.anchor,
  });

  final Color color;
  final double opacity;
  final double driftX;
  final double driftY;
  final Alignment anchor;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size =
            constraints.biggest.shortestSide * 1.2; // ~60vw equivalent
        final dx = (constraints.maxWidth * 0.20) * (driftX - 0.5) * 2;
        final dy = (constraints.maxHeight * 0.15) * (driftY - 0.5) * 2;
        final scale = 1.0 + driftX * 0.2;
        final ax = anchor.x;
        final ay = anchor.y;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: ax < 0
                  ? -size * 0.16 + dx
                  : null,
              right: ax > 0
                  ? -size * 0.14 + dx
                  : null,
              top: ay < 0 ? -size * 0.16 + dy : null,
              bottom: ay > 0 ? -size * 0.16 + dy : null,
              width: size,
              height: size,
              child: Transform.scale(
                scale: scale,
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        color.withValues(alpha: opacity),
                        color.withValues(alpha: 0.0),
                      ],
                      stops: const [0.0, 0.7],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
