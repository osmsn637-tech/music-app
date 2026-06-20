import 'package:flutter/widgets.dart';

import '../theme/app_theme.dart';
import 'reduced_motion.dart';

/// Canonical press affordance — gently scales down while held, springs back on
/// release. The app renders with NoSplash, so this (not ink ripples) is the
/// tactile feedback for every tappable surface. [Pressable] delegates here.
class ScaleTap extends StatefulWidget {
  const ScaleTap({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.pressedScale = 0.96,
    this.duration = LumenTokens.mInstant,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double pressedScale;
  final Duration duration;

  @override
  State<ScaleTap> createState() => _ScaleTapState();
}

class _ScaleTapState extends State<ScaleTap> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    // Inert when there's nothing to do — matches the old Pressable contract.
    if (widget.onTap == null && widget.onLongPress == null) return widget.child;
    final reduce = reducedMotion(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      onTapDown: reduce ? null : (_) => _set(true),
      onTapUp: reduce ? null : (_) => _set(false),
      onTapCancel: reduce ? null : () => _set(false),
      child: AnimatedScale(
        scale: _down ? widget.pressedScale : 1.0,
        duration: widget.duration,
        curve: LumenTokens.lumenDecelerate,
        child: widget.child,
      ),
    );
  }
}
