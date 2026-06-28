import 'package:flutter/widgets.dart';

import '../theme/app_theme.dart';

/// Wraps a horizontal scroller and fades its left/right edges to
/// transparent so tiles dissolve at the screen edges instead of
/// hard-cutting. Do NOT use around content that paints a BackdropFilter
/// (e.g. the Glass widget) — the ShaderMask saveLayer breaks the blur.
class HorizontalFadeRail extends StatelessWidget {
  const HorizontalFadeRail({
    super.key,
    required this.child,
    this.fade = LumenTokens.pagePad,
  });

  final Widget child;
  final double fade;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        if (!w.isFinite || w <= fade * 2) return child;
        final stop = (fade / w).clamp(0.0, 0.5);
        return ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (rect) => LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: const [
              Color(0x00000000),
              Color(0xFF000000),
              Color(0xFF000000),
              Color(0x00000000),
            ],
            stops: [0.0, stop, 1 - stop, 1.0],
          ).createShader(rect),
          child: child,
        );
      },
    );
  }
}
