import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Renders a square album cover. Uses the song's local artwork file if
/// present; otherwise generates a deterministic glassy gradient seeded by
/// [seed] so the same song always shows the same fallback.
class AlbumArt extends StatelessWidget {
  const AlbumArt({
    super.key,
    this.artworkPath,
    required this.seed,
    this.size = 56,
    this.radius = 12,
  });

  final String? artworkPath;
  final String seed;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final useFile = artworkPath != null && File(artworkPath!).existsSync();
    return SizedBox(
      width: size,
      height: size,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (useFile)
              Image.file(File(artworkPath!), fit: BoxFit.cover)
            else
              CustomPaint(painter: _GradientArt(seed: seed)),
            // Diagonal soft-light overlay
            const _ArtShine(),
          ],
        ),
      ),
    );
  }
}

class _ArtShine extends StatelessWidget {
  const _ArtShine();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(-0.5, -0.7),
            radius: 0.7,
            colors: [
              Colors.white.withValues(alpha: 0.4),
              Colors.transparent,
            ],
            stops: const [0.0, 0.35],
          ),
          backgroundBlendMode: BlendMode.overlay,
        ),
      ),
    );
  }
}

class _GradientArt extends CustomPainter {
  _GradientArt({required this.seed});

  final String seed;

  static const _palette = [
    [Color(0xFF2A1F5E), LumenTokens.orbViolet, LumenTokens.orbPink],
    [Color(0xFF0F2027), Color(0xFF2C5364), Color(0xFF6DD5FA)],
    [Color(0xFF134E5E), Color(0xFF71B280), Color(0xFFB8E994)],
    [Color(0xFF6A0572), Color(0xFFAB83A1), Color(0xFFFFB7B2)],
    [Color(0xFF430089), Color(0xFF82FFA1), Color(0xFFB2FFEE)],
    [Color(0xFF1F1C2C), Color(0xFF928DAB), Color(0xFFE0CFCF)],
    [Color(0xFF8E2DE2), Color(0xFF4A00E0), Color(0xFF8E54E9)],
    [Color(0xFF1A2980), Color(0xFF26D0CE), Color(0xFFE0F7FA)],
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final hash = seed.hashCode.abs();
    final palette = _palette[hash % _palette.length];
    final rng = math.Random(hash);
    final rect = Offset.zero & size;

    // Base radial gradient
    final paint1 = Paint()
      ..shader = RadialGradient(
        center: Alignment(rng.nextDouble() * 1.4 - 0.7,
            rng.nextDouble() * 1.4 - 0.7),
        radius: 0.9 + rng.nextDouble() * 0.4,
        colors: [palette[2], palette[0]],
      ).createShader(rect);
    canvas.drawRect(rect, paint1);

    // Secondary blob
    final paint2 = Paint()
      ..shader = RadialGradient(
        center: Alignment(rng.nextDouble() * 1.4 - 0.7,
            rng.nextDouble() * 1.4 - 0.7),
        radius: 0.5 + rng.nextDouble() * 0.3,
        colors: [palette[1].withValues(alpha: 0.85), Colors.transparent],
      ).createShader(rect);
    canvas.drawRect(rect, paint2);
  }

  @override
  bool shouldRepaint(covariant _GradientArt oldDelegate) =>
      oldDelegate.seed != seed;
}
