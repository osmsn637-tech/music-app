import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/constants/app_constants.dart';
import '../../data/database/app_database.dart';
import '../../data/database/providers.dart';
import 'lyrics_loader.dart';

final lyricsLoaderProvider = Provider<LyricsLoader>((ref) {
  return LyricsLoader();
});

final lyricsForSongProvider = FutureProvider.family<LyricsResult, SongRow>((
  ref,
  song,
) async {
  // Re-read the row by id so user-added (or repaired) lyrics get picked up
  // even when the in-memory now-playing row is stale.
  final fresh =
      await ref.read(songRepositoryProvider).findById(song.id) ?? song;
  return ref.watch(lyricsLoaderProvider).loadFor(fresh);
});

/// Per-song lyric timing offset in milliseconds. Positive = lyrics show
/// later (audio is ahead). Session-scoped per song.
final lyricOffsetProvider = StateProvider.autoDispose.family<int, String>(
  (ref, songId) => 0,
);

final lyricsActionsProvider = Provider<LyricsActions>(
  (ref) => LyricsActions(ref),
);

class LyricsActions {
  LyricsActions(this._ref);
  final Ref _ref;

  /// Save user-supplied lyrics (plain text or full `.lrc`) to the local
  /// lyrics folder, point the song row at it, and refresh the view.
  Future<void> saveLyrics(SongRow song, String text) async {
    final root = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(root.path, AppConstants.lyricsDirName));
    if (!await dir.exists()) await dir.create(recursive: true);
    final file = File(p.join(dir.path, '${song.id}.lrc'));
    await file.writeAsString(text.trim());
    await _ref
        .read(songRepositoryProvider)
        .updateLocalAssets(
          id: song.id,
          localArtworkPath: song.localArtworkPath,
          localLyricsPath: file.path,
        );
    _ref.invalidate(lyricsForSongProvider(song));
  }
}
