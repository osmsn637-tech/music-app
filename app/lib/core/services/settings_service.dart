import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/ai_dj/dj_mode.dart';

class SettingsService {
  SettingsService(this._prefs);

  final SharedPreferences _prefs;

  static const _kServerUrl = 'server_url';
  static const _kThemeMode = 'theme_mode';
  static const _kDjVoice = 'dj_voice_enabled';
  static const _kDefaultDjMode = 'default_dj_mode';
  static const _kLiveWallpaper = 'live_wallpaper_enabled';

  // --- server URL --------------------------------------------------------

  String? get serverUrl => _prefs.getString(_kServerUrl);

  Future<void> setServerUrl(String value) async {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      await _prefs.remove(_kServerUrl);
      return;
    }
    final normalized = trimmed.replaceAll(RegExp(r'/+$'), '');
    await _prefs.setString(_kServerUrl, normalized);
  }

  // --- theme -------------------------------------------------------------

  ThemeMode get themeMode {
    switch (_prefs.getString(_kThemeMode)) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    final value = switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    };
    await _prefs.setString(_kThemeMode, value);
  }

  // --- DJ voice ----------------------------------------------------------

  bool get djVoiceEnabled => _prefs.getBool(_kDjVoice) ?? false;

  Future<void> setDjVoiceEnabled(bool value) async {
    await _prefs.setBool(_kDjVoice, value);
  }

  // --- default DJ mode --------------------------------------------------

  DjMode get defaultDjMode {
    final id = _prefs.getString(_kDefaultDjMode);
    return DjMode.values.firstWhere(
      (m) => m.id == id,
      orElse: () => DjMode.smartShuffle,
    );
  }

  Future<void> setDefaultDjMode(DjMode mode) async {
    await _prefs.setString(_kDefaultDjMode, mode.id);
  }

  // --- live wallpaper ----------------------------------------------------

  /// Whether the home shell uses the multi-blob interactive background
  /// (touch-reactive, breathing) instead of the minimal two-blob stage.
  /// Default: on — it's the design's signature.
  bool get liveWallpaperEnabled => _prefs.getBool(_kLiveWallpaper) ?? true;

  Future<void> setLiveWallpaperEnabled(bool value) async {
    await _prefs.setBool(_kLiveWallpaper, value);
  }
}
