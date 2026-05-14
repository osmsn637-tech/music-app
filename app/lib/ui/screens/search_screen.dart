import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database/app_database.dart';
import '../../features/library/artist_image_resolver.dart';
import '../../features/library/home_providers.dart';
import '../../features/player/now_playing_controller.dart';
import '../../features/search/search_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/album_art.dart';
import '../widgets/glass.dart';
import '../widgets/mini_player.dart' show openPlayerRoute;
import '../widgets/song_actions.dart';
import '../widgets/song_tile.dart';

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
    _controller.selection =
        TextSelection.collapsed(offset: _controller.text.length);
    ref.read(librarySearchControllerProvider.notifier).onQueryChanged(q);
  }

  Future<void> _open(List<SongRow> queue, int index) async {
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
    Navigator.of(context).push(openPlayerRoute());
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(librarySearchControllerProvider);

    return ListView(
      padding: const EdgeInsets.fromLTRB(
          0, LumenTokens.topSafePad, 0, LumenTokens.bottomSafePad),
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(LumenTokens.pagePad, 0,
              LumenTokens.pagePad, 16),
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
          padding: const EdgeInsets.fromLTRB(LumenTokens.pagePad, 0,
              LumenTokens.pagePad, 22),
          child: Glass(
            borderRadius: LumenTokens.rSm,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            child: Row(
              children: [
                Icon(Icons.search,
                    size: 18, color: LumenTokens.fgDimOf(context)),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: InputDecoration(
                      hintText: 'Artists, songs, lyrics, and more',
                      hintStyle: TextStyle(
                        color: LumenTokens.fgDim2Of(context),
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                      border: InputBorder.none,
                      isDense: true,
                    ),
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w500),
                    onChanged: (q) => ref
                        .read(librarySearchControllerProvider.notifier)
                        .onQueryChanged(q),
                  ),
                ),
                if (state.query.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.clear, size: 18),
                    splashRadius: 18,
                    onPressed: () {
                      _controller.clear();
                      ref
                          .read(librarySearchControllerProvider.notifier)
                          .onQueryChanged('');
                    },
                  ),
              ],
            ),
          ),
        ),
        if (state.query.isEmpty) ...[
          const _ArtistsRail(),
          const SizedBox(height: 22),
          const Padding(
            padding: EdgeInsets.fromLTRB(LumenTokens.pagePad, 0,
                LumenTokens.pagePad, 12),
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
        ] else if (state.loading)
          const Padding(
            padding: EdgeInsets.all(40),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (state.results.isEmpty)
          Padding(
            padding: const EdgeInsets.all(40),
            child: Center(
              child: Text(
                'No songs match "${state.query}".',
                style: TextStyle(color: LumenTokens.fgDimOf(context)),
                textAlign: TextAlign.center,
              ),
            ),
          )
        else
          for (var i = 0; i < state.results.length; i++)
            SongTile(
              song: state.results[i],
              onTap: () => _open(state.results, i),
              onLongPress: () =>
                  SongActionsSheet.show(context, state.results[i]),
            ),
      ],
    );
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
          padding: EdgeInsets.fromLTRB(LumenTokens.pagePad, 0,
              LumenTokens.pagePad, 14),
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
                horizontal: LumenTokens.pagePad),
            itemCount: artists.length,
            itemBuilder: (context, i) {
              final a = artists[i];
              return Padding(
                padding: const EdgeInsets.only(right: 14),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => ref
                      .read(librarySearchControllerProvider.notifier)
                      .onQueryChanged(a.name),
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
                                color: Colors.black.withValues(alpha: 0.4),
                                blurRadius: 20,
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

class _BrowseGrid extends StatelessWidget {
  const _BrowseGrid({required this.onPickGenre});

  final ValueChanged<String> onPickGenre;

  static const _genres = [
    _Genre('New Releases', [Color(0xFFFF6B9D), Color(0xFFFFD36B)]),
    _Genre('Hip-Hop', [Color(0xFF6B5BFF), LumenTokens.accent]),
    _Genre('Late Night', [Color(0xFF2A1F5E), Color(0xFF5BE0FF)]),
    _Genre('Pop', [Color(0xFFFF9E5E), Color(0xFFFF6B9D)]),
    _Genre('R&B', [Color(0xFFFFD36B), Color(0xFFFF9E5E)]),
    _Genre('Charts', [Color(0xFF5BE0FF), Color(0xFF6B5BFF)]),
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: LumenTokens.pagePad),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: _genres.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          mainAxisExtent: 84,
        ),
        itemBuilder: (context, i) {
          final g = _genres[i];
          return Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(LumenTokens.rMd),
              onTap: () => onPickGenre(g.name),
              child: Ink(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(LumenTokens.rMd),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: g.colors,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.40),
                      blurRadius: 18,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(14),
                child: Align(
                  alignment: Alignment.topLeft,
                  child: Text(
                    g.name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Genre {
  const _Genre(this.name, this.colors);
  final String name;
  final List<Color> colors;
}
