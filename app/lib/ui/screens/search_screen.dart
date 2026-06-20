import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database/app_database.dart';
import '../../data/models/remote_artist.dart';
import '../../features/library/artist_image_resolver.dart';
import '../../features/library/detail_providers.dart';
import '../../features/library/home_providers.dart';
import '../../features/library/library_filters.dart';
import '../../features/library/providers.dart';
import '../../features/player/now_playing_controller.dart';
import '../../features/player/providers.dart';
import '../../features/search/search_controller.dart';
import '../motion/fade_through_switcher.dart';
import '../theme/app_theme.dart';
import '../widgets/album_art.dart';
import '../widgets/glass_kit.dart';
import '../../features/player/player_expansion_controller.dart';
import '../widgets/song_actions.dart';
import '../widgets/song_tile.dart';
import 'entity_nav.dart';

/// Lumen search — artists-first layout.
///
/// Empty state shows large round artist avatars in a horizontal rail
/// (top library artists), then a 6-card "Browse all" gradient grid. As
/// soon as the user types, the avatars + grid hide and the song
/// results take over.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _setQuery(String q) {
    _controller.text = q;
    _controller.selection = TextSelection.collapsed(
      offset: _controller.text.length,
    );
    ref.read(librarySearchControllerProvider.notifier).onQueryChanged(q);
  }

  Future<void> _open(List<SongRow> queue, int index) async {
    // Tapping a result means the user is done typing — drop the keyboard so
    // it doesn't stay up over the player when it expands. Unfocus the active
    // node directly so it works regardless of focus-scope nesting.
    FocusManager.instance.primaryFocus?.unfocus();
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(nowPlayingProvider.notifier).playFromQueue(queue, index);
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not play file: $e')),
      );
      return;
    }
    if (!mounted) return;
    PlayerExpansionScope.read(context).expand();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(librarySearchControllerProvider);
    final playingId = ref.watch(nowPlayingProvider.select((s) => s?.id));

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        0,
        LumenTokens.topSafePad,
        0,
        LumenTokens.bottomSafePad,
      ),
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(
            LumenTokens.pagePad,
            0,
            LumenTokens.pagePad,
            16,
          ),
          child: Text(
            'Search',
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w800,
              letterSpacing: -1,
              height: 1.05,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            LumenTokens.pagePad,
            0,
            LumenTokens.pagePad,
            22,
          ),
          child: GlassField(
            controller: _controller,
            hint: 'Artists, songs, albums',
            leading: Icon(
              Icons.search,
              size: 18,
              color: LumenTokens.fgDimOf(context),
            ),
            trailing: state.query.isEmpty
                ? null
                : Pressable(
                    onTap: () {
                      _controller.clear();
                      ref
                          .read(librarySearchControllerProvider.notifier)
                          .onQueryChanged('');
                    },
                    child: Icon(
                      Icons.clear,
                      size: 18,
                      color: LumenTokens.fgDimOf(context),
                    ),
                  ),
            onChanged: (q) => ref
                .read(librarySearchControllerProvider.notifier)
                .onQueryChanged(q),
          ),
        ),
        // Browse ↔ loading ↔ results cross-fade instead of hard-cutting.
        FadeThroughSwitcher(
          child: state.query.isEmpty
              ? Column(
                  key: const ValueKey('browse'),
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _ArtistsRail(),
                    const SizedBox(height: 22),
                    const Padding(
                      padding: EdgeInsets.fromLTRB(
                        LumenTokens.pagePad,
                        0,
                        LumenTokens.pagePad,
                        12,
                      ),
                      child: Text(
                        'Browse all',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ),
                    _BrowseGrid(onPickGenre: _setQuery),
                  ],
                )
              : state.loading
              ? const Padding(
                  key: ValueKey('loading'),
                  padding: EdgeInsets.all(40),
                  child: Center(child: CircularProgressIndicator()),
                )
              : Column(
                  key: const ValueKey('results'),
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: _buildResults(context, state, playingId),
                ),
        ),
      ],
    );
  }

  Widget _resultHeader(BuildContext context, String title) => Padding(
    padding: const EdgeInsets.fromLTRB(
      LumenTokens.pagePad,
      12,
      LumenTokens.pagePad,
      8,
    ),
    child: Text(
      title.toUpperCase(),
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.6,
        color: LumenTokens.fgDim2Of(context),
      ),
    ),
  );

  /// Combined results: matching artists + albums (linking to their pages)
  /// above the song matches.
  List<Widget> _buildResults(
    BuildContext context,
    SearchState state,
    String? playingId,
  ) {
    final q = state.query.trim().toLowerCase();
    final allSongs =
        ref.watch(allSongsProvider).valueOrNull ?? const <SongRow>[];
    final isPlaying =
        ref.watch(playerStateStreamProvider).valueOrNull?.playing ?? false;
    final resolver = ref.watch(artistImageResolverProvider).valueOrNull;

    final artistSet = <String>{};
    for (final s in allSongs) {
      for (final a in splitMultiArtist(s.artist)) {
        if (a.toLowerCase().contains(q)) artistSet.add(a);
      }
    }
    final artists = artistSet.toList()..sort();
    final albums = rollupAlbums(
      allSongs,
    ).where((al) => al.name.toLowerCase().contains(q)).toList();
    final songs = state.results;

    if (artists.isEmpty && albums.isEmpty && songs.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.all(40),
          child: Center(
            child: Text(
              'No matches for "${state.query}".',
              textAlign: TextAlign.center,
              style: TextStyle(color: LumenTokens.fgDimOf(context)),
            ),
          ),
        ),
      ];
    }

    return [
      if (artists.isNotEmpty) ...[
        _resultHeader(context, 'Artists'),
        for (final a in artists.take(4))
          Pressable(
            onTap: () {
              FocusScope.of(context).unfocus();
              openArtist(context, a);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: LumenTokens.pagePad,
                vertical: 8,
              ),
              child: Row(
                children: [
                  AlbumArt(
                    artworkPath: resolver?.localPath(a),
                    seed: 'ar_$a',
                    size: 46,
                    radius: LumenTokens.rPill,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      a,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: LumenTokens.fgDim2Of(context),
                  ),
                ],
              ),
            ),
          ),
      ],
      if (albums.isNotEmpty) ...[
        _resultHeader(context, 'Albums'),
        for (final al in albums.take(4))
          Pressable(
            onTap: () {
              FocusScope.of(context).unfocus();
              openAlbum(context, al.name);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: LumenTokens.pagePad,
                vertical: 8,
              ),
              child: Row(
                children: [
                  AlbumArt(
                    artworkPath: al.coverPath,
                    seed: al.coverSeed,
                    size: 46,
                    radius: 8,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          al.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (al.artist.isNotEmpty)
                          Text(
                            al.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: LumenTokens.fgDimOf(context),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
      if (songs.isNotEmpty) ...[
        _resultHeader(context, 'Songs'),
        for (var i = 0; i < songs.length; i++)
          SongTile(
            song: songs[i],
            isPlaying: playingId == songs[i].id,
            onTap: () {
              if (playingId == songs[i].id && isPlaying) {
                FocusManager.instance.primaryFocus?.unfocus();
                PlayerExpansionScope.maybeRead(context)?.expand();
              } else {
                _open(songs, i);
              }
            },
            onLongPress: () => SongActionsSheet.show(context, songs[i]),
          ),
      ],
    ];
  }
}

class _ArtistsRail extends ConsumerWidget {
  const _ArtistsRail();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final artists = ref.watch(topArtistsProvider).valueOrNull ?? const [];
    if (artists.isEmpty) return const SizedBox.shrink();

    final resolver = ref.watch(artistImageResolverProvider).valueOrNull;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(
            LumenTokens.pagePad,
            0,
            LumenTokens.pagePad,
            14,
          ),
          child: Text(
            'Artists you love',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
            ),
          ),
        ),
        SizedBox(
          height: 132,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(
              horizontal: LumenTokens.pagePad,
            ),
            itemCount: artists.length,
            itemBuilder: (context, i) {
              final a = artists[i];
              return Padding(
                padding: const EdgeInsets.only(right: 14),
                child: Pressable(
                  onTap: () => openArtist(context, a.name),
                  child: SizedBox(
                    width: 100,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.10),
                              width: 2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.28),
                                blurRadius: 22,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: AlbumArt(
                            artworkPath: resolver?.localPath(a.name),
                            seed: 'ar_${a.name}',
                            size: 96,
                            radius: LumenTokens.rPill,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          a.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Browse tiles built from the library's *real* genres, so a tap returns
/// actual results (the old hardcoded "Pop"/"Charts" labels matched nothing).
class _BrowseGrid extends ConsumerWidget {
  const _BrowseGrid({required this.onPickGenre});

  final ValueChanged<String> onPickGenre;

  static const _gradients = <List<Color>>[
    [Color(0xFF6B5BFF), LumenTokens.accent],
    [Color(0xFFFF6B9D), Color(0xFFFFD36B)],
    [Color(0xFF2A1F5E), Color(0xFF5BE0FF)],
    [Color(0xFFFF9E5E), Color(0xFFFF6B9D)],
    [Color(0xFFFFD36B), Color(0xFFFF9E5E)],
    [Color(0xFF5BE0FF), Color(0xFF6B5BFF)],
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final genres =
        ref.watch(libraryGenresProvider).valueOrNull ?? const <String>[];
    if (genres.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: LumenTokens.pagePad),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: genres.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 14,
          crossAxisSpacing: 14,
          mainAxisExtent: 96,
        ),
        itemBuilder: (context, i) => _GenreCard(
          name: genres[i],
          colors: _gradients[i % _gradients.length],
          onTap: () => onPickGenre(genres[i]),
        ),
      ),
    );
  }
}

/// Browse tile. Keeps the vibrant gradient (Apple/Spotify-style browse)
/// but layers the iOS-26 diagonal refraction shine over it and trades
/// the harsh black drop-shadow for a soft glow tinted to the card's own
/// colour — so it reads as a lit pane, not a flat sticker.
class _GenreCard extends StatelessWidget {
  const _GenreCard({
    required this.name,
    required this.colors,
    required this.onTap,
  });

  final String name;
  final List<Color> colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(LumenTokens.rMd),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: colors,
          ),
          boxShadow: [
            BoxShadow(
              color: colors.last.withValues(alpha: 0.30),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(LumenTokens.rMd),
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color(0x33FFFFFF),
                        Colors.transparent,
                        Colors.transparent,
                        Color(0x0FFFFFFF),
                      ],
                      stops: [0.0, 0.3, 0.7, 1.0],
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Align(
                alignment: Alignment.topLeft,
                child: Text(
                  name,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
