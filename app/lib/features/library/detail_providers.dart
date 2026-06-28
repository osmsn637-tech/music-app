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

/// An artist's albums, split into ones they LEAD (own) vs. ones they only
/// guest on (featured). The artist page shows these as separate "Albums" /
/// "Featured On" sections, so a one-track feature no longer surfaces another
/// artist's whole album as this artist's own.
class ArtistAlbums {
  const ArtistAlbums({required this.own, required this.features});

  final List<AlbumRef> own;
  final List<AlbumRef> features;
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

/// The album's lead artist — the most common first-credited name (before any
/// "feat.") across its tracks. Distinguishes an artist's OWN albums from ones
/// they only guest on. Returns a lower-cased key for matching.
String _albumLeadArtist(List<SongRow> songs) {
  final counts = <String, int>{};
  for (final s in songs) {
    final parts = splitMultiArtist(s.artist);
    if (parts.isEmpty) continue;
    final lead = parts.first.trim().toLowerCase();
    if (lead.isEmpty) continue;
    counts[lead] = (counts[lead] ?? 0) + 1;
  }
  if (counts.isEmpty) return '';
  return counts.entries.reduce((a, b) => b.value > a.value ? b : a).key;
}

/// Builds an [AlbumRef] for a full album tracklist.
AlbumRef _albumRef(List<SongRow> songs) {
  final cover = songs.firstWhere(
    (s) => s.localArtworkPath != null,
    orElse: () => songs.first,
  );
  return AlbumRef(
    name: displayAlbumName(cover.album!),
    artist: cover.artist ?? '',
    coverPath: cover.localArtworkPath,
    coverSeed: 'al_${cover.id}',
    songCount: songs.length,
  );
}

/// Albums by [artist], split into ones they LEAD (own) vs. ones they only
/// guest on (featured). Each album's lead artist is judged from its FULL
/// tracklist, so a single guest verse no longer lands another artist's whole
/// album in this artist's "Albums".
final artistAlbumsProvider = Provider.autoDispose
    .family<AsyncValue<ArtistAlbums>, String>((ref, artist) {
      final target = artist.trim().toLowerCase();
      return ref.watch(allSongsProvider).whenData((allSongs) {
        // Group EVERY song by album so each album's lead is judged from its
        // whole tracklist, not just this artist's tracks.
        final byAlbum = <String, List<SongRow>>{};
        for (final s in allSongs) {
          final album = s.album;
          if (album == null || album.isEmpty) continue;
          final key = normalizeAlbumKey(album);
          if (key.isEmpty) continue;
          (byAlbum[key] ??= <SongRow>[]).add(s);
        }
        final own = <AlbumRef>[];
        final features = <AlbumRef>[];
        for (final songs in byAlbum.values) {
          if (!songs.any((s) => _artistMatches(s.artist, artist))) continue;
          (_albumLeadArtist(songs) == target ? own : features)
              .add(_albumRef(songs));
        }
        int byName(AlbumRef a, AlbumRef b) =>
            a.name.toLowerCase().compareTo(b.name.toLowerCase());
        own.sort(byName);
        features.sort(byName);
        return ArtistAlbums(own: own, features: features);
      });
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
