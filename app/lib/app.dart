import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'core/constants/app_constants.dart';
import 'ui/screens/desktop_shell.dart';
import 'ui/screens/home_shell.dart';
import 'ui/theme/app_theme.dart';

class MusicApp extends StatelessWidget {
  const MusicApp({super.key});

  /// Desktop platforms (macOS / Windows / Linux) get the sidebar-based
  /// [DesktopShell]; phones keep the floating-nav [HomeShell].
  static bool get _isDesktop {
    if (kIsWeb) return false;
    switch (defaultTargetPlatform) {
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
      case TargetPlatform.linux:
        return true;
      default:
        return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Dark-only: the whole app (glass, blooms, stage, wallpapers) is
    // designed for a dark stage, so we render the dark theme always.
    return MaterialApp(
      title: AppConstants.appName,
      theme: AppTheme.dark(),
      themeMode: ThemeMode.dark,
      home: _isDesktop ? const DesktopShell() : const HomeShell(),
      debugShowCheckedModeBanner: true,
    );
  }
}
