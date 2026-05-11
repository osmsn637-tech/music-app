import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/dev_seed.dart';
import '../../data/database/app_database.dart';
import '../../data/database/providers.dart';
import '../../features/ai_dj/providers.dart';
import '../../features/library/artist_image_resolver.dart';
import '../../features/library/home_providers.dart';
import '../../features/library/library_actions.dart';
import '../../features/library/providers.dart';
import '../../features/player/now_playing_controller.dart';
import '../../features/playlists/providers.dart';
import '../../features/search/search_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/album_art.dart';
import '../widgets/glass.dart';
import '../widgets/mini_player.dart' show openPlayerRoute;
import '../widgets/song_actions.dart';
import '../widgets/song_tile.dart';
import 'home_shell_providers.dart';
import 'playlist_detail_screen.dart';

/// Albums rolled up from the songs table — one entry per (artist, album)
/// pair, with the most-recent song's artwork used as the cover.
class _AlbumRollup {
  const _AlbumRollup({
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

/// Roll up the songs stream into one entry per (artist, album) pair.
/// Returns `AsyncValue<List<_AlbumRollup>>` so the consumer can render
/// the same loading/error/data states the upstream songs provider exposes.
final _albumsProvider =
    Provider.autoDispose<AsyncValue<List<_AlbumRollup>>>((ref) {
  final asyncSongs = ref.watch(allSongsProvider);
  return asyncSongs.whenData((songs) {
    final byKey = <String, List<SongRow>>{};
    for (final s in songs) {
      final album = s.album;
      if (album == null || album.isEmpty) continue;
      final key = '${s.artist ?? 'unknown'}|$album';
      (byKey[key] ??= <SongRow>[]).add(s);
    }
    final rolls = byKey.entries.map((e) {
      final list = e.value;
      final cover = list.firstWhere(
        (s) => s.localArtworkPath != null,
        orElse: () => list.first,
      );
      return _AlbumRollup(
        name: cover.album!,
        artist: cover.artist ?? '',
        coverPath: cover.localArtworkPath,
        coverSeed: 'al_${cover.id}',
        songCount: list.length,
      );
    }).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return rolls;
  });
});

class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  static const _tabs = <String>['Songs', 'Artists', 'Albums', 'Playlists'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    var tab = ref.watch(libraryChipProvider);
    // Old persisted value 'Favorites' is no longer in the new tab set —
    // fall through to Songs without writing to state to avoid clobbering
    // any future re-introduction.
    if (!_tabs.contains(tab)) tab = 'Songs';

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(0, LumenTokens.topSafePad, 0, 0),
          sliver: SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(LumenTokens.pagePad, 0,
                  LumenTokens.pagePad, 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Expanded(
                    child: Text(
                      'Library',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -1,
                        height: 1.05,
                      ),
                    ),
                  ),
                  if (kDebugMode)
                    IconButton(
                      icon: const Icon(Icons.bug_report_outlined),
                      onPressed: () async {
                        final seed =
                            DevSeed(ref.read(appDatabaseProvider));
                        await seed.run();
                      },
                    ),
                ],
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(LumenTokens.pagePad, 0,
                LumenTokens.pagePad, 18),
            child: _SubTabs(
              tabs: _tabs,
              active: tab,
              onChange: (t) =>
                  ref.read(libraryChipProvider.notifier).state = t,
            ),
          ),
        ),
        if (tab == 'Songs') const _SongsSliver(),
        if (tab == 'Artists') const _ArtistsSliver(),
        if (tab == 'Albums') const _AlbumsSliver(),
        if (tab == 'Playlists') const _PlaylistsSliver(),
        const SliverToBoxAdapter(child: SizedBox(height: 220)),
      ],
    );
  }
}

/// Glass pill with 4 segments. Active segment gets a translucent fill.
class _SubTabs extends StatelessWidget {
  const _SubTabs({
    required this.tabs,
    required this.active,
    required this.onChange,
  });
  final List<String> tabs;
  final String active;
  final ValueChanged<String> onChange;

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    return Glass(
      borderRadius: LumenTokens.rPill,
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          for (final t in tabs)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onChange(t),
                child: AnimatedContainer(
                  duration: LumenTokens.dFast,
                  curve: LumenTokens.easeOut,
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: t == active
                        ? (isLight
                            ? Colors.white.withValues(alpha: 0.65)
                            : Colors.white.withValues(alpha: 0.18))
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(LumenTokens.rPill),
                  ),
                  child: Text(
                    t,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: t == active
                          ? LumenTokens.fg(context)
                          : LumenTokens.fgDimOf(context),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SongsSliver extends ConsumerWidget {
  const _SongsSliver();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(allSongsProvider);
    final playingId = ref.watch(
      nowPlayingProvider.select((s) => s?.id),
    );

    return async.when(
      loading: () => const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.all(40),
          child: Center(child: CircularProgressIndicator()),
        ),
      ),
      error: (e, _) => SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Center(child: Text('Error: $e')),
        ),
      ),
      data: (songs) {
        if (songs.isEmpty) {
          return _EmptySliver(
            text: 'No songs yet.\nSync from the profile menu.',
          );
        }
        return SliverList.builder(
          itemCount: songs.length,
          itemBuilder: (context, i) {
            final s = songs[i];
            return SongTile(
              key: ValueKey(s.id),
              song: s,
              isPlaying: playingId == s.id,
              onTap: () => _open(context, ref, songs, i),
              onLongPress: () => SongActionsSheet.show(context, s),
              onFavoriteToggle: () =>
                  ref.read(libraryActionsProvider).toggleFavorite(s),
            );
          },
        );
      },
    );
  }

  Future<void> _open(
    BuildContext context,
    WidgetRef ref,
    List<SongRow> queue,
    int index,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    ref.read(aiDjQueueControllerProvider.notifier).deactivate();
    try {
      await ref
          .read(nowPlayingProvider.notifier)
          .playFromQueue(queue, index);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not play: $e')));
      return;
    }
    if (!context.mounted) return;
    Navigator.of(context).push(openPlayerRoute());
  }
}

