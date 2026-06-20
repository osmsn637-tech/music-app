import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

/// Whether the desktop window is collapsed into the floating mini-player.
final miniModeProvider = StateProvider<bool>((_) => false);

/// Drives the native window between the full app and a small always-on-top
/// mini-player widget. macOS/Windows/Linux only (gated by the desktop shell).
class WindowMode {
  const WindowMode._();

  // Square cover (~272) on top + the controls strip below it. The extra
  // height over (272 + strip) covers the ~31px macOS reserves for the
  // (hidden) title-bar region, so the cover isn't squeezed. The cover flexes
  // in the layout, so an imperfect estimate can't overflow.
  static const Size _mini = Size(272, 430);
  static const Size _miniWithQueue = Size(272, 560);
  static const Size _full = Size(1040, 720);

  // Remembered top-left positions so each mode reopens where you left it,
  // instead of snapping to a fixed corner / re-centring every time.
  static Offset? _fullPos;
  static Offset? _miniPos;

  /// Collapse to the floating mini-player.
  static Future<void> enterMini(WidgetRef ref) async {
    // Remember where the full window is so exitMini can put it back.
    try {
      _fullPos = await windowManager.getPosition();
    } catch (_) {}
    ref.read(miniModeProvider.notifier).state = true;
    await windowManager.setResizable(false);
    await windowManager.setMinimumSize(const Size(240, 240));
    await windowManager.setMaximumSize(const Size(600, 620));
    await windowManager.setSize(_mini);
    await windowManager.setAlwaysOnTop(true);
    await windowManager.setTitleBarStyle(
      TitleBarStyle.hidden,
      windowButtonVisibility: false,
    );
    // Reopen the mini where it was last dragged; first time → bottom-right.
    if (_miniPos != null) {
      await windowManager.setPosition(_miniPos!);
    } else {
      await windowManager.setAlignment(Alignment.bottomRight);
    }
  }

  /// Restore the full windowed app.
  static Future<void> exitMini(WidgetRef ref) async {
    // Remember where the mini window is so the next enterMini reopens there.
    try {
      _miniPos = await windowManager.getPosition();
    } catch (_) {}
    await windowManager.setAlwaysOnTop(false);
    // Frameless Spotify-style window: hidden title bar, traffic lights kept.
    await windowManager.setTitleBarStyle(
      TitleBarStyle.hidden,
      windowButtonVisibility: true,
    );
    await windowManager.setMaximumSize(const Size(10000, 10000));
    await windowManager.setResizable(true);
    await windowManager.setMinimumSize(const Size(720, 480));
    await windowManager.setSize(_full);
    // Put the full window back where it was before minimizing; if we never
    // captured a position, fall back to centring.
    if (_fullPos != null) {
      await windowManager.setPosition(_fullPos!);
    } else {
      await windowManager.center();
    }
    ref.read(miniModeProvider.notifier).state = false;
  }

  /// Grow/shrink the mini-player to reveal or hide the inline queue.
  static Future<void> setQueueOpen(bool open) async {
    await windowManager.setSize(open ? _miniWithQueue : _mini);
  }
}
