import 'package:flutter/widgets.dart';

/// Exposes the mobile shell's content-area inner [Navigator] key so callers
/// that sit OUTSIDE that Navigator — e.g. a modal sheet mounted on the root
/// overlay (SongActionsSheet) — can still push detail pages INTO the
/// persistent-chrome inner stack instead of full-covering the nav + player.
///
/// Absent on the desktop shell (which has no inner Navigator); callers must
/// fall back to `Navigator.of(context)` when [maybeOf] returns null.
class ContentNavigatorScope extends InheritedWidget {
  const ContentNavigatorScope({
    super.key,
    required this.navKey,
    required super.child,
  });

  final GlobalKey<NavigatorState> navKey;

  static GlobalKey<NavigatorState>? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<ContentNavigatorScope>()
      ?.navKey;

  @override
  bool updateShouldNotify(ContentNavigatorScope oldWidget) =>
      navKey != oldWidget.navKey;
}

/// True when the persistent mobile-shell chrome (floating nav + mini player)
/// is overlaying this page — i.e. we're inside the inner content Navigator.
/// Shared (mobile + desktop) detail pages use it to reserve bottom space (and
/// lift FABs) ONLY when that chrome exists, instead of on the desktop
/// full-cover push where it would just leave a gap.
bool hasPersistentChrome(BuildContext context) =>
    ContentNavigatorScope.maybeOf(context) != null;
