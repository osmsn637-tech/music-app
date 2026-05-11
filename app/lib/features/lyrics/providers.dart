import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database/app_database.dart';
import 'lyrics_loader.dart';

final lyricsLoaderProvider = Provider<LyricsLoader>((ref) {
  return LyricsLoader();
});

final lyricsForSongProvider =
    FutureProvider.family<LyricsResult, SongRow>((ref, song) {
  return ref.watch(lyricsLoaderProvider).loadFor(song);
});
