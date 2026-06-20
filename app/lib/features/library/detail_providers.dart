import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database/app_database.dart';
import '../../data/models/remote_artist.dart';
import 'providers.dart';

/// A rolled-up album — one entry per (normalised) album name, with the
/// most-recent song's artwork as the cover. Shared by the Library Albums
/// tab and the artist detail page so grouping stays consistent.
class AlbumRef {
  const AlbumRef({
    required this.name,
    required this.artist,
    required this.coverPath,
    required this.coverSeed,
    required this.songCount,
  });

  final String name;
  final String artist;
  final String? coverPath;
  final String coverSeed;
  final int songCount;
}

/// Normalises an artist/album string into a stable grouping key. Strips
/// case, smart punctuation, parentheticals ("(2020)", "[EP]"), leading
/// track numbers, and remaining punctuation so tag-drift variants of the
/// same album collapse together. The key is throwaway (used only for
/// matching); display always uses the original string.
String normalizeAlbumKey(String s) {
  var n = s.trim().toLowerCase();
  n = n
      .replaceAll('‘', "'")
      .replaceAll('’', "'")
      .replaceAll('“', '"')
      .replaceAll('”', '"')
      .replaceAll('–', '-')
      .replaceAll('—', '-');
  n = n.replaceAll(RegExp(r'\s*[\(\[\{][^\)\]\}]*[\)\]\}]'), ' ');
  n = n.replaceFirst(RegExp(r'^\d+\s*[-.\s]\s*'), '');
  n = n.replaceAll(RegExp(r'[^a-z0-9\s]'), ' ');
  n = n.replaceAll(RegExp(r'\s+'), ' ').trim();
  return n;
}

/// Title-cases an album name so it never shows as "album" / "ALBUM".
/// Existing mixed-case words (acronyms, stylised titles) are left alone;
/// stopwords stay lowercase except the first word.
String displayAlbumName(String s) {
  final trimmed = s.trim();
  if (trimmed.isEmpty) return trimmed;
  final parts = trimmed.split(RegExp(r'\s+'));
  return parts
      .asMap()
      .entries
      .map((entry) {
        final i = entry.key;
        final word = entry.value;
        if (word.isEmpty) return word;
        final lower = word.toLowerCase();
        final upper = word.toUpperCase();
        final isAllOneCase = word == lower || word == upper;
        if (!isAllOneCase) return word;
        final stopwords = i == 0
            ? const <String>{}
            : const {
                'a',
                'an',
                'the',
                'of',
                'and',
                'or',
                'but',
                'in',
                'on',
                'at',
                'to',
                'for',
                'by',
                'with',
                'as',
                'from',
                'is',
              };
        if (stopwords.contains(lower)) return lower;
        return lower[0].toUpperCase() + lower.substring(1);
      })
      .join(' ');
}

/// Groups a song list into album rollups, sorted by display name.
List<AlbumRef> rollupAlbums(List<SongRow> songs) {
  final byKey = <String, List<SongRow>>{};
  for (final s in songs) {
    final album = s.album;
    if (album == null || album.isEmpty) continue;
    final key = normalizeAlbumKey(album);
    if (key.isEmpty) continue;
    (byKey[key] ??= <SongRow>[]).add(s);
  }
  final rolls =
      byKey.entries.map((e) {
          final list = e.value;
          final cover = list.firstWhere(
            (s) => s.localArtworkPath != null,
            orElse: () => list.first,
          );
          return AlbumRef(
            name: displayAlbumName(cover.album!),
            artist: cover.artist ?? '',
            coverPath: cover.localArtworkPath,
            coverSeed: 'al_${cover.id}',
            songCount: list.length,
          );
        }).toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return rolls;
}

/// All albums in the library (Library → Albums tab).
final albumsProvider = Provider.autoDispose<AsyncValue<List<AlbumRef>>>((ref) {
  return ref.watch(allSongsProvider).whenData(rollupAlbums);
});

bool _artistMatches(String? songArtist, String target) {
  final t = target.trim().toLowerCase();
  if (t.isEmpty) return false;
  for (final a in splitMultiArtist(songArtist)) {
    if (a.trim().toLowerCase() == t) return true;
  }
  return false;
}

/// Songs credited to [artist] (handles "feat." / "&" / "," multi-artist
/// fields via [splitMultiArtist]), grouped by album then title.
final songsByArtistProvider = Provider.autoDispose
    .family<AsyncValue<List<SongRow>>, String>((ref, artist) {
      return ref.watch(allSongsProvider).whenData((songs) {
        final list =
            songs.where((s) => _artistMatches(s.artist, artist)).toList()
              ..sort((a, b) {
                final byAlbum = (a.album ?? '').toLowerCase().compareTo(
                  (b.album ?? '').toLowerCase(),
                );
                if (byAlbum != 0) return byAlbum;
                return a.title.toLowerCase().compareTo(b.title.toLowerCase());
              });
        return list;
      });
    });

/// Albums [artist] appears on.
final albumsByArtistProvider = Provider.autoDispose
    .family<AsyncValue<List<AlbumRef>>, String>((ref, artist) {
      return ref.watch(songsByArtistProvider(artist)).whenData(rollupAlbums);
    });

/// Songs on [album] (matched on the normalised album key).
final songsByAlbumProvider = Provider.autoDispose
    .family<AsyncValue<List<SongRow>>, String>((ref, album) {
      final key = normalizeAlbumKey(album);
      return ref.watch(allSongsProvider).whenData((songs) {
        return songs
            .where((s) => s.album != null && normalizeAlbumKey(s.album!) == key)
            .toList();
      });
    });
