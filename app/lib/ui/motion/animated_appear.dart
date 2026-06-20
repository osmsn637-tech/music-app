import 'package:flutter/widgets.dart';

import '../theme/app_theme.dart';
import 'reduced_motion.dart';

/// One-shot entrance: fades — and optionally slides up / scales in — on first
/// build, then rests. Idempotent: only animates once, so it's safe inside
/// rebuilding parents (but NOT inside recycled list builders — gate those with
/// [StaggeredAppear.animate] = false).
class AnimatedAppear extends StatefulWidget {
  const AnimatedAppear({
    super.key,
    required this.child,
    this.duration = LumenTokens.mBase,
    this.delay = Duration.zero,
    this.offsetY = 12,
    this.scale = false,
    this.curve = LumenTokens.lumenDecelerate,
  });

  final Widget child;
  final Duration duration;
  final Duration delay;
  final double offsetY;
  final bool scale;
  final Curve curve;

  @override
  State<AnimatedAppear> createState() => _AnimatedAppearState();
}

class _AnimatedAppearState extends State<AnimatedAppear>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: widget.duration,
  );
  late final Animation<double> _a = CurvedAnimation(
    parent: _c,
    curve: widget.curve,
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (reducedMotion(context)) {
      _c.value = 1.0;
    } else if (widget.delay == Duration.zero) {
      _c.forward();
    } else {
      Future<void>.delayed(widget.delay, () {
        if (mounted) _c.forward();
      });
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _a,
      child: widget.child,
      builder: (context, child) {
        final t = _a.value.clamp(0.0, 1.0);
        Widget out = Opacity(opacity: t, child: child);
        if (widget.offsetY != 0) {
          out = Transform.translate(
            offset: Offset(0, (1 - t) * widget.offsetY),
            child: out,
          );
        }
        if (widget.scale) {
          out = Transform.scale(scale: 0.96 + 0.04 * t, child: out);
        }
        return out;
      },
    );
  }
}
