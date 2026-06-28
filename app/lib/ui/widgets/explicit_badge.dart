import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Apple-Music-style "E" explicit marker — a small rounded square with a
/// muted "E" that sits next to a song title.
class ExplicitBadge extends StatelessWidget {
  const ExplicitBadge({super.key, this.size = 16});

  /// Side length of the square box. The letter scales with it.
  final double size;

  @override
  Widget build(BuildContext context) {
    final dim = LumenTokens.fgDimOf(context);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: dim.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(size * 0.24),
      ),
      child: Text(
        'E',
        style: TextStyle(
          fontSize: size * 0.66,
          height: 1.0,
          fontWeight: FontWeight.w700,
          color: dim,
        ),
      ),
    );
  }
}
