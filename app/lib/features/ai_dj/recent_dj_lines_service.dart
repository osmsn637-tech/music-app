import 'package:drift/drift.dart' show OrderingMode, OrderingTerm, Value;

import '../../data/database/app_database.dart';

/// Cross-session memory of recent DJ commentary lines, used by
/// [DjCommentary] to suppress repeats. Persists to the `recent_dj_lines`
/// table; pruned aggressively to a small ceiling because there's no value
/// in retaining old lines beyond the de-duplication window.
class RecentDjLinesService {
  RecentDjLinesService(this._db);

  final AppDatabase _db;

  /// Hard cap on how many rows we keep. The query in [recentTexts] looks
  /// at far fewer (default 30); the cap exists so a long-lived install
  /// doesn't bloat the DB indefinitely.
  static const int _maxRows = 200;

  /// Texts spoken in the last [limit] entries, ordered most-recent first.
  /// Returned as a Set for O(1) membership lookup by the commentary engine.
  Future<Set<String>> recentTexts({int limit = 30}) async {
    final query = _db.select(_db.recentDjLines)
      ..orderBy([
        (t) => OrderingTerm(expression: t.id, mode: OrderingMode.desc),
      ])
      ..limit(limit);
    final rows = await query.get();
    return rows.map((r) => r.lineText).toSet();
  }

  /// Records a freshly-spoken line. Caller fires this after the line has
  /// been chosen. Async but the caller usually doesn't need to await — it
  /// only affects the next pick, not the current one.
  Future<void> record({
    required String lineText,
    String? intent,
    String? songId,
    String? mode,
  }) async {
    final now = DateTime.now().toIso8601String();
    await _db.into(_db.recentDjLines).insert(
          RecentDjLinesCompanion.insert(
            lineText: lineText,
            intent: Value(intent),
            songId: Value(songId),
            mode: Value(mode),
            createdAt: now,
          ),
        );
    await _pruneIfNeeded();
  }

  /// Drops rows beyond [_maxRows] keeping the most recent. Cheap because
  /// it runs after each insert and thus has at most one row to delete.
  Future<void> _pruneIfNeeded() async {
    final count = await _db
        .customSelect(
          'SELECT COUNT(*) AS c FROM recent_dj_lines',
        )
        .getSingle();
    final c = count.read<int>('c');
    if (c <= _maxRows) return;
    final toDrop = c - _maxRows;
    // Delete the oldest [toDrop] rows by id ascending.
    await _db.customStatement(
      'DELETE FROM recent_dj_lines WHERE id IN ('
      'SELECT id FROM recent_dj_lines ORDER BY id ASC LIMIT ?'
      ')',
      [toDrop],
    );
  }

  /// Wipes the table. For tests + the future "reset DJ memory" UI button.
  Future<void> clear() async {
    await _db.delete(_db.recentDjLines).go();
  }
}
