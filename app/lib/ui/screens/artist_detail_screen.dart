import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database/app_database.dart';
import '../motion/animated_appear.dart';
import '../motion/lumen_route.dart';
import '../../features/ai_dj/providers.dart';
import '../../features/library/artist_image_resolver.dart';
import '../../features/library/detail_providers.dart';
import '../../features/nav/content_navigator_scope.dart';
import '../../features/player/now_playing_controller.dart';
import '../../features/player/player_expansion_controller.dart';
import '../../features/player/providers.dart';
import '../theme/app_theme.dart';
import '../widgets/album_art.dart';
import '../widgets/glass_kit.dart';
import '../widgets/song_actions.dart';
import '../widgets/song_tile.dart';
import 'album_detail_screen.dart';

/// All songs and albums credited to a single artist, with play/shuffle.
class ArtistDetailScreen extends ConsumerWidget {
  const ArtistDetailScreen({super.key, required this.artist});

  final String artist;

  Future<void> _play(
    BuildContext context,
    WidgetRef ref,
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
    PlayerExpansionScope.maybeRead(context)?.expand();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final songsAsync = ref.watch(songsByArtistProvider(artist));
    final albums =
        ref.watch(albumsByArtistProvider(artist)).valueOrNull ??
        const <AlbumRef>[];
    final resolver = ref.watch(artistImageResolverProvider).valueOrNull;
    final playingId = ref.watch(nowPlayingProvider.select((s) => s?.id));
    final isPlaying =
        ref.watch(playerStateStreamProvider).valueOrNull?.playing ?? false;
    final bottomPad = hasPersistentChrome(context)
        ? LumenTokens.bottomSafePad
        : 40.0;

    return StageScaffold(
      body: songsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (songs) {
          if (songs.isEmpty) {
            return Center(
              child: Text(
                'No songs by $artist',
                style: TextStyle(color: LumenTokens.fgDimOf(context)),
              ),
            );
          }
          return ListView(
            padding: EdgeInsets.only(bottom: bottomPad),
            children: [
              // ── Header: image + name + counts + play/shuffle ──
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  LumenTokens.pagePad,
                  4,
                  LumenTokens.pagePad,
                  8,
                ),
                child: Column(
                  children: [
                    AnimatedAppear(
                      scale: true,
                      offsetY: 0,
                      child: AlbumArt(
                        artworkPath: resolver?.localPath(artist),
                        seed: 'ar_$artist',
                        size: 132,
                        radius: LumenTokens.rPill,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      artist,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.6,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${songs.length} song${songs.length == 1 ? '' : 's'}'
                      '${albums.isEmpty ? '' : ' · ${albums.length} album${albums.length == 1 ? '' : 's'}'}',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: LumenTokens.fgDimOf(context),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        GlassButton(
                          label: 'Play',
                          icon: Icons.play_arrow_rounded,
                          primary: true,
                          onPressed: () => _play(context, ref, songs, 0),
                        ),
                        const SizedBox(width: 12),
                        GlassIconButton(
                          icon: Icons.shuffle_rounded,
                          size: 52,
                          iconSize: 22,
                          onTap: () {
                            final shuffled = [...songs]..shuffle();
                            _play(context, ref, shuffled, 0);
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // ── Albums rail ──
              if (albums.isNotEmpty) ...[
                const SizedBox(height: 8),
                const Padding(
                  padding: EdgeInsets.fromLTRB(
                    LumenTokens.pagePad,
                    8,
                    LumenTokens.pagePad,
                    12,
                  ),
                  child: Text(
                    'Albums',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.5,
                    ),
                  ),
                ),
                SizedBox(
                  height: 184,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(
                      horizontal: LumenTokens.pagePad,
                    ),
                    itemCount: albums.length,
                    itemBuilder: (context, i) {
                      final al = albums[i];
                      return Padding(
                        padding: const EdgeInsets.only(right: 14),
                        child: Pressable(
                          onTap: () => Navigator.of(
                            context,
                          ).pushLumen((_) => AlbumDetailScreen(album: al.name)),
                          child: SizedBox(
                            width: 134,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                AlbumArt(
                                  artworkPath: al.coverPath,
                                  seed: al.coverSeed,
                                  size: 134,
                                  radius: LumenTokens.rSm,
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
                                  '${al.songCount} song${al.songCount == 1 ? '' : 's'}',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: LumenTokens.fgDim2Of(context),
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
                const SizedBox(height: 18),
              ],

              // ── Songs ──
              const Padding(
                padding: EdgeInsets.fromLTRB(
                  LumenTokens.pagePad,
                  4,
                  LumenTokens.pagePad,
                  8,
                ),
                child: Text(
                  'Songs',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                  ),
                ),
              ),
              for (var i = 0; i < songs.length; i++)
                SongTile(
                  song: songs[i],
                  isPlaying: playingId == songs[i].id,
                  linkEntities: false,
                  onTap: () {
                    if (playingId == songs[i].id && isPlaying) {
                      PlayerExpansionScope.maybeRead(context)?.expand();
                    } else {
                      _play(context, ref, songs, i);
                    }
                  },
                  onLongPress: () => SongActionsSheet.show(context, songs[i]),
                ),
            ],
          );
        },
      ),
    );
  }
}
