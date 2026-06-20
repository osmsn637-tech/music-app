import 'package:animations/animations.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';

import '../theme/app_theme.dart';

enum LumenAxis { horizontal, fade }

/// Smooth, platform-appropriate page route. On iOS we keep the native
/// Cupertino slide so the edge-swipe-back gesture survives; everywhere else
/// (Android / desktop) we use the animations-package shared-axis (drill-in) or
/// fade-through (peer screens like Settings / Sync).
Route<T> lumenPageRoute<T>(
  WidgetBuilder builder, {
  LumenAxis axis = LumenAxis.horizontal,
  bool fullscreenDialog = false,
}) {
  final isIOS = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
  if (isIOS) {
    return CupertinoPageRoute<T>(
      builder: builder,
      fullscreenDialog: fullscreenDialog,
    );
  }
  return PageRouteBuilder<T>(
    opaque: false, // the persistent StageBackground shows through
    fullscreenDialog: fullscreenDialog,
    transitionDuration: LumenTokens.mPage,
    reverseTransitionDuration: LumenTokens.mPageExit,
    pageBuilder: (context, _, _) => builder(context),
    transitionsBuilder: (context, anim, secondary, child) {
      switch (axis) {
        case LumenAxis.horizontal:
          return SharedAxisTransition(
            animation: anim,
            secondaryAnimation: secondary,
            transitionType: SharedAxisTransitionType.horizontal,
            fillColor: const Color(0x00000000),
            child: child,
          );
        case LumenAxis.fade:
          return FadeThroughTransition(
            animation: anim,
            secondaryAnimation: secondary,
            fillColor: const Color(0x00000000),
            child: child,
          );
      }
    },
  );
}

extension LumenNav on NavigatorState {
  Future<T?> pushLumen<T>(
    WidgetBuilder builder, {
    LumenAxis axis = LumenAxis.horizontal,
  }) => push<T>(lumenPageRoute<T>(builder, axis: axis));
}
