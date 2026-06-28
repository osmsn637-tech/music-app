import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/dev_seed.dart';
import '../motion/lumen_route.dart';
import '../motion/staggered_appear.dart';
import '../../data/database/app_database.dart';
import '../../data/database/providers.dart';
import '../../features/ai_dj/providers.dart';
import '../../features/library/artist_image_resolver.dart';
import '../../features/library/detail_providers.dart';
import '../../features/library/home_providers.dart';
import '../../features/library/library_actions.dart';
import '../../features/library/library_filters.dart';
import '../../features/player/now_playing_controller.dart';
import '../../features/player/providers.dart';
import '../../features/playlists/providers.dart';
import '../theme/app_theme.dart';
import '../widgets/album_art.dart';
import '../widgets/glass.dart';
import '../widgets/glass_kit.dart';
import '../widgets/playlist_cover.dart';
import '../../features/player/player_expansion_controller.dart';
import '../widgets/song_actions.dart';
import '../widgets/song_tile.dart';
import 'entity_nav.dart';
import 'home_shell_providers.dart';
import 'playlist_detail_screen.dart';

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
              padding: const EdgeInsets.fromLTRB(
                LumenTokens.pagePad,
                0,
                LumenTokens.pagePad,
                16,
              ),
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
                        final seed = DevSeed(ref.read(appDatabaseProvider));
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
            padding: const EdgeInsets.fromLTRB(
              LumenTokens.pagePad,
              0,
              LumenTokens.pagePad,
              18,
            ),
            child: _SubTabs(
              tabs: _tabs,
              active: tab,
              onChange: (t) => ref.read(libraryChipProvider.notifier).state = t,
            ),
          ),
        ),
        if (tab == 'Songs') ...[const _SongsControls(), const _SongsSliver()],
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
                              ? Colors.white
                              : Colors.white.withValues(alpha: 0.18))
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(LumenTokens.rPill),
                    boxShadow: (t == active && isLight)
                        ? [
                            BoxShadow(
                              color: const Color(
                                0xFF141428,
                              ).withValues(alpha: 0.12),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ]
                        : null,
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

/// Songs-tab control row: count + duration, a favorites filter, and a
/// sort selector.
class _SongsControls extends ConsumerWidget {
  const _SongsControls();

  String _fmtTotal(int totalMs) {
    if (totalMs <= 0) return '';
    final m = totalMs ~/ 60000;
    final h = m ~/ 60;
    final min = m % 60;
    return h == 0 ? ' · $min min' : ' · $h hr $min min';
  }

  Future<void> _pickSort(
    BuildContext context,
    WidgetRef ref,
    LibrarySort current,
  ) async {
    final picked = await showGlassSheet<LibrarySort>(
      context,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Sort by', style: glassEyebrow(context)),
            ),
          ),
          for (final s in LibrarySort.values)
            Pressable(
              onTap: () => Navigator.of(context).pop(s),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 13,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        s.label,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: LumenTokens.fg(context),
                        ),
                      ),
                    ),
                    if (s == current)
                      const Icon(
                        Icons.check_rounded,
                        size: 20,
                        color: LumenTokens.accent,
                      ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 6),
        ],
      ),
    );
    if (picked != null) {
      ref.read(librarySortProvider.notifier).state = picked;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final songs =
        ref.watch(librarySongsProvider).valueOrNull ?? const <SongRow>[];
    final favOnly = ref.watch(libraryFavoritesOnlyProvider);
    final sort = ref.watch(librarySortProvider);
    final totalMs = songs.fold<int>(0, (s, r) => s + (r.durationMs ?? 0));
    final meta =
        '${songs.length} song${songs.length == 1 ? '' : 's'}${_fmtTotal(totalMs)}';

    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          LumenTokens.pagePad,
          0,
          LumenTokens.pagePad,
          10,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                meta,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: LumenTokens.fgDimOf(context),
                ),
              ),
            ),
            Pressable(
              onTap: () =>
                  ref.read(libraryFavoritesOnlyProvider.notifier).state =
                      !favOnly,
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Icon(
                  favOnly
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  size: 20,
                  color: favOnly
                      ? LumenTokens.accent
                      : LumenTokens.fgDimOf(context),
                ),
              ),
            ),
            const SizedBox(width: 4),
            Pressable(
              onTap: () => _pickSort(context, ref, sort),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.swap_vert_rounded,
                      size: 18,
                      color: LumenTokens.fgDimOf(context),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      sort.label,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: LumenTokens.fg(context),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SongsSliver extends ConsumerStatefulWidget {
  const _SongsSliver();

  @override
  ConsumerState<_SongsSliver> createState() => _SongsSliverState();
}

class _SongsSliverState extends ConsumerState<_SongsSliver> {
  // Cascade the first screenful, once. After the entrance window closes the
  // flag flips so scroll-recycled rows never re-fire the animation.
  static const _cap = 8;
  bool _entered = false;
  bool _scheduled = false;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(librarySongsProvider);
    final favOnly = ref.watch(libraryFavoritesOnlyProvider);
    final playingId = ref.watch(nowPlayingProvider.select((s) => s?.id));
    final isPlaying =
        ref.watch(playerStateStreamProvider).valueOrNull?.playing ?? false;

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
            text: favOnly
                ? 'No favorites yet.\nTap the heart on a song to add it.'
                : 'No songs yet.\nSync from the profile menu.',
          );
        }
        if (!_entered && !_scheduled) {
          _scheduled = true;
          Future<void>.delayed(const Duration(milliseconds: 750), () {
            if (mounted) setState(() => _entered = true);
          });
        }
        return SliverList.builder(
          itemCount: songs.length,
          itemBuilder: (context, i) {
            final s = songs[i];
            return StaggeredAppear(
              key: ValueKey(s.id),
              index: i,
              maxItems: _cap,
              animate: !_entered && i < _cap,
              child: SongTile(
                song: s,
                isPlaying: playingId == s.id,
                onTap: () {
                  if (playingId == s.id && isPlaying) {
                    PlayerExpansionScope.maybeRead(context)?.expand();
                  } else {
                    _open(context, songs, i);
                  }
                },
                onLongPress: () => SongActionsSheet.show(context, s),
                onMore: () => SongActionsSheet.show(context, s),
                onFavoriteToggle: () =>
                    ref.read(libraryActionsProvider).toggleFavorite(s),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _open(
    BuildContext context,
    List<SongRow> queue,
    int index,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    ref.read(aiDjQueueControllerProvider.notifier).deactivate();
    try {
      await ref.read(nowPlayingProvider.notifier).playFromQueue(queue, index);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not play: $e')));
      return;
    }
    if (!context.mounted) return;
    PlayerExpansionScope.read(context).expand();
  }
}

/// Vertical list of artists. Round avatar + name + chevron. Tapping
/// hops over to Search and pre-fills the artist's name.
class _ArtistsSliver extends ConsumerStatefulWidget {
  const _ArtistsSliver();

  @override
  ConsumerState<_ArtistsSliver> createState() => _ArtistsSliverState();
}

class _ArtistsSliverState extends ConsumerState<_ArtistsSliver> {
  static const _cap = 10;
  bool _entered = false;
  bool _scheduled = false;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(allArtistsProvider);
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
        if (!_entered && !_scheduled) {
          _scheduled = true;
          Future<void>.delayed(const Duration(milliseconds: 750), () {
            if (mounted) setState(() => _entered = true);
          });
        }
        return SliverList.builder(
          itemCount: artists.length,
          itemBuilder: (context, i) {
            final a = artists[i];
            return StaggeredAppear(
              index: i,
              animate: !_entered && i < _cap,
              child: Pressable(
                onTap: () => openArtist(context, a.name),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        LumenTokens.pagePad,
                        8,
                        LumenTokens.pagePad,
                        8,
                      ),
                      child: Row(
                        children: [
                          AlbumArt(
                            artworkPath: resolver?.localPath(a.name),
                            seed: 'ar_${a.name}',
                            size: 54,
                            radius: LumenTokens.rPill,
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  a.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${a.songCount} song${a.songCount == 1 ? '' : 's'}',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    color: LumenTokens.fgDimOf(context),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.chevron_right,
                            size: 20,
                            color: LumenTokens.fgDim2Of(context),
                          ),
                        ],
                      ),
                    ),
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

/// 2-column grid of album cards → album detail page.
class _AlbumsSliver extends ConsumerStatefulWidget {
  const _AlbumsSliver();

  @override
  ConsumerState<_AlbumsSliver> createState() => _AlbumsSliverState();
}

class _AlbumsSliverState extends ConsumerState<_AlbumsSliver> {
  static const _cap = 8;
  bool _entered = false;
  bool _scheduled = false;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(albumsProvider);
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
        if (!_entered && !_scheduled) {
          _scheduled = true;
          Future<void>.delayed(const Duration(milliseconds: 750), () {
            if (mounted) setState(() => _entered = true);
          });
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
            delegate: SliverChildBuilderDelegate((context, i) {
              final al = list[i];
              return StaggeredAppear(
                index: i,
                animate: !_entered && i < _cap,
                child: Pressable(
                  onTap: () => openAlbum(context, al.name),
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
                ),
              );
            }, childCount: list.length),
          ),
        );
      },
    );
  }
}

class _PlaylistsSliver extends ConsumerStatefulWidget {
  const _PlaylistsSliver();

  @override
  ConsumerState<_PlaylistsSliver> createState() => _PlaylistsSliverState();
}

class _PlaylistsSliverState extends ConsumerState<_PlaylistsSliver> {
  static const _cap = 8;
  bool _entered = false;
  bool _scheduled = false;

  @override
  Widget build(BuildContext context) {
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
        if (!_entered && !_scheduled) {
          _scheduled = true;
          Future<void>.delayed(const Duration(milliseconds: 750), () {
            if (mounted) setState(() => _entered = true);
          });
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
            delegate: SliverChildBuilderDelegate((context, i) {
              final pl = list[i];
              return StaggeredAppear(
                index: i,
                animate: !_entered && i < _cap,
                child: RepaintBoundary(
                  child: Pressable(
                    onTap: () => Navigator.of(
                      context,
                    ).pushLumen((_) => PlaylistDetailScreen(playlistId: pl.id)),
                    child: Glass(
                      borderRadius: LumenTokens.rLg,
                      padding: const EdgeInsets.all(10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: AspectRatio(
                              aspectRatio: 1,
                              child: LayoutBuilder(
                                builder: (context, c) => PlaylistCover(
                                  playlistId: pl.id,
                                  size: c.maxWidth,
                                  radius: LumenTokens.rXs,
                                ),
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
                ),
              );
            }, childCount: list.length),
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
