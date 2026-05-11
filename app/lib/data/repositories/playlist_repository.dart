import 'package:drift/drift.dart';

import '../database/app_database.dart';

class PlaylistRepository {
  PlaylistRepository(this._db);

  final AppDatabase _db;

  Stream<List<PlaylistRow>> watchAll() {
    return (_db.select(_db.playlists)
          ..orderBy([(p) => OrderingTerm(expression: p.createdAt)]))
        .watch();
  }

  Future<PlaylistRow?> findById(String id) {
    return (_db.select(_db.playlists)..where((p) => p.id.equals(id)))
        .getSingleOrNull();
  }

  /// Watches the songs in [playlistId], ordered by their stored position.
  Stream<List<SongRow>> watchSongs(String playlistId) {
    final query = _db.select(_db.playlistSongs).join([
      innerJoin(
        _db.songs,
        _db.songs.id.equalsExp(_db.playlistSongs.songId),
      ),
    ])
      ..where(_db.playlistSongs.playlistId.equals(playlistId))
      ..orderBy([OrderingTerm(expression: _db.playlistSongs.position)]);

    return query
        .watch()
        .map((rows) => rows.map((r) => r.readTable(_db.songs)).toList());
  }

  Future<String> create(String name) async {
    final id = 'pl_${DateTime.now().microsecondsSinceEpoch}';
    await _db.into(_db.playlists).insert(
          PlaylistsCompanion.insert(
            id: id,
            name: name,
            createdAt: DateTime.now().toIso8601String(),
          ),
        );
    return id;
  }

  Future<void> rename(String id, String name) {
    return (_db.update(_db.playlists)..where((p) => p.id.equals(id)))
        .write(PlaylistsCompanion(name: Value(name)));
  }

  Future<void> delete(String id) async {
    await _db.transaction(() async {
      await (_db.delete(_db.playlistSongs)
            ..where((ps) => ps.playlistId.equals(id)))
          .go();
      await (_db.delete(_db.playlists)..where((p) => p.id.equals(id))).go();
    });
  }

  Future<void> addSong({
    required String playlistId,
    required String songId,
  }) async {
    final maxPosRow = await (_db.selectOnly(_db.playlistSongs)
          ..addColumns([_db.playlistSongs.position.max()])
          ..where(_db.playlistSongs.playlistId.equals(playlistId)))
        .getSingleOrNull();
    final nextPos = (maxPosRow?.read(_db.playlistSongs.position.max()) ?? -1) + 1;
    await _db.into(_db.playlistSongs).insert(
          PlaylistSongsCompanion.insert(
            playlistId: playlistId,
            songId: songId,
            position: nextPos,
          ),
          mode: InsertMode.insertOrIgnore,
        );
  }

  Future<void> removeSong({
    required String playlistId,
    required String songId,
  }) async {
    await _db.transaction(() async {
      await (_db.delete(_db.playlistSongs)
            ..where((ps) =>
                ps.playlistId.equals(playlistId) & ps.songId.equals(songId)))
          .go();
      await _compactPositions(playlistId);
    });
  }

  /// Move song from [oldIndex] to [newIndex] within the playlist.
  Future<void> reorder({
    required String playlistId,
    required int oldIndex,
    required int newIndex,
  }) async {
    if (oldIndex == newIndex) return;
    await _db.transaction(() async {
      final rows = await (_db.select(_db.playlistSongs)
            ..where((ps) => ps.playlistId.equals(playlistId))
            ..orderBy([(ps) => OrderingTerm(expression: ps.position)]))
          .get();
      final list = [...rows];
      final adjustedNew = newIndex > oldIndex ? newIndex - 1 : newIndex;
      final moved = list.removeAt(oldIndex);
      list.insert(adjustedNew, moved);
      for (var i = 0; i < list.length; i++) {
        await (_db.update(_db.playlistSongs)
              ..where((ps) =>
                  ps.playlistId.equals(playlistId) &
                  ps.songId.equals(list[i].songId)))
            .write(PlaylistSongsCompanion(position: Value(i)));
      }
    });
  }

  Future<void> _compactPositions(String playlistId) async {
    final rows = await (_db.select(_db.playlistSongs)
          ..where((ps) => ps.playlistId.equals(playlistId))
          ..orderBy([(ps) => OrderingTerm(expression: ps.position)]))
        .get();
    for (var i = 0; i < rows.length; i++) {
      if (rows[i].position != i) {
        await (_db.update(_db.playlistSongs)
              ..where((ps) =>
                  ps.playlistId.equals(playlistId) &
                  ps.songId.equals(rows[i].songId)))
            .write(PlaylistSongsCompanion(position: Value(i)));
      }
    }
  }
}
