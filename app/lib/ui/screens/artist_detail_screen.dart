import 'dart:io';

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
import '../widgets/stage_background.dart';
import '../widgets/stretch_scroll.dart';
import 'album_detail_screen.dart';

/// An artist page: a big full-bleed artist photo with the name overlaid,
/// then play/shuffle, an albums rail, and the songs.
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
    final artistAlbums = ref.watch(artistAlbumsProvider(artist)).valueOrNull;
    final albums = artistAlbums?.own ?? const <AlbumRef>[];
    final features = artistAlbums?.features ?? const <AlbumRef>[];
    final resolver = ref.watch(artistImageResolverProvider).valueOrNull;
    final photoPath = resolver?.localPath(artist);
    final playingId = ref.watch(nowPlayingProvider.select((s) => s?.id));
    final isPlaying =
        ref.watch(playerStateStreamProvider).valueOrNull?.playing ?? false;
    final bottomPad = hasPersistentChrome(context)
        ? LumenTokens.bottomSafePad
        : 40.0;

    // Custom scaffold (not StageScaffold) so the hero photo bleeds full to the
    // very top of the screen — no app-bar row / safe-area gap above it — with
    // the back button floated over the image.
    return StageBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Material(
          type: MaterialType.transparency,
          child: Stack(
            children: [
              Positioned.fill(
                child: songsAsync.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
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
                    final meta =
                        '${songs.length} song${songs.length == 1 ? '' : 's'}'
                        '${albums.isEmpty ? '' : ' · ${albums.length} album${albums.length == 1 ? '' : 's'}'}';

                    return ScrollConfiguration(
                      behavior: const StretchScrollBehavior(),
                      child: ListView(
                        padding: EdgeInsets.only(bottom: bottomPad),
                        children: [
                          // ── Full-bleed photo hero with the name overlaid ──
                          _ArtistHero(
                            name: artist,
                            photoPath: photoPath,
                            meta: meta,
                          ),

                          // ── Play / shuffle ──
                          Padding(
                            padding: const EdgeInsets.fromLTRB(
                              LumenTokens.pagePad,
                              16,
                              LumenTokens.pagePad,
                              4,
                            ),
                            child: Row(
                              children: [
                                GlassButton(
                                  label: 'Play',
                                  icon: Icons.play_arrow_rounded,
                                  primary: true,
                                  onPressed: () =>
                                      _play(context, ref, songs, 0),
                                ),
                                const SizedBox(width: 12),
                                GlassIconButton(
                                  icon: Icons.shuffle_rounded,
                                  size: 52,
                                  iconSize: 22,
                                  onTap: () => _play(
                                    context,
                                    ref,
                                    [...songs]..shuffle(),
                                    0,
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // ── Albums (this artist leads) ──
                          if (albums.isNotEmpty) ...[
                            const _SectionLabel('Albums'),
                            _AlbumRail(albums: albums),
                            const SizedBox(height: 8),
                          ],

                          // ── Featured On (albums they only guest on) ──
                          if (features.isNotEmpty) ...[
                            const _SectionLabel('Featured On'),
                            _AlbumRail(albums: features),
                            const SizedBox(height: 8),
                          ],

                          // ── Songs ──
                          const _SectionLabel('Songs'),
                          for (var i = 0; i < songs.length; i++)
                            SongTile(
                              song: songs[i],
                              isPlaying: playingId == songs[i].id,
                              linkEntities: false,
                              onTap: () {
                                if (playingId == songs[i].id && isPlaying) {
                                  PlayerExpansionScope.maybeRead(
                                    context,
                                  )?.expand();
                                } else {
                                  _play(context, ref, songs, i);
                                }
                              },
                              onLongPress: () =>
                                  SongActionsSheet.show(context, songs[i]),
                              onMore: () =>
                                  SongActionsSheet.show(context, songs[i]),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              if (Navigator.of(context).canPop())
                Positioned(
                  top: MediaQuery.paddingOf(context).top + 8,
                  left: 8,
                  child: GlassIconButton(
                    icon: Icons.arrow_back_ios_new_rounded,
                    iconSize: 17,
                    onTap: () => Navigator.of(context).maybePop(),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ArtistHero extends StatelessWidget {
  const _ArtistHero({
    required this.name,
    required this.photoPath,
    required this.meta,
  });

  final String name;
  final String? photoPath;
  final String meta;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 360,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Photo (cover-fit) or a deterministic gradient fallback.
          if (photoPath != null)
            AnimatedAppear(
              child: Image.file(
                File(photoPath!),
                fit: BoxFit.cover,
                alignment: Alignment.topCenter,
                errorBuilder: (_, _, _) => _fallback(),
              ),
            )
          else
            _fallback(),
          // Bottom scrim so the name + meta read against any photo.
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.2),
                  Colors.black.withValues(alpha: 0.8),
                ],
                stops: [0.25, 0.6, 1.0],
              ),
            ),
          ),
          // Name + meta, bottom-left.
          Positioned(
            left: LumenTokens.pagePad,
            right: LumenTokens.pagePad,
            bottom: 16,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -1.2,
                    height: 1.02,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  meta,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.white.withValues(alpha: 0.75),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _fallback() => const DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [LumenTokens.orbDeep, LumenTokens.accent],
      ),
    ),
  );
}

/// A horizontal rail of album covers — shared by the "Albums" and
/// "Featured On" sections.
class _AlbumRail extends StatelessWidget {
  const _AlbumRail({required this.albums});

  final List<AlbumRef> albums;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 184,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: LumenTokens.pagePad),
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
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        LumenTokens.pagePad,
        18,
        LumenTokens.pagePad,
        10,
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.5,
        ),
      ),
    );
  }
}
