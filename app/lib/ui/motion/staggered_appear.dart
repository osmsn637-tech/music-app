import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../theme/app_theme.dart';
import 'animated_appear.dart';

/// Wraps a list/grid item so it fades + slides in with a small per-index delay,
/// creating a cascade as a section first paints. The delay is capped so
/// far-down items don't lag, and [animate] = false (for scroll-recycled rows
/// that would otherwise re-fire on every scroll-back) renders the child at rest.
class StaggeredAppear extends StatelessWidget {
  const StaggeredAppear({
    super.key,
    required this.index,
    required this.child,
    this.maxItems = 8,
    this.step = LumenTokens.mStaggerStep,
    this.offsetY = 14,
    this.animate = true,
  });

  final int index;
  final Widget child;
  final int maxItems;
  final Duration step;
  final double offsetY;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    if (!animate) return child;
    final capped = math.min(index, maxItems);
    return AnimatedAppear(delay: step * capped, offsetY: offsetY, child: child);
  }
}
