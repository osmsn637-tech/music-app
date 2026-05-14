import 'dart:ui';

import 'package:flutter/material.dart';

/// Frosted-glass surface — a `BackdropFilter` blur, a translucent fill,
/// hairline border, and an inner top-edge shine. Matches `.glass` and
/// `.glass-strong` from `styles.css`.
class Glass extends StatelessWidget {
  const Glass({
    super.key,
    required this.child,
    this.strong = false,
    this.borderRadius = 16,
    this.padding,
    this.blur = true,
  });

  final Widget child;
  final bool strong;
  final double borderRadius;
  final EdgeInsetsGeometry? padding;

  /// When false, skip the `BackdropFilter`. Use on panels whose content
  /// is mostly opaque — the fullscreen blur would be invisible work.
  final bool blur;

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final blurSigma = strong ? 60.0 : 40.0;
    final fill = isLight
        ? Colors.white.withValues(alpha: strong ? 0.70 : 0.55)
        : Colors.white.withValues(alpha: strong ? 0.10 : 0.06);
    final borderColor = isLight
        ? Colors.white.withValues(alpha: strong ? 0.85 : 0.70)
        : Colors.white.withValues(alpha: strong ? 0.12 : 0.08);
    // Diagonal sheen — the iOS 26 refraction trick. Brighter top-left
    // highlight, faint bottom-right glint. Pulled tighter on light mode
    // so the glass still reads as a discrete pane against cream.
    final innerHi = Colors.white.withValues(
      alpha: isLight ? (strong ? 1.0 : 0.9) : (strong ? 0.18 : 0.12),
    );
    final innerLo = isLight
        ? Colors.white.withValues(alpha: strong ? 0.55 : 0.45)
        : Colors.white.withValues(alpha: 0.05);
    // Spec shadows differ by mode — dark is heavy (deep stage), light
    // is gentle blue-purple to keep cards from looking sticker-cut.
    final shadowColor = isLight
        ? const Color(0xFF141428).withValues(alpha: strong ? 0.16 : 0.10)
        : Colors.black.withValues(alpha: strong ? 0.50 : 0.40);

    final pane = Container(
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: borderColor, width: 1),
        boxShadow: [
          BoxShadow(
            color: shadowColor,
            blurRadius: strong ? (isLight ? 40 : 48) : (isLight ? 28 : 32),
            offset: Offset(0, strong ? 12 : 8),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Refractive top-edge shine — diagonal gradient overlay.
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(borderRadius),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      innerHi,
                      Colors.transparent,
                      Colors.transparent,
                      innerLo,
                    ],
                    stops: const [0.0, 0.3, 0.7, 1.0],
                  ),
                ),
              ),
            ),
          ),
          if (padding != null)
            Padding(padding: padding!, child: child)
          else
            child,
        ],
      ),
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: blur
          ? BackdropFilter(
              filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
              child: pane,
            )
          : pane,
    );
  }
}
