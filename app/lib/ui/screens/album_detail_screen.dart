import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database/app_database.dart';
import '../../features/ai_dj/providers.dart';
import '../../features/library/album_colors_provider.dart';
import '../../features/library/detail_providers.dart';
import '../../features/nav/content_navigator_scope.dart';
import '../../features/player/now_playing_controller.dart';
import '../../features/player/player_expansion_controller.dart';
import '../../features/player/providers.dart';
import '../motion/animated_appear.dart';
import '../theme/app_theme.dart';
import '../widgets/album_art.dart';
import '../widgets/explicit_badge.dart';
import '../widgets/glass_kit.dart';
import '../widgets/song_actions.dart';
import '../widgets/tempo_sheet.dart';
import 'entity_nav.dart';

/// An album's tracklist. A cover-tinted gradient hero (big cover + bold title
/// + a prominent Play) over a numbered tracklist.
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

  static String _fmtTotal(int totalMs) {
    if (totalMs <= 0) return '';
    final totalMin = totalMs ~/ 60000;
    final hours = totalMin ~/ 60;
    final minutes = totalMin % 60;
    return hours == 0 ? '$minutes min' : '$hours hr $minutes min';
  }

  static String _fmtTrack(int? ms) {
    if (ms == null || ms <= 0) return '';
    final s = ms ~/ 1000;
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final songsAsync = ref.watch(songsByAlbumProvider(album));
    final playingId = ref.watch(nowPlayingProvider.select((s) => s?.id));
    final isPlaying =
        ref.watch(playerStateStreamProvider).valueOrNull?.playing ?? false;
    final bottomPad = hasPersistentChrome(context)
        ? LumenTokens.bottomSafePad
        : 40.0;

    return StageScaffold(
      bleedTop: true,
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
          final palette = ref
              .watch(albumColorsProvider(cover.localArtworkPath))
              .valueOrNull;
          final tint = (palette != null && palette.isNotEmpty)
              ? palette.first
              : LumenTokens.accent;

          return Stack(
            children: [
              CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: _Hero(
                      album: album,
                      cover: cover,
                      artist: artist,
                      meta: [
                        '${songs.length} song${songs.length == 1 ? '' : 's'}',
                        if (totalMs > 0) _fmtTotal(totalMs),
                      ].join(' · '),
                      tint: tint,
                      onPlay: () => _play(context, ref, songs, 0),
                      onShuffle: () =>
                          _play(context, ref, [...songs]..shuffle(), 0),
                      onArtist: artist.isEmpty
                          ? null
                          : () => openArtist(context, artist),
                    ),
                  ),
                  SliverList(
                    delegate: SliverChildBuilderDelegate((context, i) {
                      final s = songs[i];
                      final current = playingId == s.id;
                      return _TrackRow(
                        index: i + 1,
                        song: s,
                        current: current,
                        isPlaying: isPlaying,
                        tint: tint,
                        duration: _fmtTrack(s.durationMs),
                        onTap: () {
                          if (current && isPlaying) {
                            PlayerExpansionScope.maybeRead(context)?.expand();
                          } else {
                            _play(context, ref, songs, i);
                          }
                        },
                        onMore: () => SongActionsSheet.show(context, s),
                      );
                    }, childCount: songs.length),
                  ),
                  SliverToBoxAdapter(child: SizedBox(height: bottomPad)),
                ],
              ),
              const Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: IgnorePointer(child: _TopFrostEdge()),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({
    required this.album,
    required this.cover,
    required this.artist,
    required this.meta,
    required this.tint,
    required this.onPlay,
    required this.onShuffle,
    required this.onArtist,
  });

  final String album;
  final SongRow cover;
  final String artist;
  final String meta;
  final Color tint;
  final VoidCallback onPlay;
  final VoidCallback onShuffle;
  final VoidCallback? onArtist;

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;
    return Container(
      // Cover-derived wash fading into the stage background.
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [tint.withValues(alpha: 0.5), Colors.transparent],
        ),
      ),
      padding: EdgeInsets.fromLTRB(
        LumenTokens.pagePad,
        // Clear the floating back button — the hero now bleeds up behind
        // the status bar, so the cover sits below the overlaid top bar.
        topInset + 56,
        LumenTokens.pagePad,
        10,
      ),
      child: Column(
        children: [
          AnimatedAppear(
            scale: true,
            offsetY: 0,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(LumenTokens.rLg),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.45),
                    blurRadius: 40,
                    offset: const Offset(0, 18),
                  ),
                ],
              ),
              child: AlbumArt(
                artworkPath: cover.localArtworkPath,
                seed: 'al_${cover.id}',
                size: 208,
                radius: LumenTokens.rLg,
              ),
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            'ALBUM',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.6,
              color: LumenTokens.accent,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            displayAlbumName(album),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.7,
              height: 1.08,
            ),
          ),
          const SizedBox(height: 8),
          if (artist.isNotEmpty)
            Pressable(
              onTap: onArtist ?? () {},
              child: Text(
                artist,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 15,
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
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              GlassButton(
                label: 'Play',
                icon: Icons.play_arrow_rounded,
                primary: true,
                onPressed: onPlay,
              ),
              const SizedBox(width: 12),
              GlassIconButton(
                icon: Icons.shuffle_rounded,
                size: 52,
                iconSize: 22,
                onTap: onShuffle,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A numbered track row: index (or equalizer when playing) · title/artist ·
/// duration · more.
class _TrackRow extends StatelessWidget {
  const _TrackRow({
    required this.index,
    required this.song,
    required this.current,
    required this.isPlaying,
    required this.tint,
    required this.duration,
    required this.onTap,
    required this.onMore,
  });

  final int index;
  final SongRow song;
  final bool current;
  final bool isPlaying;
  final Color tint;
  final String duration;
  final VoidCallback onTap;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final titleColor = current ? LumenTokens.accent : LumenTokens.fg(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onLongPress: onMore,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: LumenTokens.pagePad,
          vertical: 9,
        ),
        child: Row(
          children: [
            SizedBox(
              width: 26,
              child: current
                  ? const Icon(
                      Icons.graphic_eq_rounded,
                      size: 17,
                      color: LumenTokens.accent,
                    )
                  : Text(
                      '$index',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: LumenTokens.fgDim2Of(context),
                        fontFeatures: LumenTokens.tnum,
                      ),
                    ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          song.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: titleColor,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      const ExplicitBadge(),
                    ],
                  ),
                  TempoBadge(song: song),
                ],
              ),
            ),
            if (duration.isNotEmpty) ...[
              const SizedBox(width: 10),
              Text(
                duration,
                style: TextStyle(
                  fontSize: 12.5,
                  color: LumenTokens.fgDim2Of(context),
                  fontFeatures: LumenTokens.tnum,
                ),
              ),
            ],
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onMore,
              child: Padding(
                padding: const EdgeInsets.only(left: 6),
                child: Icon(
                  Icons.more_horiz_rounded,
                  size: 20,
                  color: LumenTokens.fgDim2Of(context),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopFrostEdge extends StatelessWidget {
  const _TopFrostEdge();

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.paddingOf(context).top + 48;
    return SizedBox(
      height: h,
      width: double.infinity,
      child: ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (r) => const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.black, Colors.transparent],
          stops: [0.55, 1.0],
        ).createShader(r),
        child: ClipRect(
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 7, sigmaY: 7),
            child: SizedBox(height: h, width: double.infinity),
          ),
        ),
      ),
    );
  }
}
