import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/album_colors.dart';
import '../../data/database/app_database.dart';
import '../../features/library/album_colors_provider.dart';
import '../../features/library/home_providers.dart';
import '../../features/library/providers.dart';
import '../../features/playlists/providers.dart';
import '../../features/player/now_playing_controller.dart';
import '../../features/player/providers.dart';
import '../theme/app_theme.dart';
import '../widgets/album_art.dart';
import '../widgets/glass.dart';
import '../widgets/playlist_cover.dart';
import '../../features/player/player_expansion_controller.dart';
import 'home_shell_providers.dart';
import 'playlist_detail_screen.dart';

/// Lumen home — iOS 26 redesign.
///
/// Layout (top → bottom):
///   1. Eyebrow date + sentence-cased greeting (top-LEFT; the profile
///      button on the right is owned by HomeShell so the safe-area
///      anchoring stays consistent across tabs).
///   2. Flacko (AI DJ) feature card — pink pitch + Start pill.
///   3. Quick Picks — 2×4 horizontal-row grid, 8 songs per page,
///      swipeable for the next page.
///   4. Your playlists — horizontal glass-card rail.
///   5. Pick up where you left off — vertical recents list inside one
///      glass chassis.
///   6. New for you — secondary art rail (lazy when there's content).
///   7. In rotation — round artist avatars.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  static const _topPad = LumenTokens.topSafePad;
  static const _bottomPad = LumenTokens.bottomSafePad;
  static const _hPad = LumenTokens.pagePad;

  Future<void> _open(
    BuildContext context,
    WidgetRef ref,
    List<SongRow> queue,
    int index,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(nowPlayingProvider.notifier).playFromQueue(queue, index);
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not play file: $e')),
      );
      return;
    }
    if (!context.mounted) return;
    PlayerExpansionScope.read(context).expand();
  }

  Future<void> _createPlaylist(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('New playlist'),
          content: TextField(
            controller: controller,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(hintText: 'Playlist name'),
            onSubmitted: (value) => Navigator.of(context).pop(value.trim()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(controller.text.trim()),
              child: const Text('Create'),
            ),
          ],
        );
      },
    );
    controller.dispose();
    if (name == null || name.isEmpty) return;
    await ref.read(playlistRepositoryProvider).create(name);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    final recents = ref.watch(recentlyPlayedProvider).valueOrNull ?? const [];
    final added = ref.watch(recentlyAddedProvider).valueOrNull ?? const [];
    final favorites =
        ref.watch(favoriteSongsProvider).valueOrNull ?? const [];
    final playlists = ref.watch(allPlaylistsProvider).valueOrNull ?? const [];
    final currentSong = ref.watch(nowPlayingProvider);
    final isPlaying = ref.watch(playerStateStreamProvider).valueOrNull?.playing ?? false;
    // Quick Picks pulls from recently-played first, falls back to
    // recently-added so a fresh-synced library still has content.
    final quickPicks = recents.isNotEmpty ? recents : added;

    // Swipeable glass-list trio for the "Pick up where you left off"
    // slot. Only pages with content are shown; if just one page exists,
    // the widget falls back to a static glass card with no pagination.
    final pickupPages = <_GlassListPage>[
      if (recents.isNotEmpty)
        _GlassListPage(
            title: 'Pick up where you left off',
            songs: recents.take(4).toList()),
      // "In rotation" reuses recently-added so it doesn't duplicate the
      // first page's data — same surface, fresh slice of the library.
      if (added.isNotEmpty)
        _GlassListPage(
            title: 'In rotation',
            songs: added.take(4).toList()),
      if (added.length > 4)
        _GlassListPage(
            title: 'New for you',
            songs: added.skip(4).take(4).toList()),
      if (favorites.isNotEmpty)
        _GlassListPage(
            title: 'Your favorites',
            songs: favorites.take(4).toList()),
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 0, 0, _bottomPad),
      children: [
        _HomeTopSection(
          now: now,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: _topPad),
              Padding(
                padding: const EdgeInsets.fromLTRB(_hPad, 0, _hPad, 22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      LumenTod.dateLabel(now),
                      style: TextStyle(
                        fontSize: 11,
                        letterSpacing: 0.5,
                        fontWeight: FontWeight.w700,
                        color: Colors.white.withValues(alpha: 0.72),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      LumenTod.greetingFor(now),
                      style: const TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -1,
                        height: 1.05,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              if (quickPicks.isNotEmpty)
                _QuickPicks(
                  songs: quickPicks,
                  currentSongId: currentSong?.id,
                  isPlaying: isPlaying,
                  onTap: (queue, i) => _open(context, ref, queue, i),
                ),
            ],
          ),
        ),

        if (pickupPages.isNotEmpty)
          _SwipeableGlassList(
            pages: pickupPages,
            onTap: (queue, i) => _open(context, ref, queue, i),
          ),

        _PlaylistsRail(
          playlists: playlists,
          onCreate: () => _createPlaylist(context, ref),
          onSeeAll: () {
            ref.read(libraryChipProvider.notifier).state = 'Playlists';
            ref.read(homeTabIndexProvider.notifier).state = 3;
          },
        ),

        if (recents.isEmpty && added.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
            child: Text(
              'Sync your library from the profile menu (top-right) to get '
              'started.',
              textAlign: TextAlign.center,
              style: TextStyle(color: LumenTokens.fgDimOf(context)),
            ),
          ),
      ],
    );
  }
}

