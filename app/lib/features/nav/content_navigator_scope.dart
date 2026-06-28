import 'package:flutter/widgets.dart';

/// Exposes a shell's content-area inner [Navigator] key so callers that sit
/// OUTSIDE that Navigator — e.g. a modal sheet on the root overlay
/// (SongActionsSheet), or the desktop sidebar / player bar — can still push
/// detail pages INTO the inner content stack instead of full-covering the
/// shell chrome (nav + player). Both the mobile and desktop shells provide it.
class ContentNavigatorScope extends InheritedWidget {
  const ContentNavigatorScope({
    super.key,
    required this.navKey,
    this.overlaysContent = true,
    required super.child,
  });

  final GlobalKey<NavigatorState> navKey;

  /// True when the persistent chrome (nav + mini player) floats OVER this
  /// content, so detail pages must reserve bottom space for it — the mobile
  /// shell. False on the desktop shell, where the player bar sits BELOW the
  /// content panel in normal layout, so pushed pages need no bottom clearance.
  final bool overlaysContent;

  static GlobalKey<NavigatorState>? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<ContentNavigatorScope>()
      ?.navKey;

  @override
  bool updateShouldNotify(ContentNavigatorScope oldWidget) =>
      navKey != oldWidget.navKey ||
      overlaysContent != oldWidget.overlaysContent;
}

/// True when persistent chrome floats OVER the content and pushed pages must
/// reserve bottom space (mobile). The desktop shell has an inner content
/// Navigator too, but lays its player bar out below the panel — so this is
/// false there and detail pages skip the mobile-sized bottom gap.
bool hasPersistentChrome(BuildContext context) =>
    context
        .dependOnInheritedWidgetOfExactType<ContentNavigatorScope>()
        ?.overlaysContent ??
    false;
