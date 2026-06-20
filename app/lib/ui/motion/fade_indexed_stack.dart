import 'package:flutter/widgets.dart';

import '../theme/app_theme.dart';
import 'reduced_motion.dart';

/// An [IndexedStack] that fades the visible layer in whenever [index] changes.
/// Off-screen children stay built (so scroll position, focus and in-flight
/// providers are preserved exactly like a plain IndexedStack), but a quick
/// fade cushions the swap so tab / pane changes never hard-cut.
class FadeIndexedStack extends StatefulWidget {
  const FadeIndexedStack({
    super.key,
    required this.index,
    required this.children,
    this.duration = LumenTokens.mFast,
    this.alignment = AlignmentDirectional.topStart,
    this.sizing = StackFit.loose,
  });

  final int index;
  final List<Widget> children;
  final Duration duration;
  final AlignmentGeometry alignment;
  final StackFit sizing;

  @override
  State<FadeIndexedStack> createState() => _FadeIndexedStackState();
}

class _FadeIndexedStackState extends State<FadeIndexedStack>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: widget.duration,
    value: 1,
  );
  late final Animation<double> _a = CurvedAnimation(
    parent: _c,
    curve: LumenTokens.lumenDecelerate,
  );

  @override
  void didUpdateWidget(FadeIndexedStack old) {
    super.didUpdateWidget(old);
    if (old.index != widget.index && !reducedMotion(context)) {
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _a,
      child: IndexedStack(
        index: widget.index,
        alignment: widget.alignment,
        sizing: widget.sizing,
        children: widget.children,
      ),
    );
  }
}
