import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../repositories/song_repository.dart';
import 'app_database.dart';

/// Overridden in `main.dart` with an instance whose stored file paths were
/// already rebased onto the current app container (see [rebasePathsIfNeeded]).
/// The fallback body here keeps tests / tooling working without that gate.
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

final songRepositoryProvider = Provider<SongRepository>((ref) {
  return SongRepository(ref.watch(appDatabaseProvider));
});
