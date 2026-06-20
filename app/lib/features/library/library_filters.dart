import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database/app_database.dart';
import 'providers.dart';

/// Distinct genres in the library, most-common first. Drives the Search
/// "Browse" tiles so they map to real, searchable genres instead of
/// hardcoded labels that return nothing.
final libraryGenresProvider = Provider.autoDispose<AsyncValue<List<String>>>((
  ref,
) {
  return ref.watch(allSongsProvider).whenData((songs) {
    final counts = <String, int>{};
    for (final s in songs) {
      final g = s.genre?.trim();
      if (g == null || g.isEmpty) continue;
      counts[g] = (counts[g] ?? 0) + 1;
    }
    final entries = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries.map((e) => e.key).toList();
  });
});

/// Sort options for the Library → Songs list.
enum LibrarySort {
  recentlyAdded,
  recentlyPlayed,
  title,
  artist,
  album,
  duration,
}

extension LibrarySortLabel on LibrarySort {
  String get label => switch (this) {
    LibrarySort.recentlyAdded => 'Recently added',
    LibrarySort.recentlyPlayed => 'Recently played',
    LibrarySort.title => 'Title',
    LibrarySort.artist => 'Artist',
    LibrarySort.album => 'Album',
    LibrarySort.duration => 'Duration',
  };
}

final librarySortProvider = StateProvider<LibrarySort>(
  (ref) => LibrarySort.recentlyAdded,
);

final libraryFavoritesOnlyProvider = StateProvider<bool>((ref) => false);

/// The Songs-tab list, filtered (favorites) and sorted per the current
/// selections. Sorting is client-side over the already-streamed rows.
final librarySongsProvider = Provider.autoDispose<AsyncValue<List<SongRow>>>((
  ref,
) {
  final favOnly = ref.watch(libraryFavoritesOnlyProvider);
  final sort = ref.watch(librarySortProvider);
  final base = favOnly
      ? ref.watch(favoriteSongsProvider)
      : ref.watch(allSongsProvider);
  return base.whenData((songs) {
    final list = [...songs];
    switch (sort) {
      case LibrarySort.recentlyAdded:
        list.sort((a, b) => (b.addedAt ?? '').compareTo(a.addedAt ?? ''));
      case LibrarySort.recentlyPlayed:
        list.sort(
          (a, b) => (b.lastPlayedAt ?? '').compareTo(a.lastPlayedAt ?? ''),
        );
      case LibrarySort.title:
        list.sort(
          (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
        );
      case LibrarySort.artist:
        list.sort(
          (a, b) => (a.artist ?? '').toLowerCase().compareTo(
            (b.artist ?? '').toLowerCase(),
          ),
        );
      case LibrarySort.album:
        list.sort(
          (a, b) => (a.album ?? '').toLowerCase().compareTo(
            (b.album ?? '').toLowerCase(),
          ),
        );
      case LibrarySort.duration:
        list.sort((a, b) => (b.durationMs ?? 0).compareTo(a.durationMs ?? 0));
    }
    return list;
  });
});
