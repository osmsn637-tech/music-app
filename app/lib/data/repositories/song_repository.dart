import 'package:drift/drift.dart';

import '../database/app_database.dart';

class SongRepository {
  SongRepository(this._db);

  final AppDatabase _db;

  Stream<List<SongRow>> watchAll() {
    return (_db.select(_db.songs)
          ..orderBy([
            (s) =>
                OrderingTerm(expression: s.addedAt, mode: OrderingMode.desc),
            (s) => OrderingTerm(expression: s.title),
          ]))
        .watch();
  }

  Stream<List<SongRow>> watchFavorites() {
    return (_db.select(_db.songs)
          ..where((s) => s.isFavorite.equals(1))
          ..orderBy([(s) => OrderingTerm(expression: s.title)]))
        .watch();
  }

  Future<List<SongRow>> search(String query) {
    if (query.trim().isEmpty) return Future.value(const []);
    final like = '%${query.trim().toLowerCase()}%';
    return (_db.select(_db.songs)
          ..where((s) => s.searchText.like(like))
          ..orderBy([(s) => OrderingTerm(expression: s.title)]))
        .get();
  }

  Future<SongRow?> findById(String id) {
    return (_db.select(_db.songs)..where((s) => s.id.equals(id)))
        .getSingleOrNull();
  }

  Future<Set<String>> existingIds() async {
    final rows = await (_db.selectOnly(_db.songs)..addColumns([_db.songs.id]))
        .get();
    return rows.map((r) => r.read(_db.songs.id)!).toSet();
  }

  Future<void> insertAll(List<SongsCompanion> rows) async {
    await _db.batch((b) {
      b.insertAll(_db.songs, rows, mode: InsertMode.insertOrIgnore);
    });
  }

  Future<void> insert(SongsCompanion row) {
    return _db.into(_db.songs).insert(row, mode: InsertMode.insertOrIgnore);
  }

  Future<void> deleteById(String id) {
    return (_db.delete(_db.songs)..where((s) => s.id.equals(id))).go();
  }

  Future<void> setFavorite({required String id, required bool favorite}) {
    return (_db.update(_db.songs)..where((s) => s.id.equals(id))).write(
      SongsCompanion(isFavorite: Value(favorite ? 1 : 0)),
    );
  }

  Future<void> stampPlayed(String id) {
    return (_db.update(_db.songs)..where((s) => s.id.equals(id))).write(
      SongsCompanion(lastPlayedAt: Value(DateTime.now().toIso8601String())),
    );
  }

  /// Updates the cached local-file pointers for an existing song. Used by
  /// the sync repair pass to swap in newly-downloaded artwork or lyrics
  /// without rewriting the rest of the row.
  Future<void> updateLocalAssets({
    required String id,
    String? localArtworkPath,
    String? localLyricsPath,
  }) {
    return (_db.update(_db.songs)..where((s) => s.id.equals(id))).write(
      SongsCompanion(
        localArtworkPath: Value(localArtworkPath),
        localLyricsPath: Value(localLyricsPath),
      ),
    );
  }

  /// Refreshes the metadata fields (title / artist / album / genre / mood /
  /// bpm / durationMs / fileName / searchText) for an existing song without
  /// touching the cached file paths or play history. Used by the sync repair
  /// pass when the server-side `repair` tool has cleaned up titles/artists
  /// and we want those fixes to land in the phone DB without a re-download.
  Future<void> updateMetadata({
    required String id,
    required String title,
    String? artist,
    String? album,
    String? genre,
    String? mood,
    int? bpm,
    int? durationMs,
    String? fileName,
    String? searchText,
  }) {
    return (_db.update(_db.songs)..where((s) => s.id.equals(id))).write(
      SongsCompanion(
        title: Value(title),
        artist: Value(artist),
        album: Value(album),
        genre: Value(genre),
        mood: Value(mood),
        bpm: Value(bpm),
        durationMs: Value(durationMs),
        fileName: fileName == null ? const Value.absent() : Value(fileName),
        searchText:
            searchText == null ? const Value.absent() : Value(searchText),
      ),
    );
  }
}
