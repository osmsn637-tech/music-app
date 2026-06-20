import 'package:flutter/widgets.dart';

/// Drives the single unified player widget between its mini form
/// (`value == 0`) and its full-screen form (`value == 1`).
///
/// Replaces the previous "two screens + Hero morph + route push" model:
/// there is now exactly one player widget tree in the app, hosted by
/// `HomeShell`, and any caller that used to push the full player route
/// instead calls [expand] on this controller.
///
/// The controller is owned by [PlayerExpansionScope] (which provides the
/// `TickerProvider`) and discovered by descendants via `of(context)` /
/// `read(context)`.
class PlayerExpansionController extends ChangeNotifier {
  PlayerExpansionController({required TickerProvider vsync}) {
    _ac = AnimationController(
      vsync: vsync,
      duration: const Duration(milliseconds: 360),
      reverseDuration: const Duration(milliseconds: 320),
      lowerBound: 0.0,
      upperBound: 1.0,
    )..addListener(_onTick);
  }

  late final AnimationController _ac;

  /// Vertical drag distance, in logical pixels, that covers the full
  /// collapse from full → mini. A drag of this many pixels downward at
  /// `value == 1` lands at `value == 0`. Tuned to roughly the height of
  /// the artwork panel.
  static const double dragDistance = 360;

  /// Current expansion value, 0..1.
  double get value => _ac.value;

  /// True once the player is past the half-point — used by the GestureDetector
  /// in the mini form to flip from "tap-to-expand" to "drag-to-collapse".
  bool get isExpanded => value >= 0.5;

  /// Direct access to the underlying animation for places that want to
  /// drive `AnimatedBuilder` etc. The public surface is the controller,
  /// though — prefer that.
  AnimationController get animation => _ac;

  void _onTick() => notifyListeners();

  /// Animate from mini → full.
  Future<void> expand() async {
    if (_ac.value >= 0.999) return;
    await _ac.animateTo(1.0, curve: Curves.easeOutCubic);
  }

  /// Animate from full → mini.
  Future<void> collapse() async {
    if (_ac.value <= 0.001) return;
    await _ac.animateBack(0.0, curve: Curves.easeOutCubic);
  }

  /// Snap to mini form with no animation. Used when there's no song
  /// playing — the host hides the player entirely in that case, and we
  /// want it to be in mini form ready for the next tap-to-expand.
  void reset() {
    _ac.value = 0;
  }

  /// Pixel-driven drag update. [deltaY] is the finger's vertical delta
  /// in screen pixels — positive means downward (toward mini).
  void dragBy(double deltaY) {
    final next = (_ac.value - deltaY / dragDistance).clamp(0.0, 1.0);
    _ac.value = next;
  }

  /// Release. Velocity is in pixels/sec along Y. Positive = downward.
  /// Flicks above the velocity threshold commit regardless of position.
  Future<void> endDrag({required double velocity}) async {
    const flick = 800.0;
    final double target;
    if (velocity > flick) {
      target = 0.0;
    } else if (velocity < -flick) {
      target = 1.0;
    } else {
      target = _ac.value >= 0.5 ? 1.0 : 0.0;
    }
    if ((target - _ac.value).abs() < 0.001) return;
    if (target > _ac.value) {
      await _ac.animateTo(target, curve: Curves.easeOutCubic);
    } else {
      await _ac.animateBack(target, curve: Curves.easeOutCubic);
    }
  }

  @override
  void dispose() {
    _ac.removeListener(_onTick);
    _ac.dispose();
    super.dispose();
  }
}

/// `InheritedNotifier` host for [PlayerExpansionController]. Wrap this
/// around the home shell once — descendants reach the controller via
/// `PlayerExpansionScope.of(context)` (subscribing) or `.read(context)`
/// (one-shot).
class PlayerExpansionScope extends StatefulWidget {
  const PlayerExpansionScope({super.key, required this.child});

  final Widget child;

  /// Subscribing access — the calling widget will rebuild on every
  /// expansion tick. Use this inside `build` to read [value].
  static PlayerExpansionController of(BuildContext context) {
    final inh = context
        .dependOnInheritedWidgetOfExactType<_PlayerExpansionInherited>();
    assert(inh != null, 'PlayerExpansionScope.of called outside the scope');
    return inh!.controller;
  }

  /// One-shot access — does NOT subscribe to changes. Use for callbacks
  /// like `onTap: () => PlayerExpansionScope.read(context).expand()`.
  static PlayerExpansionController read(BuildContext context) {
    final inh = context
        .getInheritedWidgetOfExactType<_PlayerExpansionInherited>();
    assert(inh != null, 'PlayerExpansionScope.read called outside the scope');
    return inh!.controller;
  }

  /// Like [read] but tolerates the scope being absent — returns null
  /// instead of asserting. Pushed routes (settings, sync, playlist
  /// detail) live above the home shell, so the scope isn't an ancestor
  /// there; widgets that merely want to pause work when the player
  /// covers them (e.g. [StageBackground]) use this to stay mountable
  /// anywhere.
  static PlayerExpansionController? maybeRead(BuildContext context) {
    return context
        .getInheritedWidgetOfExactType<_PlayerExpansionInherited>()
        ?.controller;
  }

  @override
  State<PlayerExpansionScope> createState() => _PlayerExpansionScopeState();
}

class _PlayerExpansionScopeState extends State<PlayerExpansionScope>
    with SingleTickerProviderStateMixin {
  late final PlayerExpansionController _controller;

  @override
  void initState() {
    super.initState();
    _controller = PlayerExpansionController(vsync: this);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _PlayerExpansionInherited(
      controller: _controller,
      child: widget.child,
    );
  }
}

class _PlayerExpansionInherited
    extends InheritedNotifier<PlayerExpansionController> {
  const _PlayerExpansionInherited({
    required PlayerExpansionController controller,
    required super.child,
  }) : super(notifier: controller);

  PlayerExpansionController get controller => notifier!;
}
