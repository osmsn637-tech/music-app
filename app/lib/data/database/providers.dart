import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../repositories/song_repository.dart';
import 'app_database.dart';

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

final songRepositoryProvider = Provider<SongRepository>((ref) {
  return SongRepository(ref.watch(appDatabaseProvider));
});
