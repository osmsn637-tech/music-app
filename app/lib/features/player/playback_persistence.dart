import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'playback_modes.dart';

/// What we persist between launches so the app can restore the last
/// session (current song + queue + position + modes) instead of coming
/// up silent and empty.
class PlaybackSnapshot {
  const PlaybackSnapshot({
    required this.queueIds,
    required this.index,
    required this.positionMs,
    required this.shuffle,
    required this.repeat,
  });

  final List<String> queueIds;
  final int index;
  final int positionMs;
  final bool shuffle;
  final QueueRepeatMode repeat;

  Map<String, dynamic> toJson() => {
    'q': queueIds,
    'i': index,
    'p': positionMs,
    's': shuffle,
    'r': repeat.index,
  };

  static PlaybackSnapshot? tryParse(String raw) {
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      final ids = (m['q'] as List).cast<String>();
      final r = (m['r'] as int?) ?? 0;
      return PlaybackSnapshot(
        queueIds: ids,
        index: (m['i'] as int?) ?? 0,
        positionMs: (m['p'] as int?) ?? 0,
        shuffle: (m['s'] as bool?) ?? false,
        repeat: QueueRepeatMode
            .values[r.clamp(0, QueueRepeatMode.values.length - 1)],
      );
    } catch (_) {
      return null;
    }
  }
}

/// Tiny SharedPreferences-backed store for the playback snapshot. Lazily
/// resolves the prefs instance so callers don't need to thread it in.
class PlaybackStateStore {
  SharedPreferences? _prefs;
  static const _key = 'playback_state_v1';

  Future<SharedPreferences> get _p async =>
      _prefs ??= await SharedPreferences.getInstance();

  Future<void> save(PlaybackSnapshot snapshot) async {
    try {
      (await _p).setString(_key, jsonEncode(snapshot.toJson()));
    } catch (_) {}
  }

  Future<PlaybackSnapshot?> load() async {
    try {
      final raw = (await _p).getString(_key);
      return raw == null ? null : PlaybackSnapshot.tryParse(raw);
    } catch (_) {
      return null;
    }
  }

  Future<void> clear() async {
    try {
      (await _p).remove(_key);
    } catch (_) {}
  }
}
