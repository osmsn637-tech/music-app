import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/ai_dj/dj_mode.dart';
import 'settings_service.dart';

final sharedPreferencesProvider = FutureProvider<SharedPreferences>((ref) {
  return SharedPreferences.getInstance();
});

final settingsServiceProvider = FutureProvider<SettingsService>((ref) async {
  final prefs = await ref.watch(sharedPreferencesProvider.future);
  return SettingsService(prefs);
});

final serverUrlProvider = FutureProvider<String?>((ref) async {
  final settings = await ref.watch(settingsServiceProvider.future);
  return settings.serverUrl;
});

/// Reactive theme mode. Hydrates from SharedPreferences on first read.
class ThemeModeController extends StateNotifier<ThemeMode> {
  ThemeModeController(this._ref) : super(ThemeMode.system) {
    _hydrate();
  }
  final Ref _ref;

  Future<void> _hydrate() async {
    final settings = await _ref.read(settingsServiceProvider.future);
    state = settings.themeMode;
  }

  Future<void> set(ThemeMode mode) async {
    state = mode;
    final settings = await _ref.read(settingsServiceProvider.future);
    await settings.setThemeMode(mode);
  }
}

final themeModeProvider =
    StateNotifierProvider<ThemeModeController, ThemeMode>((ref) {
  return ThemeModeController(ref);
});

/// Reactive DJ-voice toggle. Now a simple bool gating the offline voice bank
/// — when off, the queue controller skips the bank lookup entirely and
/// transitions are silent. No TTS path remains.
class DjVoiceController extends StateNotifier<bool> {
  DjVoiceController(this._ref) : super(false) {
    _hydrate();
  }
  final Ref _ref;

  Future<void> _hydrate() async {
    final settings = await _ref.read(settingsServiceProvider.future);
    state = settings.djVoiceEnabled;
  }

  Future<void> set(bool value) async {
    state = value;
    final settings = await _ref.read(settingsServiceProvider.future);
    await settings.setDjVoiceEnabled(value);
  }
}

final djVoiceProvider =
    StateNotifierProvider<DjVoiceController, bool>((ref) {
  return DjVoiceController(ref);
});

/// Default DJ mode used the first time AI DJ opens in a session.
class DefaultDjModeController extends StateNotifier<DjMode> {
  DefaultDjModeController(this._ref) : super(DjMode.smartShuffle) {
    _hydrate();
  }
  final Ref _ref;

  Future<void> _hydrate() async {
    final settings = await _ref.read(settingsServiceProvider.future);
    state = settings.defaultDjMode;
  }

  Future<void> set(DjMode mode) async {
    state = mode;
    final settings = await _ref.read(settingsServiceProvider.future);
    await settings.setDefaultDjMode(mode);
  }
}

final defaultDjModeProvider =
    StateNotifierProvider<DefaultDjModeController, DjMode>((ref) {
  return DefaultDjModeController(ref);
});

/// Toggle for the interactive multi-blob background. Off falls back to the
/// minimal two-blob stage so the glass surfaces read more clearly.
class LiveWallpaperController extends StateNotifier<bool> {
  LiveWallpaperController(this._ref) : super(true) {
    _hydrate();
  }
  final Ref _ref;

  Future<void> _hydrate() async {
    final settings = await _ref.read(settingsServiceProvider.future);
    state = settings.liveWallpaperEnabled;
  }

  Future<void> set(bool value) async {
    state = value;
    final settings = await _ref.read(settingsServiceProvider.future);
    await settings.setLiveWallpaperEnabled(value);
  }
}

final liveWallpaperProvider =
    StateNotifierProvider<LiveWallpaperController, bool>((ref) {
  return LiveWallpaperController(ref);
});
