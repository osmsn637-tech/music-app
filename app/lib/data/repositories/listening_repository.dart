import 'package:drift/drift.dart';

import '../database/app_database.dart';

/// Records listening events and rolls them into per-song / per-context stats.
class ListeningRepository {
  ListeningRepository(this._db);

  final AppDatabase _db;

  Future<int> insertEvent({
    required String songId,
    required String eventType,
    String? context,
    int? positionMs,
    int? listenedMs,
  }) {
    final row = ListeningEventsCompanion.insert(
      songId: songId,
      eventType: eventType,
      context: Value(context),
      positionMs: Value(positionMs),
      listenedMs: Value(listenedMs),
      createdAt: DateTime.now().toIso8601String(),
    );
    return _db.into(_db.listeningEvents).insert(row);
  }

  Stream<List<ListeningEventRow>> watchRecent({int limit = 100}) {
    return (_db.select(_db.listeningEvents)
          ..orderBy([
            (e) => OrderingTerm(
                expression: e.createdAt, mode: OrderingMode.desc),
          ])
          ..limit(limit))
        .watch();
  }

  Future<SongStatsRow?> statsFor(String songId) {
    return (_db.select(_db.songStats)..where((s) => s.songId.equals(songId)))
        .getSingleOrNull();
  }

  Stream<SongStatsRow?> watchStatsFor(String songId) {
    return (_db.select(_db.songStats)..where((s) => s.songId.equals(songId)))
        .watchSingleOrNull();
  }

  /// Applies an event to the rollup tables (song_stats and context_stats).
  /// Caller is responsible for inserting the raw event separately.
  Future<void> applyEventToStats({
    required String songId,
    required String eventType,
    String? context,
    int listenedMs = 0,
  }) async {
    await _db.transaction(() async {
      await _upsertSongStats(
        songId: songId,
        eventType: eventType,
        listenedMs: listenedMs,
      );
      if (context != null) {
        await _upsertContextStats(
          songId: songId,
          eventType: eventType,
          context: context,
          listenedMs: listenedMs,
        );
      }
    });
  }

  Future<void> _upsertSongStats({
    required String songId,
    required String eventType,
    required int listenedMs,
  }) async {
    final existing = await statsFor(songId);
    final nowIso = DateTime.now().toIso8601String();
    if (existing == null) {
      await _db.into(_db.songStats).insert(
            SongStatsCompanion.insert(
              songId: songId,
              playCount: Value(eventType == 'play' ? 1 : 0),
              completeCount: Value(eventType == 'complete' ? 1 : 0),
              skipCount: Value(eventType == 'skip' ? 1 : 0),
              replayCount: Value(eventType == 'replay' ? 1 : 0),
              favoriteCount: Value(eventType == 'favorite' ? 1 : 0),
              totalListenedMs: Value(listenedMs),
              lastPlayedAt: Value(
                _isPlayLike(eventType) ? nowIso : existing?.lastPlayedAt,
              ),
            ),
          );
      return;
    }
    await (_db.update(_db.songStats)..where((s) => s.songId.equals(songId)))
        .write(
      SongStatsCompanion(
        playCount: Value(
          existing.playCount + (eventType == 'play' ? 1 : 0),
        ),
        completeCount: Value(
          existing.completeCount + (eventType == 'complete' ? 1 : 0),
        ),
        skipCount: Value(
          existing.skipCount + (eventType == 'skip' ? 1 : 0),
        ),
        replayCount: Value(
          existing.replayCount + (eventType == 'replay' ? 1 : 0),
        ),
        favoriteCount: Value(
          existing.favoriteCount + (eventType == 'favorite' ? 1 : 0),
        ),
        totalListenedMs:
            Value(existing.totalListenedMs + listenedMs),
        lastPlayedAt: Value(
          _isPlayLike(eventType) ? nowIso : existing.lastPlayedAt,
        ),
      ),
    );
  }

  Future<void> _upsertContextStats({
    required String songId,
    required String eventType,
    required String context,
    required int listenedMs,
  }) async {
    final existing = await (_db.select(_db.contextStats)
          ..where((c) =>
              c.songId.equals(songId) & c.context.equals(context)))
        .getSingleOrNull();
    if (existing == null) {
      await _db.into(_db.contextStats).insert(
            ContextStatsCompanion.insert(
              songId: songId,
              context: context,
              playCount: Value(eventType == 'play' ? 1 : 0),
              completeCount: Value(eventType == 'complete' ? 1 : 0),
              skipCount: Value(eventType == 'skip' ? 1 : 0),
              totalListenedMs: Value(listenedMs),
            ),
          );
      return;
    }
    await (_db.update(_db.contextStats)
          ..where((c) => c.id.equals(existing.id)))
        .write(
      ContextStatsCompanion(
        playCount: Value(
          existing.playCount + (eventType == 'play' ? 1 : 0),
        ),
        completeCount: Value(
          existing.completeCount + (eventType == 'complete' ? 1 : 0),
        ),
        skipCount: Value(
          existing.skipCount + (eventType == 'skip' ? 1 : 0),
        ),
        totalListenedMs:
            Value(existing.totalListenedMs + listenedMs),
      ),
    );
  }

  bool _isPlayLike(String type) =>
      type == 'play' || type == 'replay' || type == 'complete';
}
