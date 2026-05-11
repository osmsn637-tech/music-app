import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../../features/ai_dj/providers.dart';
import '../../features/player/now_playing_controller.dart';
import '../../features/player/providers.dart';
import '../screens/player_screen.dart';
import '../theme/app_theme.dart';
import 'album_art.dart';
import 'bloom_background.dart';

/// Hero tag shared between the mini-player artwork and the full player's
/// big album art. Tying it to the song id means the morph animation plays
/// cleanly when navigating between the two surfaces.
String miniPlayerArtHeroTag(String songId) => 'now-playing-art-$songId';

/// Shared route used everywhere the player is pushed (mini-player tap,
/// library, search, playlist, home, AI DJ). Two important properties:
///
///   - `opaque: false` keeps the underlying page (home shell, library,
///     etc.) rendered behind the player. So when the user drags the
///     player down to dismiss it, they SEE the page they came from
///     materialize underneath, not a black void.
///   - Fade-only transition. The Hero on the album art handles the
///     visible "mini → big" morph; the rest of the player just fades
///     in/out so it doesn't race the artwork tween.
Route<T> openPlayerRoute<T>() {
  return PageRouteBuilder<T>(
    opaque: false,
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 360),
    reverseTransitionDuration: const Duration(milliseconds: 280),
    pageBuilder: (_, _, _) => const PlayerScreen(),
    transitionsBuilder: (context, animation, _, child) {
      return FadeTransition(
        opacity: CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        ),
        child: child,
      );
    },
  );
}

/// Persistent mini-player. Glass-strong; tap to expand into the full
/// player with a Hero morph on the artwork.
class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final song = ref.watch(nowPlayingProvider);
    if (song == null) return const SizedBox.shrink();

    final controller = ref.read(nowPlayingProvider.notifier);
    final state = ref.watch(playerStateStreamProvider);

    final isPlaying = state.valueOrNull?.playing ?? false;
    final processing = state.valueOrNull?.processingState;

    // Resolve "what's next" from whichever queue owns the playhead:
    // AI DJ takes priority when active; otherwise fall back to the
    // generic library/artist queue managed by NowPlayingController.
    final djQueue = ref.watch(aiDjQueueControllerProvider);
    final djActive = djQueue.isActive;
    final djHasNext =
        djActive && djQueue.currentIndex + 1 < djQueue.queue.length;
    final genericHasNext = controller.hasNext;
    final hasNext = djActive ? djHasNext : genericHasNext;

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
      child: GestureDetector(
        onTap: () => _openPlayer(context),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: DecoratedBox(
            // Opaque black base so the mini-player is never see-through —
            // the bloom blobs / artwork blur composite ON TOP of this.
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
            ),
            child: Stack(
              children: [
                // Animated bloom background — same multi-blob system the
                // full player uses, scaled into the mini's footprint. The
                // colors flow with the current song's artwork palette.
                Positioned.fill(
                  child: RepaintBoundary(
                    child: BloomBackground(song: song, darkenStrength: 0.6),
                  ),
                ),
                Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
                child: Row(
                  children: [
                    Hero(
                      tag: miniPlayerArtHeroTag(song.id),
                      flightShuttleBuilder: _artHeroFlight,
                      child: AlbumArt(
                        artworkPath: song.localArtworkPath,
                        seed: song.id,
                        size: 56,
                        radius: 12,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            song.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.2,
                            ),
                          ),
                          if (song.artist != null)
                            Text(
                              song.artist!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                color: LumenTokens.fgDim,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 4),
                    _MiniGlyph(
                      icon: processing == ProcessingState.loading
                          ? Icons.hourglass_top
                          : isPlaying
                              ? Icons.pause
                              : Icons.play_arrow,
                      onTap: () async {
                        if (isPlaying) {
                          await controller.pause();
                        } else {
                          await controller.resume();
                        }
                      },
                    ),
                    _MiniGlyph(
                      icon: Icons.skip_next,
                      onTap: hasNext
                          ? () {
                              if (djActive) {
                                ref
                                    .read(aiDjQueueControllerProvider.notifier)
                                    .skip();
                              } else {
                                controller.next();
                              }
                            }
                          : null,
                    ),
                  ],
                ),
              ),
              // Slim progress strip kept; very thin so it reads as a hint
              // rather than a competing element.
              const _MiniProgress(),
              // Drag-handle pill at the very bottom — same as the screenshot.
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 6),
                child: Container(
                  width: 64,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ],
          ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static void _openPlayer(BuildContext context) {
    Navigator.of(context).push(openPlayerRoute());
  }

  /// Custom shuttle so the artwork doesn't get squashed mid-flight when
  /// the source/target sizes differ a lot. Lerps corner radius from the
  /// mini's 12px to the full player's 22px so corners don't snap at the
  /// end. Reads the song from whichever Hero we're flying away from.
  static Widget _artHeroFlight(
    BuildContext flightContext,
    Animation<double> animation,
    HeroFlightDirection flightDirection,
    BuildContext fromContext,
    BuildContext toContext,
  ) {
    final from = (fromContext.widget as Hero).child;
    final albumArt = _findAlbumArt(from);
    return AnimatedBuilder(
      animation: animation,
      builder: (_, __) {
        final t = flightDirection == HeroFlightDirection.push
            ? animation.value
            : 1 - animation.value;
        final r = 12.0 + (22.0 - 12.0) * t;
        return AspectRatio(
          aspectRatio: 1,
          child: albumArt == null
              ? const SizedBox.shrink()
              : AlbumArt(
                  artworkPath: albumArt.artworkPath,
                  seed: albumArt.seed,
                  size: double.infinity,
                  radius: r,
                ),
        );
      },
    );
  }

  /// Walks the from-Hero's child looking for an [AlbumArt] so the shuttle
  /// can rebuild it at the interpolated radius. The Hero child can be
  /// either the bare AlbumArt (mini side) or wrapped in another widget.
  static AlbumArt? _findAlbumArt(Widget w) {
    if (w is AlbumArt) return w;
    if (w is SingleChildRenderObjectWidget && w.child != null) {
      return _findAlbumArt(w.child!);
    }
    return null;
  }
}

class _MiniProgress extends ConsumerWidget {
  const _MiniProgress();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final position =
        ref.watch(playerPositionProvider).valueOrNull ?? Duration.zero;
    final duration =
        ref.watch(playerDurationProvider).valueOrNull ?? Duration.zero;
    final progress = duration.inMilliseconds <= 0
        ? 0.0
        : (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(1),
        child: LinearProgressIndicator(
          value: progress,
          minHeight: 2,
          backgroundColor: Colors.white.withValues(alpha: 0.12),
          valueColor: AlwaysStoppedAnimation(
            Colors.white.withValues(alpha: 0.55),
          ),
        ),
      ),
    );
  }
}

class _MiniGlyph extends StatelessWidget {
  const _MiniGlyph({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(
            icon,
            size: 28,
            color: Colors.white.withValues(alpha: disabled ? 0.35 : 0.95),
          ),
        ),
      ),
    );
  }
}
