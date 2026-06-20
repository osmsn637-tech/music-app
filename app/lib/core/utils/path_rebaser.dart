import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../data/database/app_database.dart';
import '../constants/app_constants.dart';

/// iOS (and sandboxed macOS) rotate the app-container path on reinstall,
/// which invalidates every absolute file path stored in the DB. The audio
/// / artwork / lyric files themselves survive under
/// `Documents/<sub>/<file>` — only the stored prefix points at a dead
/// container, so the row's metadata shows but `File(path)` resolves to
/// nothing and the song looks "deleted".
///
/// This runs ONCE at startup and MUST be awaited before the first DB read
/// (see `main.dart`). For every song it re-derives the path's tail
/// relative to the documents container and re-prefixes it with the CURRENT
/// documents directory, so the stored paths always point at this install's
/// real files.
///
/// Robust by construction:
///   * Walks ALL rows (not a single probe row), so a dev-seed `/dev/null`
///     row can't make it bail.
///   * Keys off the `/Documents/` segment, falling back to the known asset
///     sub-folders, instead of string-matching a probe-derived base.
///   * Idempotent — re-running with already-current paths is a no-op.
Future<void> rebasePathsIfNeeded(AppDatabase db) async {
  final docsDir = (await getApplicationDocumentsDirectory()).path;

  final rows = await db.select(db.songs).get();
  if (rows.isEmpty) return;

  String? rebase(String? stored) {
    if (stored == null || stored.isEmpty) return stored;
    final tail = _docsRelativeTail(stored);
    if (tail == null) return stored; // not a docs-managed asset → leave it
    return p.join(docsDir, tail);
  }

  await db.transaction(() async {
    for (final row in rows) {
      final file = rebase(row.localFilePath);
      final lyrics = rebase(row.localLyricsPath);
      final art = rebase(row.localArtworkPath);
      if (file == row.localFilePath &&
          lyrics == row.localLyricsPath &&
          art == row.localArtworkPath) {
        continue; // already current — skip the write
      }
      await (db.update(db.songs)..where((t) => t.id.equals(row.id))).write(
        SongsCompanion(
          localFilePath: Value(file ?? row.localFilePath),
          localLyricsPath: Value(lyrics),
          localArtworkPath: Value(art),
        ),
      );
    }
  });
}

/// The portion of [path] relative to the documents container, or null if
/// [path] isn't a documents-managed asset. Handles both the iOS / macOS
/// `…/Documents/<sub>/<file>` layout and a bare `…/<sub>/<file>` fallback
/// (Android's docs dir has no `Documents` segment) so every platform's
/// stored paths rebase onto the current container.
String? _docsRelativeTail(String path) {
  const token = '/Documents/';
  final idx = path.indexOf(token);
  if (idx >= 0) return path.substring(idx + token.length);
  // Fallback: anchor on a known asset sub-folder.
  for (final sub in const [
    AppConstants.musicDirName,
    AppConstants.lyricsDirName,
    AppConstants.artworkDirName,
    AppConstants.artistsDirName,
  ]) {
    final marker = '/$sub/';
    final i = path.indexOf(marker);
    if (i >= 0) return path.substring(i + 1); // keep "<sub>/<file>"
  }
  return null;
}