class _HomeTopSection extends StatelessWidget {
  const _HomeTopSection({required this.now, required this.child});
  final DateTime now;
  final Widget child;

  String get _assetPath {
    final hour = now.hour;
    if (hour < 5) return 'assets/quick_pick_bg/night.jpg';
    if (hour < 8) return 'assets/quick_pick_bg/sunrise.jpg';
    if (hour < 12) return 'assets/quick_pick_bg/morning.jpg';
    if (hour < 16) return 'assets/quick_pick_bg/mid day.jpg';
    if (hour < 18) return 'assets/quick_pick_bg/aftrnnon.jpg';
    if (hour < 21) return 'assets/quick_pick_bg/sundown.jpg';
    return 'assets/quick_pick_bg/night.jpg';
  }

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(
        bottom: Radius.circular(LumenTokens.rLg),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: Image.asset(
                _assetPath,
                fit: BoxFit.cover,
                alignment: Alignment.topCenter,
              ),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: isLight ? 0.34 : 0.18),
                      Colors.black.withValues(alpha: isLight ? 0.52 : 0.58),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Theme(
            data: Theme.of(context).copyWith(brightness: Brightness.dark),
            child: child,
          ),
        ],
      ),
    );
  }
}

/// Quick Picks — YouTube-Music-style 2×4 song grid, swipe horizontally
/// for the next 8. Each page is a hand-laid Column-of-Rows (not a
/// GridView) so horizontal drags pass straight through to the PageView
/// instead of being eaten by an inner Scrollable.
class _QuickPicks extends StatefulWidget {
  const _QuickPicks({
    required this.songs,
    required this.currentSongId,
    required this.isPlaying,
    required this.onTap,
  });
  final List<SongRow> songs;
  final String? currentSongId;
  final bool isPlaying;

  /// Fires with `(queue, index)` so the player can populate a real queue
  /// (and so prev/next buttons stay enabled while playing the row).
  final void Function(List<SongRow> queue, int index) onTap;

  static const _cols = 1;
  static const _rows = 4;
  static const _perPage = _cols * _rows;
  static const _rowHeight = 78.0;
  static const _rowGap = 14.0;
  static const _colGap = 16.0;
  static const _pageHeight = _rowHeight * _rows + _rowGap * (_rows - 1);

  @override
  State<_QuickPicks> createState() => _QuickPicksState();
}

