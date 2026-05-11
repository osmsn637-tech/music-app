import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The signature animated AI DJ orb — multi-radial gradient sphere with a
/// glassy highlight, an outer glass border, three concentric rings, and
/// `spin` + `breathe` animations. Matches `.orb` from `styles.css`.
class AiDjOrb extends StatefulWidget {
  const AiDjOrb({
    super.key,
    this.size = 220,
    this.animated = true,
  });

  final double size;
  final bool animated;

  @override
  State<AiDjOrb> createState() => _AiDjOrbState();
}

class _AiDjOrbState extends State<AiDjOrb>
    with TickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 12),
  )..repeat();

  late final AnimationController _breathe = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 4),
  )..repeat(reverse: true);

  @override
  void didUpdateWidget(covariant AiDjOrb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animated) {
      if (!_spin.isAnimating) _spin.repeat();
      if (!_breathe.isAnimating) _breathe.repeat(reverse: true);
    } else {
      _spin.stop();
      _breathe.stop();
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    _breathe.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size + 104, // room for the outer rings
      height: widget.size + 104,
      child: AnimatedBuilder(
        animation: Listenable.merge([_spin, _breathe]),
        builder: (context, _) {
          final breathe = 1.0 + 0.04 *
              (0.5 - 0.5 *
                  (1 - 2 * (_breathe.value < 0.5 ? _breathe.value : 1 - _breathe.value))
                      .abs());
          return Stack(
            alignment: Alignment.center,
            children: [
              _Ring(diameter: widget.size + 104, opacity: 0.3, scale: breathe),
              _Ring(diameter: widget.size + 64, opacity: 0.6, scale: breathe),
              _Ring(diameter: widget.size + 32, opacity: 1.0, scale: breathe),
              Transform.scale(
                scale: 1.0 + 0.05 * (_spin.value * 2 - 1).abs(),
                child: Transform.rotate(
                  angle: _spin.value * 6.28318530718,
                  child: _OrbBody(size: widget.size),
                ),
              ),
              _OrbHighlight(size: widget.size, scale: 2.0 - breathe),
            ],
          );
        },
      ),
    );
  }
}

class _OrbBody extends StatelessWidget {
  const _OrbBody({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: LumenTokens.orbDeep,
          boxShadow: [
            BoxShadow(
              color: LumenTokens.orbViolet.withValues(alpha: 0.6),
              blurRadius: 80,
            ),
            BoxShadow(
              color: LumenTokens.orbPink.withValues(alpha: 0.35),
              blurRadius: 160,
            ),
          ],
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  center: const Alignment(-0.4, -0.5),
                  radius: 0.7,
                  colors: [
                    LumenTokens.orbViolet,
                    Colors.transparent,
                  ],
                  stops: const [0.0, 1.0],
                ),
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  center: const Alignment(0.4, 0.4),
                  radius: 0.7,
                  colors: [
                    LumenTokens.orbPink,
                    Colors.transparent,
                  ],
                  stops: const [0.0, 1.0],
                ),
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  center: const Alignment(0.2, -0.4),
                  radius: 0.55,
                  colors: [
                    LumenTokens.orbCyan,
                    Colors.transparent,
                  ],
                  stops: const [0.0, 1.0],
                ),
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  center: const Alignment(-0.4, 0.4),
                  radius: 0.55,
                  colors: [
                    LumenTokens.orbGold,
                    Colors.transparent,
                  ],
                  stops: const [0.0, 1.0],
                ),
              ),
            ),
            // Inner soft highlight
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  center: Alignment.center,
                  radius: 0.95,
                  colors: [
                    Colors.white.withValues(alpha: 0.15),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OrbHighlight extends StatelessWidget {
  const _OrbHighlight({required this.size, required this.scale});

  final double size;
  final double scale;

  @override
  Widget build(BuildContext context) {
    return Transform.scale(
      scale: scale,
      child: SizedBox(
        width: size,
        height: size,
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.2),
              width: 1,
            ),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withValues(alpha: 0.35),
                Colors.transparent,
                Colors.transparent,
                Colors.white.withValues(alpha: 0.08),
              ],
              stops: const [0.0, 0.3, 0.7, 1.0],
            ),
          ),
        ),
      ),
    );
  }
}

class _Ring extends StatelessWidget {
  const _Ring({
    required this.diameter,
    required this.opacity,
    required this.scale,
  });

  final double diameter;
  final double opacity;
  final double scale;

  @override
  Widget build(BuildContext context) {
    return Transform.scale(
      scale: scale,
      child: SizedBox(
        width: diameter,
        height: diameter,
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.12 * opacity),
              width: 1,
            ),
          ),
        ),
      ),
    );
  }
}
