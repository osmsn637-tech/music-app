import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database/app_database.dart';
import '../../data/database/providers.dart';
import '../../data/models/remote_artist.dart';

/// Songs ordered by `last_played_at` desc, capped at [limit].
final recentlyPlayedProvider =
    StreamProvider.autoDispose<List<SongRow>>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return (db.select(db.songs)
        ..where((s) => s.lastPlayedAt.isNotNull())
        ..orderBy([
          (s) => OrderingTerm(
              expression: s.lastPlayedAt, mode: OrderingMode.desc),
        ])
        ..limit(40))
      .watch();
});

/// Recently added songs (used for the "Top Picks" / "New for you" rail).
final recentlyAddedProvider =
    StreamProvider.autoDispose<List<SongRow>>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return (db.select(db.songs)
        ..orderBy([
          (s) =>
              OrderingTerm(expression: s.addedAt, mode: OrderingMode.desc),
        ])
        ..limit(40))
      .watch();
});

class ArtistRollup {
  const ArtistRollup({required this.name, required this.songCount});
  final String name;
  final int songCount;
}

/// EVERY distinct artist in the library, ordered by song count desc.
/// Splits multi-artist fields ("Drake, 21 Savage", "X feat. Y", "X & Y")
/// so each performer counts toward their own rollup — including artists who
/// only ever guest. Used by the full Artists lists (Library tab + the desktop
/// sidebar), which must show all of them, not just the top few.
final allArtistsProvider =
    FutureProvider.autoDispose<List<ArtistRollup>>((ref) async {
  final db = ref.watch(appDatabaseProvider);
  final all = await db.select(db.songs).get();
  final counts = <String, int>{};
  for (final s in all) {
    for (final a in splitMultiArtist(s.artist)) {
      counts[a] = (counts[a] ?? 0) + 1;
    }
  }
  final list = counts.entries
      .map((e) => ArtistRollup(name: e.key, songCount: e.value))
      .toList()
    ..sort((a, b) => b.songCount.compareTo(a.songCount));
  return list;
});

/// The top 10 artists by song count — for the search "Artists" rail (a
/// horizontal strip, so it stays short on purpose).
final topArtistsProvider =
    FutureProvider.autoDispose<List<ArtistRollup>>((ref) async {
  final all = await ref.watch(allArtistsProvider.future);
  return all.take(10).toList();
});
