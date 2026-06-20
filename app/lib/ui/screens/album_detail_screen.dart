import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database/app_database.dart';
import '../../features/ai_dj/providers.dart';
import '../../features/library/detail_providers.dart';
import '../../features/nav/content_navigator_scope.dart';
import '../../features/player/now_playing_controller.dart';
import '../../features/player/player_expansion_controller.dart';
import '../../features/player/providers.dart';
import '../motion/animated_appear.dart';
import '../theme/app_theme.dart';
import '../widgets/album_art.dart';
import '../widgets/glass_kit.dart';
import '../widgets/song_actions.dart';
import '../widgets/song_tile.dart';
import 'entity_nav.dart';

/// An album's tracklist, with cover, tappable artist, and play/shuffle.
class AlbumDetailScreen extends ConsumerWidget {
  const AlbumDetailScreen({super.key, required this.album});

  final String album;

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

  String _formatDuration(int totalMs) {
    if (totalMs <= 0) return '';
    final totalMin = totalMs ~/ 60000;
    final hours = totalMin ~/ 60;
    final minutes = totalMin % 60;
    if (hours == 0) return '$minutes min';
    return '$hours hr $minutes min';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final songsAsync = ref.watch(songsByAlbumProvider(album));
    final playingId = ref.watch(nowPlayingProvider.select((s) => s?.id));
    final isPlaying =
        ref.watch(playerStateStreamProvider).valueOrNull?.playing ?? false;
    // Reserve room for the persistent nav + mini player only when that chrome
    // is actually overlaying us (mobile inner Navigator), not on desktop.
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
                'No songs on this album',
                style: TextStyle(color: LumenTokens.fgDimOf(context)),
              ),
            );
          }
          final cover = songs.firstWhere(
            (s) => s.localArtworkPath != null,
            orElse: () => songs.first,
          );
          final artist = cover.artist ?? '';
          final totalMs = songs.fold<int>(0, (s, r) => s + (r.durationMs ?? 0));
          final meta = [
            '${songs.length} song${songs.length == 1 ? '' : 's'}',
            if (totalMs > 0) _formatDuration(totalMs),
          ].join(' · ');

          return ListView(
            padding: EdgeInsets.only(bottom: bottomPad),
            children: [
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
                        artworkPath: cover.localArtworkPath,
                        seed: 'al_${cover.id}',
                        size: 220,
                        radius: LumenTokens.rSm,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      displayAlbumName(album),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.6,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 6),
                    if (artist.isNotEmpty)
                      Pressable(
                        onTap: () => openArtist(context, artist),
                        child: Text(
                          artist,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: LumenTokens.accent,
                          ),
                        ),
                      ),
                    const SizedBox(height: 4),
                    Text(
                      meta,
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
              const SizedBox(height: 12),
              for (var i = 0; i < songs.length; i++)
                SongTile(
                  song: songs[i],
                  isPlaying: playingId == songs[i].id,
                  showArt: false,
                  linkEntities: false,
                  onTap: () {
                    // Tapping the track that's already playing opens the
                    // player instead of restarting it from the top.
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
