import 'package:drift/drift.dart';

import '../../data/database/app_database.dart';

/// Inserts a few demo rows so the Library screen has something to render
/// before Phase 3 (Wi-Fi sync) lands. The local file paths are placeholders
/// — tapping a seeded row will fail to play. Real playback comes from sync.
class DevSeed {
  DevSeed(this._db);

  final AppDatabase _db;

  Future<void> run() async {
    final now = DateTime.now();
    final rows = [
      _row(
        id: 'dev_001',
        title: 'Demo Track One',
        artist: 'Test Artist',
        album: 'Phase 2 Demos',
        genre: 'Chill',
        mood: 'study',
        bpm: 92,
        addedAt: now,
      ),
      _row(
        id: 'dev_002',
        title: 'Demo Track Two',
        artist: 'Test Artist',
        album: 'Phase 2 Demos',
        genre: 'Electronic',
        mood: 'workout',
        bpm: 140,
        addedAt: now.subtract(const Duration(minutes: 1)),
      ),
      _row(
        id: 'dev_003',
        title: 'Demo Track Three',
        artist: 'Other Artist',
        album: 'Various',
        genre: 'Lo-fi',
        mood: 'study',
        bpm: 75,
        addedAt: now.subtract(const Duration(minutes: 2)),
      ),
    ];
    await _db.batch((b) {
      b.insertAll(_db.songs, rows, mode: InsertMode.insertOrIgnore);
    });
  }

  Future<void> clear() async {
    await _db.delete(_db.songs).go();
  }

  SongsCompanion _row({
    required String id,
    required String title,
    required String artist,
    required String album,
    required String genre,
    required String mood,
    required int bpm,
    required DateTime addedAt,
  }) {
    final searchText =
        [title, artist, album, genre, mood].join(' ').toLowerCase();
    return SongsCompanion.insert(
      id: id,
      title: title,
      artist: Value(artist),
      album: Value(album),
      genre: Value(genre),
      mood: Value(mood),
      bpm: Value(bpm),
      durationMs: const Value(180000),
      fileName: Value('$id.mp3'),
      localFilePath: '/dev/null/$id.mp3',
      searchText: Value(searchText),
      addedAt: Value(addedAt.toIso8601String()),
    );
  }
}
