import '../../data/database/app_database.dart';
import '../../data/models/remote_artist.dart';

/// Snapshot of the user's listening behavior used to score recommendations.
class UserListeningProfile {
  UserListeningProfile({
    required this.playCountById,
    required this.completeCountById,
    required this.skipCountById,
    required this.replayCountById,
    required this.totalListenedMsById,
    required this.lastPlayedById,
    required this.favoriteSongIds,
    required this.topArtists,
    required this.topGenres,
    required this.topMoods,
    required this.contextCompleteCountById,
    required this.contextSkipCountById,
    required this.now,
  });

  final Map<String, int> playCountById;
  final Map<String, int> completeCountById;
  final Map<String, int> skipCountById;
  final Map<String, int> replayCountById;
  final Map<String, int> totalListenedMsById;
  final Map<String, DateTime> lastPlayedById;
  final Set<String> favoriteSongIds;
  final List<String> topArtists;
  final List<String> topGenres;
  final List<String> topMoods;

  /// `Map<context, Map<songId, completeCount>>`
  final Map<String, Map<String, int>> contextCompleteCountById;

  /// `Map<context, Map<songId, skipCount>>`
  final Map<String, Map<String, int>> contextSkipCountById;

  final DateTime now;

  static const _recentWindow = Duration(hours: 6);
  static const _highPlayCountThreshold = 5;
  static const _topListLength = 10;

  bool isFavorite(String songId) => favoriteSongIds.contains(songId);

  bool wasCompleted(String songId) =>
      (completeCountById[songId] ?? 0) > 0;

  bool wasReplayed(String songId) =>
      (replayCountById[songId] ?? 0) > 0;

  bool wasSkipped(String songId) =>
      (skipCountById[songId] ?? 0) >= 2; // 1 skip can be a fluke; 2+ is a pattern

  bool hasHighPlayCount(String songId) =>
      (playCountById[songId] ?? 0) >= _highPlayCountThreshold;

  bool isNeverPlayed(String songId) =>
      (playCountById[songId] ?? 0) == 0;

  bool playedRecently(String songId) {
    final last = lastPlayedById[songId];
    if (last == null) return false;
    return now.difference(last) < _recentWindow;
  }

  /// True when *any* performer named in [artist] is in the user's top three.
  /// Splits multi-artist fields ("Drake, 21 Savage", "X feat. Y") so a song
  /// where Drake is a featured guest still scores against Drake's history.
  bool isFavoriteArtist(String? artist) {
    if (artist == null) return false;
    final names = splitMultiArtist(artist);
    if (names.isEmpty) return false;
    final top = topArtists.take(3).toSet();
    return names.any(top.contains);
  }

  /// Returns true if the user usually completes [songId] in [context].
  bool completesInContext(String songId, String context) {
    final map = contextCompleteCountById[context];
    if (map == null) return false;
    final completes = map[songId] ?? 0;
    final skips = (contextSkipCountById[context] ?? const {})[songId] ?? 0;
    return completes >= 2 && completes > skips;
  }

  /// Builds a profile by querying the DB.
  static Future<UserListeningProfile> load(AppDatabase db) async {
    final stats = await db.select(db.songStats).get();
    final songs = await db.select(db.songs).get();
    final ctxStats = await db.select(db.contextStats).get();

    final playCount = <String, int>{};
    final completeCount = <String, int>{};
    final skipCount = <String, int>{};
    final replayCount = <String, int>{};
    final totalMs = <String, int>{};
    final lastPlayed = <String, DateTime>{};
    for (final s in stats) {
      playCount[s.songId] = s.playCount;
      completeCount[s.songId] = s.completeCount;
      skipCount[s.songId] = s.skipCount;
      replayCount[s.songId] = s.replayCount;
      totalMs[s.songId] = s.totalListenedMs;
      if (s.lastPlayedAt != null) {
        final parsed = DateTime.tryParse(s.lastPlayedAt!);
        if (parsed != null) lastPlayed[s.songId] = parsed;
      }
    }

    final favorites = songs
        .where((s) => s.isFavorite == 1)
        .map((s) => s.id)
        .toSet();

    final ctxComplete = <String, Map<String, int>>{};
    final ctxSkip = <String, Map<String, int>>{};
    for (final c in ctxStats) {
      (ctxComplete[c.context] ??= {})[c.songId] = c.completeCount;
      (ctxSkip[c.context] ??= {})[c.songId] = c.skipCount;
    }

    return UserListeningProfile(
      playCountById: playCount,
      completeCountById: completeCount,
      skipCountById: skipCount,
      replayCountById: replayCount,
      totalListenedMsById: totalMs,
      lastPlayedById: lastPlayed,
      favoriteSongIds: favorites,
      topArtists: _topByMultiKey(
        songs,
        weight: (s) => completeCount[s.id] ?? 0,
        keysOf: (s) => splitMultiArtist(s.artist),
      ),
      topGenres: _topByCount(
        songs,
        weight: (s) => completeCount[s.id] ?? 0,
        keyOf: (s) => s.genre,
      ),
      topMoods: _topByCount(
        songs,
        weight: (s) => completeCount[s.id] ?? 0,
        keyOf: (s) => s.mood,
      ),
      contextCompleteCountById: ctxComplete,
      contextSkipCountById: ctxSkip,
      now: DateTime.now(),
    );
  }

  static List<String> _topByCount(
    List<SongRow> songs, {
    required int Function(SongRow) weight,
    required String? Function(SongRow) keyOf,
  }) {
    final counts = <String, int>{};
    for (final s in songs) {
      final k = keyOf(s);
      if (k == null || k.isEmpty) continue;
      counts[k] = (counts[k] ?? 0) + weight(s);
    }
    final ranked = counts.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return ranked.take(_topListLength).map((e) => e.key).toList();
  }

  /// Variant of [_topByCount] for fields that hold *multiple* keys per
  /// song — currently just the artist field, where "Drake, 21 Savage"
  /// should credit both names rather than bucket them as one combined
  /// "artist". Each returned key gets the song's full weight (a complete
  /// of a duet counts as one for each performer).
  static List<String> _topByMultiKey(
    List<SongRow> songs, {
    required int Function(SongRow) weight,
    required Iterable<String> Function(SongRow) keysOf,
  }) {
    final counts = <String, int>{};
    for (final s in songs) {
      final w = weight(s);
      if (w == 0) continue;
      for (final k in keysOf(s)) {
        if (k.isEmpty) continue;
        counts[k] = (counts[k] ?? 0) + w;
      }
    }
    final ranked = counts.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return ranked.take(_topListLength).map((e) => e.key).toList();
  }

  /// Empty profile for first-run / no listening history yet.
  factory UserListeningProfile.empty() {
    return UserListeningProfile(
      playCountById: const {},
      completeCountById: const {},
      skipCountById: const {},
      replayCountById: const {},
      totalListenedMsById: const {},
      lastPlayedById: const {},
      favoriteSongIds: const {},
      topArtists: const [],
      topGenres: const [],
      topMoods: const [],
      contextCompleteCountById: const {},
      contextSkipCountById: const {},
      now: DateTime.now(),
    );
  }
}

