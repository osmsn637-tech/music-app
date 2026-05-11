import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database/app_database.dart';
import '../../data/database/providers.dart';

final allSongsProvider = StreamProvider<List<SongRow>>((ref) {
  return ref.watch(songRepositoryProvider).watchAll();
});

final favoriteSongsProvider = StreamProvider<List<SongRow>>((ref) {
  return ref.watch(songRepositoryProvider).watchFavorites();
});
