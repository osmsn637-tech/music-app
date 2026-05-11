import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database/app_database.dart';
import '../../data/database/providers.dart';
import '../../data/repositories/playlist_repository.dart';

final playlistRepositoryProvider = Provider<PlaylistRepository>((ref) {
  return PlaylistRepository(ref.watch(appDatabaseProvider));
});

final allPlaylistsProvider = StreamProvider<List<PlaylistRow>>((ref) {
  return ref.watch(playlistRepositoryProvider).watchAll();
});

final playlistSongsProvider =
    StreamProvider.family<List<SongRow>, String>((ref, playlistId) {
  return ref.watch(playlistRepositoryProvider).watchSongs(playlistId);
});