/// Vertical list of artists. Round avatar + name + chevron. Tapping
/// hops over to Search and pre-fills the artist's name.
class _ArtistsSliver extends ConsumerWidget {
  const _ArtistsSliver();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(topArtistsProvider);
    final resolver = ref.watch(artistImageResolverProvider).valueOrNull;

    return async.when(
      loading: () => const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.all(40),
          child: Center(child: CircularProgressIndicator()),
        ),
      ),
      error: (e, _) => SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Center(child: Text('Error: $e')),
        ),
      ),
      data: (artists) {
        if (artists.isEmpty) {
          return _EmptySliver(text: 'No artists yet.');
        }
        return SliverList.builder(
          itemCount: artists.length,
          itemBuilder: (context, i) {
            final a = artists[i];
            return InkWell(
              onTap: () {
                ref
                    .read(librarySearchControllerProvider.notifier)
                    .onQueryChanged(a.name);
                ref.read(homeTabIndexProvider.notifier).state = 2;
              },
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                    LumenTokens.pagePad, 6, LumenTokens.pagePad, 6),
                child: Row(
                  children: [
                    AlbumArt(
                      artworkPath: resolver?.localPath(a.name),
                      seed: 'ar_${a.name}',
                      size: 52,
                      radius: LumenTokens.rPill,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            a.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            '${a.songCount} song${a.songCount == 1 ? '' : 's'}',
                            style: TextStyle(
                              fontSize: 12,
                              color: LumenTokens.fgDimOf(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right,
                        size: 18,
                        color: LumenTokens.fgDimOf(context)),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

/// 2-column grid of album cards. Tapping pre-fills search with the
/// album name (no dedicated album-detail screen exists yet).
class _AlbumsSliver extends ConsumerWidget {
  const _AlbumsSliver();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_albumsProvider);
    return async.when(
      loading: () => const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.all(40),
          child: Center(child: CircularProgressIndicator()),
        ),
      ),
      error: (e, _) => SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Center(child: Text('Error: $e')),
        ),
      ),
      data: (list) {
        if (list.isEmpty) {
          return _EmptySliver(text: 'No albums yet.');
        }
        return SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: LumenTokens.pagePad),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 14,
              crossAxisSpacing: 14,
              childAspectRatio: 0.82,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, i) {
                final al = list[i];
                return InkWell(
                  borderRadius: BorderRadius.circular(LumenTokens.rSm),
                  onTap: () {
                    ref
                        .read(librarySearchControllerProvider.notifier)
                        .onQueryChanged(al.name);
                    ref.read(homeTabIndexProvider.notifier).state = 2;
                  },
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AspectRatio(
                        aspectRatio: 1,
                        child: AlbumArt(
                          artworkPath: al.coverPath,
                          seed: al.coverSeed,
                          size: double.infinity,
                          radius: LumenTokens.rSm,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        al.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        al.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: LumenTokens.fgDimOf(context),
                        ),
                      ),
                    ],
                  ),
                );
              },
              childCount: list.length,
            ),
          ),
        );
      },
    );
  }
}

class _PlaylistsSliver extends ConsumerWidget {
  const _PlaylistsSliver();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(allPlaylistsProvider);
    return async.when(
      loading: () => const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.all(40),
          child: Center(child: CircularProgressIndicator()),
        ),
      ),
      error: (e, _) => SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Text('Error: $e'),
        ),
      ),
      data: (list) {
        if (list.isEmpty) {
          return _EmptySliver(
            text: 'No playlists yet.\nLong-press any song -> Add to playlist.',
          );
        }
        return SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: LumenTokens.pagePad),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 14,
              crossAxisSpacing: 14,
              childAspectRatio: 0.78,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, i) {
                final pl = list[i];
                return RepaintBoundary(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(LumenTokens.rLg),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            PlaylistDetailScreen(playlistId: pl.id),
                      ),
                    ),
                    child: Glass(
                      borderRadius: LumenTokens.rLg,
                      padding: const EdgeInsets.all(10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: AspectRatio(
                              aspectRatio: 1,
                              child: AlbumArt(
                                seed: 'pl_${pl.id}',
                                size: double.infinity,
                                radius: LumenTokens.rXs,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'PLAYLIST',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                              color: LumenTokens.fgDim2Of(context),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            pl.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
              childCount: list.length,
            ),
          ),
        );
      },
    );
  }
}

class _EmptySliver extends StatelessWidget {
  const _EmptySliver({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Center(
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(color: LumenTokens.fgDimOf(context)),
          ),
        ),
      ),
    );
  }
}
