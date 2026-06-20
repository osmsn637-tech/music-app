import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../features/ai_dj/dj_mode.dart';

class SettingsService {
  SettingsService(this._prefs);

  final SharedPreferences _prefs;

  static const _kServerUrl = 'server_url';
  static const _kDjVoice = 'dj_voice_enabled';
  static const _kDefaultDjMode = 'default_dj_mode';
  static const _kConnectUrl = 'connect_url';
  static const _kRoomCode = 'connect_room_code';
  static const _kDeviceName = 'connect_device_name';
  static const _kDeviceId = 'connect_device_id';

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

  // --- Live Connect ------------------------------------------------------

  /// Defaults so a fresh install auto-joins the deployed handoff room with no
  /// setup. Both are overridable in Settings → Live Connect (and the room
  /// code is rotated server-side via `flyctl secrets set ROOM_CODE=...`).
  static const _defaultConnectUrl = 'wss://flacko-connect.fly.dev/ws';
  static const _defaultRoomCode = 'f532aa0c5d9d6960';

  /// WebSocket URL of the handoff service. Falls back to the deployed Fly
  /// endpoint when the user hasn't set a custom one.
  String? get connectUrl => _prefs.getString(_kConnectUrl) ?? _defaultConnectUrl;

  Future<void> setConnectUrl(String value) async {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      await _prefs.remove(_kConnectUrl);
      return;
    }
    await _prefs.setString(
      _kConnectUrl,
      trimmed.replaceAll(RegExp(r'/+$'), ''),
    );
  }

  /// Shared pairing code; all the user's devices use the same one to join the
  /// same Connect room. Falls back to the deployed room's code so devices
  /// pair out of the box.
  String? get roomCode => _prefs.getString(_kRoomCode) ?? _defaultRoomCode;

  Future<void> setRoomCode(String value) async {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      await _prefs.remove(_kRoomCode);
      return;
    }
    await _prefs.setString(_kRoomCode, trimmed);
  }

  /// Human label shown in other devices' pickers. Defaults from the platform.
  String get deviceName {
    final v = _prefs.getString(_kDeviceName);
    return (v != null && v.isNotEmpty) ? v : _defaultDeviceName();
  }

  Future<void> setDeviceName(String value) async {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      await _prefs.remove(_kDeviceName);
      return;
    }
    await _prefs.setString(_kDeviceName, trimmed);
  }

  /// Stable per-install id used to recognize this device across reconnects
  /// and to ignore our own echoes. Generated once on first read.
  String get deviceId {
    var id = _prefs.getString(_kDeviceId);
    if (id == null || id.isEmpty) {
      id = const Uuid().v4();
      _prefs.setString(_kDeviceId, id); // cached in-memory immediately
    }
    return id;
  }

  String _defaultDeviceName() {
    if (kIsWeb) return 'Browser';
    switch (defaultTargetPlatform) {
      case TargetPlatform.macOS:
        return 'Mac';
      case TargetPlatform.iOS:
        return 'iPhone';
      case TargetPlatform.android:
        return 'Android phone';
      case TargetPlatform.windows:
        return 'Windows PC';
      case TargetPlatform.linux:
        return 'Linux PC';
      default:
        return 'My device';
    }
  }
}
