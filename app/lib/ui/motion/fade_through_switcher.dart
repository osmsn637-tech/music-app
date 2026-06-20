import 'package:animations/animations.dart';
import 'package:flutter/widgets.dart';

import '../theme/app_theme.dart';
import 'reduced_motion.dart';

/// Material "fade through" between two states — the outgoing child fades + dims
/// out, the incoming fades + scales in, with no muddy cross-dissolve. The
/// [child] MUST carry a stable [Key] (e.g. `ValueKey('list')`) so the switcher
/// knows when the content actually changed.
class FadeThroughSwitcher extends StatelessWidget {
  const FadeThroughSwitcher({
    super.key,
    required this.child,
    this.duration = LumenTokens.mBase,
    this.alignment = Alignment.center,
  });

  final Widget child;
  final Duration duration;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    if (reducedMotion(context)) return child;
    return PageTransitionSwitcher(
      duration: duration,
      layoutBuilder: (entries) =>
          Stack(alignment: alignment, children: entries),
      transitionBuilder: (child, primary, secondary) => FadeThroughTransition(
        animation: primary,
        secondaryAnimation: secondary,
        fillColor: const Color(0x00000000),
        child: child,
      ),
      child: child,
    );
  }
}
