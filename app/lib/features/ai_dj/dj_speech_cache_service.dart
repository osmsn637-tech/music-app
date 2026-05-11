import 'package:drift/drift.dart' show InsertMode, Value;

import '../../data/database/app_database.dart';
import 'dj_mode.dart';
import 'dj_speech_types.dart';

/// CRUD wrapper around the `dj_speech_cache` table. Holds memoized DJ
/// commentary lines so the same `(song, mode, intent, position, voice)`
/// combo doesn't re-roll the template lottery every time it plays. The
/// playback path tries this first; on miss, it generates via [DjCommentary]
/// and writes the result back here.
///
/// `rawText` is the value that will be sent to TTS — pronunciation is
/// applied at speak-time, not bake-cached, so editing the pronunciation
/// map invalidates nothing in this cache.
class DjSpeechCacheService {
  DjSpeechCacheService(this._db);

  final AppDatabase _db;

  static const String _defaultVoice = 'default';

  /// Composite-key flatten. `song|mode|intent|pos|voice` — readable in DB
  /// dumps, fast to build, no need for a multi-column unique index.
  static String keyFor({
    required String songId,
    required DjMode mode,
    required DjIntent intent,
    required QueuePositionType position,
    String? voiceId,
  }) {
    final v = (voiceId == null || voiceId.isEmpty) ? _defaultVoice : voiceId;
    return '$songId|${mode.id}|${intent.id}|${position.id}|$v';
  }

  Future<DjSpeechCacheRow?> get({
    required String songId,
    required DjMode mode,
    required DjIntent intent,
    required QueuePositionType position,
    String? voiceId,
  }) {
    final id = keyFor(
      songId: songId,
      mode: mode,
      intent: intent,
      position: position,
      voiceId: voiceId,
    );
    return (_db.select(_db.djSpeechCache)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  Future<void> put({
    required String songId,
    required DjMode mode,
    required DjIntent intent,
    required QueuePositionType position,
    required String rawText,
    required String spokenText,
    String? audioPath,
    String? voiceId,
  }) async {
    final id = keyFor(
      songId: songId,
      mode: mode,
      intent: intent,
      position: position,
      voiceId: voiceId,
    );
    final now = DateTime.now().toIso8601String();
    await _db.into(_db.djSpeechCache).insert(
          DjSpeechCacheCompanion.insert(
            id: id,
            songId: songId,
            mode: mode.id,
            intent: intent.id,
            queuePositionType: position.id,
            rawText: rawText,
            spokenText: spokenText,
            audioPath: Value(audioPath),
            voiceId: Value(voiceId ?? _defaultVoice),
            createdAt: now,
            updatedAt: const Value(null),
          ),
          mode: InsertMode.insertOrReplace,
        );
  }

  /// Drops every cached line for [songId]. Call when a song is removed,
  /// renamed, or when the user wants to regenerate just that song's lines.
  Future<int> invalidateForSong(String songId) async {
    return (_db.delete(_db.djSpeechCache)
          ..where((t) => t.songId.equals(songId)))
        .go();
  }

  /// Wipes the entire cache. Surfaced from the future training screen as
  /// a "regenerate all" button.
  Future<int> clear() {
    return _db.delete(_db.djSpeechCache).go();
  }

  /// All rows. Used by the bulk audio pre-render in the training screen
  /// to loop every cached commentary line and synthesize its audio file.
  /// Returned in insertion order — recent first when paginating, but for
  /// pre-render the order doesn't matter.
  Future<List<DjSpeechCacheRow>> all() {
    return _db.select(_db.djSpeechCache).get();
  }

  /// Cheap row count for diagnostics / training-screen progress display.
  Future<int> count() async {
    final row = await _db
        .customSelect('SELECT COUNT(*) AS c FROM dj_speech_cache')
        .getSingle();
    return row.read<int>('c');
  }
}
