import 'package:flutter/material.dart';

/// Scroll behavior for pages with a top hero image (Home, Artist).
///
/// Clamps the scroll position at the edges so the leading content never pulls
/// away to reveal the page background on an over-pull, and replaces the
/// platform bounce/glow with a STRETCH overscroll on every platform — so the
/// hero stays pinned to the top and the content stretches in place like a
/// rubber band instead of detaching and exposing the background behind it.
class StretchScrollBehavior extends MaterialScrollBehavior {
  const StretchScrollBehavior();

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return StretchingOverscrollIndicator(
      axisDirection: details.direction,
      child: child,
    );
  }

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const ClampingScrollPhysics();
}
