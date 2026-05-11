import 'package:drift/drift.dart';

@DataClassName('SongRow')
class Songs extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get artist => text().nullable()();
  TextColumn get album => text().nullable()();
  TextColumn get genre => text().nullable()();
  TextColumn get mood => text().nullable()();
  IntColumn get bpm => integer().nullable()();
  IntColumn get durationMs => integer().nullable()();
  TextColumn get fileName => text().nullable()();
  TextColumn get localFilePath => text()();
  TextColumn get localLyricsPath => text().nullable()();
  TextColumn get localArtworkPath => text().nullable()();
  TextColumn get searchText => text().nullable()();
  TextColumn get addedAt => text().nullable()();
  TextColumn get lastPlayedAt => text().nullable()();
  IntColumn get isFavorite => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('SongStatsRow')
class SongStats extends Table {
  TextColumn get songId => text()();
  IntColumn get playCount => integer().withDefault(const Constant(0))();
  IntColumn get completeCount => integer().withDefault(const Constant(0))();
  IntColumn get skipCount => integer().withDefault(const Constant(0))();
  IntColumn get replayCount => integer().withDefault(const Constant(0))();
  IntColumn get favoriteCount => integer().withDefault(const Constant(0))();
  IntColumn get totalListenedMs => integer().withDefault(const Constant(0))();
  TextColumn get lastPlayedAt => text().nullable()();

  @override
  Set<Column> get primaryKey => {songId};
}

@DataClassName('ListeningEventRow')
class ListeningEvents extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get songId => text()();
  TextColumn get eventType => text()();
  TextColumn get context => text().nullable()();
  IntColumn get positionMs => integer().nullable()();
  IntColumn get listenedMs => integer().nullable()();
  TextColumn get createdAt => text()();
}

@DataClassName('ContextStatsRow')
class ContextStats extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get songId => text()();
  TextColumn get context => text()();
  IntColumn get playCount => integer().withDefault(const Constant(0))();
  IntColumn get completeCount => integer().withDefault(const Constant(0))();
  IntColumn get skipCount => integer().withDefault(const Constant(0))();
  IntColumn get totalListenedMs => integer().withDefault(const Constant(0))();
}

@DataClassName('PlaylistRow')
class Playlists extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get createdAt => text()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('PlaylistSongRow')
class PlaylistSongs extends Table {
  TextColumn get playlistId => text()();
  TextColumn get songId => text()();
  IntColumn get position => integer()();

  @override
  Set<Column> get primaryKey => {playlistId, songId};
}

/// User-editable map of `original → spoken` substitutions applied to every
/// DJ TTS line before it reaches `flutter_tts`. Lets the user fix names
/// the synth pronounces wrong (e.g., "The Weeknd" → "The Weekend",
/// "SZA" → "Sizza"). [type] segments by what part of metadata the fix
/// applies to so the UI can group them; matching is global by string.
@DataClassName('PronunciationFixRow')
class PronunciationFixes extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get originalText => text()();
  TextColumn get spokenText => text()();
  // 'artist' | 'title' | 'album' | 'word' | 'acronym'
  TextColumn get type => text().withDefault(const Constant('word'))();
  TextColumn get createdAt => text()();
  TextColumn get updatedAt => text().nullable()();
}

/// Rolling log of recent DJ commentary lines so we can avoid repeating the
/// same phrasing across sessions. Pruned aggressively by row count (keep
/// last ~200) — there's no need to retain history.
@DataClassName('RecentDjLineRow')
class RecentDjLines extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get lineText => text()();
  TextColumn get intent => text().nullable()();
  TextColumn get songId => text().nullable()();
  TextColumn get mode => text().nullable()();
  TextColumn get createdAt => text()();
}

/// Memoized DJ commentary lines per `(song, mode, intent, queue position,
/// voice)`. Populated either lazily on the first matching playback or
/// eagerly via `preprocessDjSpeechForLibrary`. The composite key is
/// flattened into a single TEXT primary key so upserts are O(1) and we
/// don't need a multi-column index. Pronunciation is **not** applied to
/// `rawText` — TTS rewrites it at speak-time, so changing the user's
/// pronunciation map invalidates nothing. `spokenText` mirrors what TTS
/// would actually utter at insert-time, kept for debug / preview UIs.
/// `audioPath` reserved for a future cached-audio engine.
@DataClassName('DjSpeechCacheRow')
class DjSpeechCache extends Table {
  TextColumn get id => text()();
  TextColumn get songId => text()();
  TextColumn get mode => text()();
  TextColumn get intent => text()();
  TextColumn get queuePositionType => text()();
  TextColumn get rawText => text()();
  TextColumn get spokenText => text()();
  TextColumn get audioPath => text().nullable()();
  TextColumn get voiceId => text().nullable()();
  TextColumn get createdAt => text()();
  TextColumn get updatedAt => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
