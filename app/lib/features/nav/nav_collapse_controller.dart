import 'package:flutter/material.dart';

/// Drives the floating nav bar's expanded↔collapsed morph and exposes
/// it to the [ExpandingPlayer] (so the mini-player rect can interpolate
/// in sync). value=0 → expanded (mini-player sits on its own row above
/// the tab pill); value=1 → collapsed (mini-player is inline between
/// the tab pill and search button on a single row, and the inactive
/// pill tabs have slid into the active one).
class NavCollapseController extends ChangeNotifier {
  NavCollapseController({required TickerProvider vsync})
      : _controller = AnimationController(
          vsync: vsync,
          duration: const Duration(milliseconds: 320),
          value: 0,
        ) {
    _controller.addListener(notifyListeners);
  }

  final AnimationController _controller;

  double get value => _controller.value;
  Animation<double> get animation => _controller.view;
  bool get isCollapsed => _controller.value > 0.5;

  void expand() {
    _controller.animateTo(
      0,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  void collapse() {
    _controller.animateTo(
      1,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  void setCollapsed(bool collapsed) =>
      collapsed ? collapse() : expand();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

/// InheritedWidget exposing the [NavCollapseController] to descendants.
/// The ExpandingPlayer reads this so its mini rect (and chrome) can
/// interpolate to the inline layout when the nav collapses.
class NavCollapseScope extends InheritedWidget {
  const NavCollapseScope({
    super.key,
    required this.controller,
    required super.child,
  });

  final NavCollapseController controller;

  static NavCollapseController of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<NavCollapseScope>();
    assert(scope != null, 'NavCollapseScope not found in widget tree');
    return scope!.controller;
  }

  static NavCollapseController read(BuildContext context) {
    final scope =
        context.getInheritedWidgetOfExactType<NavCollapseScope>();
    assert(scope != null, 'NavCollapseScope not found in widget tree');
    return scope!.controller;
  }

  @override
  bool updateShouldNotify(NavCollapseScope oldWidget) =>
      controller != oldWidget.controller;
}