class _QuickPicksState extends State<_QuickPicks> {
  static const _initialPage = 10000;
  final PageController _ctrl = PageController(
    initialPage: _initialPage,
    viewportFraction: 0.88,
  );

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.songs.isEmpty) return const SizedBox.shrink();

    final pages = <List<SongRow>>[];
    for (var i = 0; i < widget.songs.length; i += _QuickPicks._perPage) {
      pages.add(widget.songs.sublist(
          i, (i + _QuickPicks._perPage).clamp(0, widget.songs.length)));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(
              LumenTokens.pagePad, 14, LumenTokens.pagePad, 12),
          child: Text(
            'Quick picks',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
            ),
          ),
        ),
        SizedBox(
          height: _QuickPicks._pageHeight,
          child: PageView.builder(
            controller: _ctrl,
            padEnds: false,
            itemBuilder: (context, pi) {
              final actualPageIndex =
                  (pi - _initialPage) % pages.length;
              final pageSongs = pages[actualPageIndex];
              final pageStart =
                  actualPageIndex * _QuickPicks._perPage;
              final isLight = Theme.of(context).brightness == Brightness.light;
              return Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: LumenTokens.pagePad),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(LumenTokens.rXs),
                    color:
                        Colors.white.withValues(alpha: isLight ? 0.48 : 0.055),
                    border: Border.all(
                      color: Colors.white
                          .withValues(alpha: isLight ? 0.64 : 0.08),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var c = 0; c < _QuickPicks._cols; c++) ...[
                        if (c > 0) const SizedBox(width: _QuickPicks._colGap),
                        Expanded(
                          child: Column(
                            children: [
                              for (var r = 0; r < _QuickPicks._rows; r++) ...[
                                if (r > 0)
                                  const SizedBox(height: _QuickPicks._rowGap),
                                SizedBox(
                                  height: _QuickPicks._rowHeight,
                                  child: (c * _QuickPicks._rows + r <
                                          pageSongs.length)
                                      ? _SongRow(
                                          song: pageSongs[
                                              c * _QuickPicks._rows + r],
                                          active: widget.currentSongId ==
                                              pageSongs[c *
                                                          _QuickPicks._rows +
                                                      r]
                                                  .id,
                                          playing: widget.isPlaying,
                                          onTap: () => widget.onTap(
                                            widget.songs,
                                            pageStart +
                                                c * _QuickPicks._rows +
                                                r,
                                          ),
                                        )
                                      : const SizedBox.expand(),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 26),
      ],
    );
  }
}

class _SongRow extends ConsumerWidget {
  const _SongRow({
    required this.song,
    required this.active,
    required this.playing,
    required this.onTap,
  });
  final SongRow song;
  final bool active;
  final bool playing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Active rows pick up the song's own dominant artwork colour instead
    // of the global pink accent. Clamp saturation/lightness so washed-out
    // covers don't fade into the background and oversaturated ones don't
    // glare on top of the glass surface.
    Color tint = LumenTokens.accent;
    if (active) {
      final colors = ref
          .watch(albumColorsProvider(song.localArtworkPath))
          .valueOrNull;
      if (colors != null && colors.isNotEmpty) {
        // Greyscale covers come through as a neutral palette — clamping
        // a true grey to 0.55+ saturation would resurface hue=0 (red),
        // so route through the shared accent helper which short-circuits
        // on neutrals.
        tint = AlbumColors.accentFromPalette(colors, fallback: tint);
      }
    }

    final row = InkWell(
      borderRadius: BorderRadius.circular(LumenTokens.rXs),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        child: Row(
          children: [
            AlbumArt(
              artworkPath: song.localArtworkPath,
              seed: song.id,
              size: 60,
              radius: 10,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    song.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: active ? FontWeight.w800 : FontWeight.w700,
                      height: 1.2,
                      color: active ? tint : null,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      if (active) ...[
                        Icon(
                          playing ? Icons.graphic_eq : Icons.pause_circle_filled,
                          size: 14,
                          color: tint,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          playing ? 'Playing' : 'Paused',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                            color: tint,
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      Expanded(
                        child: Text(
                          song.artist ?? 'Unknown artist',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: active
                                ? LumenTokens.fg(context)
                                : LumenTokens.fgDimOf(context),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    return row;
  }
}

class _PageDots extends StatelessWidget {
  const _PageDots({required this.count, required this.active});
  final int count;
  final int active;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(count, (i) {
        final isActive = i == active;
        return Padding(
          padding: const EdgeInsets.only(left: 6),
          child: AnimatedContainer(
            duration: LumenTokens.dFast,
            curve: LumenTokens.easeOut,
            width: isActive ? 18 : 6,
            height: 6,
            decoration: BoxDecoration(
              color: isActive
                  ? LumenTokens.accent
                  : (Theme.of(context).brightness == Brightness.dark
                      ? LumenTokens.fgDisabled
                      : LumenTokens.fgLightDisabled),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        );
      }),
    );
  }
}

/// Horizontal rail of glass playlist cards.
class _PlaylistsRail extends StatelessWidget {
  const _PlaylistsRail({
    required this.playlists,
    required this.onCreate,
    required this.onSeeAll,
  });
  final List<PlaylistRow> playlists;
  final VoidCallback onCreate;
  final VoidCallback onSeeAll;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(
          title: 'Your playlists',
          action: 'See All',
          onAction: onSeeAll,
        ),
        SizedBox(
          height: 200,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(
                horizontal: LumenTokens.pagePad),
            itemCount: playlists.length + 1,
            itemBuilder: (context, i) {
              if (i == 0) {
                return Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: SizedBox(
                    width: 150,
                    child: GestureDetector(
                      onTap: onCreate,
                      child: Glass(
                        borderRadius: LumenTokens.rLg,
                        padding: const EdgeInsets.all(10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius:
                                      BorderRadius.circular(LumenTokens.rXs),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.16),
                                  ),
                                ),
                                child: const Center(
                                  child: Icon(Icons.add_rounded, size: 42),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'New playlist',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              'Create from here',
                              style: TextStyle(
                                fontSize: 11,
                                color: LumenTokens.fgDimOf(context),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }

              final p = playlists[i - 1];
              return Padding(
                padding: const EdgeInsets.only(right: 12),
                child: SizedBox(
                  width: 150,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(LumenTokens.rLg),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            PlaylistDetailScreen(playlistId: p.id),
                      ),
                    ),
                    child: Glass(
                      borderRadius: LumenTokens.rLg,
                      padding: const EdgeInsets.all(10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          PlaylistCover(
                            playlistId: p.id,
                            size: 130,
                            radius: LumenTokens.rXs,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            p.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            'Playlist',
                            style: TextStyle(
                              fontSize: 11,
                              color: LumenTokens.fgDimOf(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 18),
      ],
    );
  }
}

/// One page inside [_SwipeableGlassList].
class _GlassListPage {
  const _GlassListPage({required this.title, required this.songs});
  final String title;
  final List<SongRow> songs;
}

/// Swipeable trio of glass-card lists — same vertical-row chassis used
/// originally for "Pick up where you left off", now extended so the
/// user can swipe to "In rotation" and "Your favorites" without
/// scrolling further down. The header title fades between pages,
/// pagination dots sit on the right.
class _SwipeableGlassList extends StatefulWidget {
  const _SwipeableGlassList({required this.pages, required this.onTap});
  final List<_GlassListPage> pages;

  /// Fires with `(queue, index)`. Each page treats its own song list as
  /// the queue so prev/next walk that page rather than escaping to
  /// neighbouring pages.
  final void Function(List<SongRow> queue, int index) onTap;

  @override
  State<_SwipeableGlassList> createState() => _SwipeableGlassListState();
}

class _SwipeableGlassListState extends State<_SwipeableGlassList> {
  static const _initialPage = 10000;
  late final PageController _ctrl = PageController(initialPage: _initialPage);
  int _page = 0;

  // 4 rows × ~60px each (44 art + 16 padding) = ~240. The exact
  // height is computed against the longest page so the PageView's
  // SizedBox doesn't snap heights between pages.
  static const _rowHeight = 60.0;
  static const _glassPadding = 12.0; // 6 × 2 outer Glass padding

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final maxRows = widget.pages
        .map((p) => p.songs.length)
        .fold<int>(0, (m, n) => n > m ? n : m);
    final pageHeight = _rowHeight * maxRows + _glassPadding;
    final active = widget.pages[_page % widget.pages.length];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
              LumenTokens.pagePad, 4, LumenTokens.pagePad, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: AnimatedSwitcher(
                  duration: LumenTokens.dFast,
                  layoutBuilder: (currentChild, previousChildren) => Stack(
                    alignment: Alignment.centerLeft,
                    children: [
                      ...previousChildren,
                      ?currentChild,
                    ],
                  ),
                  transitionBuilder: (child, anim) =>
                      FadeTransition(opacity: anim, child: child),
                  child: Text(
                    active.title,
                    key: ValueKey(active.title),
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.5,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: pageHeight,
          child: PageView.builder(
            controller: _ctrl,
            onPageChanged: (i) =>
                setState(() => _page = (i - _initialPage) % widget.pages.length),
            itemBuilder: (context, pi) {
              final page = widget.pages[(pi - _initialPage) % widget.pages.length];
              return Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: LumenTokens.pagePad),
                child: _GlassListContent(
                  songs: page.songs,
                  onTap: widget.onTap,
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 18),
      ],
    );
  }
}

/// The visual chassis itself — a translucent Glass container holding
/// a vertical stack of song rows. Identical between pages so the
/// swipe is felt as content swap, not surface swap.
class _GlassListContent extends StatelessWidget {
  const _GlassListContent({required this.songs, required this.onTap});
  final List<SongRow> songs;
  final void Function(List<SongRow> queue, int index) onTap;

  @override
  Widget build(BuildContext context) {
    return Glass(
      borderRadius: LumenTokens.rLg,
      padding: const EdgeInsets.all(6),
      // ClipRect absorbs the ~2 px of rounding-error overflow when the
      // glass card's fixed page height divides into N rows that don't
      // sum to exactly the available space. Better than tuning the row
      // padding because the row count changes between pages.
      child: ClipRect(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < songs.length; i++)
              _glassRow(context, songs, i),
          ],
        ),
      ),
    );
  }

  Widget _glassRow(BuildContext context, List<SongRow> songs, int i) {
    final s = songs[i];
    return InkWell(
              borderRadius: BorderRadius.circular(LumenTokens.rXs),
              onTap: () => onTap(songs, i),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  children: [
                    AlbumArt(
                      artworkPath: s.localArtworkPath,
                      seed: s.id,
                      size: 44,
                      radius: 10,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            s.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            [s.artist, s.album]
                                .whereType<String>()
                                .where((t) => t.isNotEmpty)
                                .join(' · '),
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
                    Icon(
                      Icons.more_horiz,
                      size: 18,
                      color: LumenTokens.fgDimOf(context),
                    ),
                  ],
                ),
              ),
            );
  }
}

/// Section header — title + optional trailing action.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    this.action,
    this.onAction,
  });

  final String title;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          LumenTokens.pagePad, 4, LumenTokens.pagePad, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5,
              ),
            ),
          ),
          if (action != null)
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: onAction,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 6, vertical: 4),
                child: Text(
                  action!,
                  style: const TextStyle(
                    color: LumenTokens.accent,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// One page inside [_SwipeableArtRail]. Each page has its own header
/// (eyebrow + title) and its own song list — same visual style across
/// pages, only the content differs.
class _RailPage {
  const _RailPage({
    required this.eyebrow,
    required this.title,
    required this.songs,
  });
  final String eyebrow;
  final String title;
  final List<SongRow> songs;
}

/// Swipeable horizontal stack of art rails. The header (eyebrow + title)
/// fades between pages; pagination dots sit on the right. Each page
/// renders the same `_ArtRail` so the visual rhythm is identical
/// across "New for you", "In rotation", and "Your favorites".
class _SwipeableArtRail extends StatefulWidget {
  const _SwipeableArtRail({required this.pages, required this.onTap});
  final List<_RailPage> pages;
  final ValueChanged<SongRow> onTap;

  @override
  State<_SwipeableArtRail> createState() => _SwipeableArtRailState();
}

class _SwipeableArtRailState extends State<_SwipeableArtRail> {
  late final PageController _ctrl = PageController();
  int _page = 0;
  static const _tileSize = 140.0;
  static const _railHeight = _tileSize + 56;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.pages[_page.clamp(0, widget.pages.length - 1)];
    final showPager = widget.pages.length > 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Animated header — title swap is a 180ms fade so the eye lands
        // on the new heading right as the rail finishes paging.
        Padding(
          padding: const EdgeInsets.fromLTRB(LumenTokens.pagePad, 4,
              LumenTokens.pagePad, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: AnimatedSwitcher(
                  duration: LumenTokens.dFast,
                  transitionBuilder: (child, anim) =>
                      FadeTransition(opacity: anim, child: child),
                  child: Column(
                    key: ValueKey(active.title),
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        active.eyebrow,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                          color: LumenTokens.fgDim2Of(context),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        active.title,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (showPager)
                _PageDots(count: widget.pages.length, active: _page),
            ],
          ),
        ),
        SizedBox(
          height: _railHeight,
          child: PageView.builder(
            controller: _ctrl,
            onPageChanged: (i) => setState(() => _page = i),
            itemCount: widget.pages.length,
            itemBuilder: (context, pi) {
              return _ArtRail(
                songs: widget.pages[pi].songs,
                tileSize: _tileSize,
                onTap: widget.onTap,
              );
            },
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

/// Horizontal scroller of square album-art tiles with title/artist below.
/// Used as the per-page content of [_SwipeableArtRail].
class _ArtRail extends StatelessWidget {
  const _ArtRail({
    required this.songs,
    required this.tileSize,
    required this.onTap,
  });

  final List<SongRow> songs;
  final double tileSize;
  final ValueChanged<SongRow> onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: tileSize + 52,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: LumenTokens.pagePad),
        itemCount: songs.length,
        itemBuilder: (context, i) {
          final s = songs[i];
          return Padding(
            padding: const EdgeInsets.only(right: 14),
            child: SizedBox(
              width: tileSize,
              child: GestureDetector(
                onTap: () => onTap(s),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AlbumArt(
                      artworkPath: s.localArtworkPath,
                      seed: s.id,
                      size: tileSize,
                      radius: LumenTokens.rSm,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      s.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (s.artist != null)
                      Text(
                        s.artist!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color: LumenTokens.fgDimOf(context),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
