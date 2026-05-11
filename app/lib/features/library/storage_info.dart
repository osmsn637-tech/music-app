import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/constants/app_constants.dart';
import '../../data/database/app_database.dart';
import '../../data/sources/file_downloader.dart';

class StorageInfo {
  const StorageInfo({
    required this.totalBytes,
    required this.musicBytes,
    required this.lyricsBytes,
    required this.artworkBytes,
  });

  final int totalBytes;
  final int musicBytes;
  final int lyricsBytes;
  final int artworkBytes;

  String get human => formatBytes(totalBytes);
}

String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}

class StorageInspector {
  Future<StorageInfo> compute() async {
    final root = await getApplicationDocumentsDirectory();
    final music = await _dirSize(p.join(root.path, AppConstants.musicDirName));
    final lyrics =
        await _dirSize(p.join(root.path, AppConstants.lyricsDirName));
    final art = await _dirSize(p.join(root.path, AppConstants.artworkDirName));
    return StorageInfo(
      totalBytes: music + lyrics + art,
      musicBytes: music,
      lyricsBytes: lyrics,
      artworkBytes: art,
    );
  }

  /// Wipes downloaded music + lyrics + artwork files AND clears all
  /// metadata rows (songs, song_stats, listening_events, context_stats,
  /// playlist_songs).
  Future<void> clearDownloads({
    required AppDatabase db,
    required FileDownloader downloader,
  }) async {
    final layout = await downloader.layout();
    for (final dir in [layout.music, layout.lyrics, layout.artwork]) {
      if (await dir.exists()) {
        await for (final entity in dir.list()) {
          try {
            if (entity is File) await entity.delete();
          } catch (_) {}
        }
      }
    }
    await db.transaction(() async {
      await db.delete(db.playlistSongs).go();
      await db.delete(db.contextStats).go();
      await db.delete(db.listeningEvents).go();
      await db.delete(db.songStats).go();
      await db.delete(db.songs).go();
    });
  }

  /// Clears listening history without touching downloads or favorites.
  Future<void> clearHistory(AppDatabase db) async {
    await db.transaction(() async {
      await db.delete(db.listeningEvents).go();
      await db.delete(db.songStats).go();
      await db.delete(db.contextStats).go();
    });
  }

  Future<int> _dirSize(String path) async {
    final dir = Directory(path);
    if (!await dir.exists()) return 0;
    var total = 0;
    await for (final entity in dir.list(recursive: true)) {
      if (entity is File) {
        try {
          total += await entity.length();
        } catch (_) {}
      }
    }
    return total;
  }
}
