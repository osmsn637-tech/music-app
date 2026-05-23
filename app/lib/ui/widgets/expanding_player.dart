import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/album_colors.dart';
import '../../data/database/app_database.dart';
import '../../features/ai_dj/ai_dj_queue_controller.dart';
import '../../features/ai_dj/ai_dj_service.dart';
import '../../features/ai_dj/providers.dart';
import '../../features/library/album_colors_provider.dart';
import '../../features/library/library_actions.dart';
import '../../features/player/now_playing_controller.dart';
import '../../features/player/player_expansion_controller.dart';
import '../../features/player/player_service.dart';
import '../../features/player/providers.dart';
import '../screens/lyrics_screen.dart';
import '../theme/app_theme.dart';
import 'album_art.dart';
import 'bloom_background.dart';
import 'song_actions.dart';

/// Soft white that matches the mini-player's resolved icon colour. The
/// transport glyphs lerp from this (at e=0) to the album-tinted accent
/// (at e=1), so by the time the player is full the icons are coloured
/// and by the time it shrinks back to mini they're white again.
const Color _miniGlyphWhite = Color(0xF2FFFFFF);

/// Stacked mini-player + full-player as a single widget. The expansion
/// value (0 = mini, 1 = full) is owned by [PlayerExpansionScope] above
/// it in the tree; this widget reads it via `PlayerExpansionScope.of`.
///
/// Layout strategy:
///   - The card (a rounded-rect with the bloom inside) lerps between a
///     pinned-to-the-bottom mini rect and a fullscreen rect.
///   - The three shared elements (artwork, play, next) are absolutely
///     positioned at screen-space rects lerped between their mini and
///     full positions, so they appear to fly between the two layouts.
///   - Two chrome layers cross-fade: a mini-only layer (slim title,
///     progress strip, drag pill) and a full-only layer (top chrome,
///     prev button, big title text). Each one is `IgnorePointer`-ed
///     and `Opacity`-faded based on `e`.
///   - A full-screen translucent GestureDetector intercepts tap-to-
///     expand and drag-to-collapse/expand. It's `translucent` so the
///     InkWells on the transport buttons (which sit on top of it in
///     z-order) still receive their own taps.
class ExpandingPlayer extends ConsumerWidget {
  const ExpandingPlayer({
    super.key,
    required this.tabBarHeight,
  });

  /// Height of the home shell's tab bar, in logical pixels. The
  /// mini-player sits flush above it; we need this to compute the
  /// mini rect's top edge.
  final double tabBarHeight;

  /// Padding above the mini-player's bottom edge — matches the
  /// previous mini layout's `EdgeInsets.fromLTRB(8, 0, 8, 6)`.
  static const double _miniBottomGap = 6;

  /// Mini-player visible height. Matches the previous `_MiniPlayer`'s
  /// laid-out height (cover + progress strip + drag pill).
  static const double _miniHeight = 86;

  /// Horizontal padding on the mini-player.
  static const double _miniHPad = 8;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // This outer build runs only when one of the watched providers
    // (song / player state / dj queue / palette) changes. The
    // expansion controller is read NON-subscribingly — its ticks no
    // longer rebuild this tree. The morphing layout lives inside
    // [_PlayerMorph], which is the only widget that listens to the
    // controller (via AnimatedBuilder) and so the only one that
    // rebuilds 60 Hz during expand / collapse / drag.
    final song = ref.watch(nowPlayingProvider);
    if (song == null) return const SizedBox.shrink();

    final expansion = PlayerExpansionScope.read(context);

    final state = ref.watch(playerStateStreamProvider);
    final isPlaying = state.valueOrNull?.playing ?? false;
    final processing = state.valueOrNull?.processingState;
    final loading = processing == PlayerProcessingState.loading;

    final djQueue = ref.watch(aiDjQueueControllerProvider);
    final djActive = djQueue.isActive;
    final nowController = ref.read(nowPlayingProvider.notifier);
    final hasPrev = djActive
        ? djQueue.currentIndex > 0
        : nowController.hasPrev;
    final hasNext = djActive
        ? djQueue.currentIndex + 1 < djQueue.queue.length
        : nowController.hasNext;

    // Accent colour derived from the cached album palette. Falls back to
    // a soft pink while extraction is resolving on a first cold start.
    final palette = ref
        .watch(albumColorsProvider(song.localArtworkPath))
        .valueOrNull;
    final accent = palette == null
        ? const Color(0xFFFFA08F)
        : AlbumColors.accentFromPalette(palette,
            fallback: const Color(0xFFFFA08F));

    // ----- Gesture / callback handlers (closed over current state) ------------
    void onPlayPause() async {
      if (isPlaying) {
        await nowController.pause();
      } else {
        await nowController.resume();
      }
    }

    void onNext() {
      if (djActive) {
        ref.read(aiDjQueueControllerProvider.notifier).skip();
      } else {
        nowController.next();
      }
    }

    void onPrev() {
      if (djActive) {
        ref
            .read(aiDjQueueControllerProvider.notifier)
            .playAt(djQueue.currentIndex - 1);
      } else {
        nowController.previous();
      }
    }

    return _PlayerMorph(
      song: song,
      expansion: expansion,
      tabBarHeight: tabBarHeight,
      miniBottomGap: _miniBottomGap,
      miniHeight: _miniHeight,
      miniHPad: _miniHPad,
      isPlaying: isPlaying,
      loading: loading,
      hasPrev: hasPrev,
      hasNext: hasNext,
      accent: accent,
      isFavorite: song.isFavorite == 1,
      onPlayPause: onPlayPause,
      onNext: hasNext ? onNext : null,
      onPrev: hasPrev ? onPrev : null,
      onLyrics: () => _openLyrics(context),
      onFavorite: () =>
          ref.read(libraryActionsProvider).toggleFavorite(song),
      onMore: () => SongActionsSheet.show(context, song),
      onQueue: () => _openQueue(context, ref, djQueue),
    );
  }

  /// Soft white that matches the mini-player's resolved icon colour.
  /// Kept as a static constant so [_PlayerMorph] (separate class) can
  /// share the value without each instance re-allocating a Color.
  static const Color miniGlyphWhite = _miniGlyphWhite;

  /// Push the lyrics view with a fade. Opaque — the lyrics page paints
  /// its own black gradient bg, so once the transition completes
  /// Flutter can STOP rendering the underlying player + shell +
  /// StageBackground every frame. Was the dominant per-frame cost
  /// while the lyrics page was open (every shell tab body + animated
  /// stage blobs + the player's bloom kept painting underneath an
  /// invisible non-opaque route).
  void _openLyrics(BuildContext context) {
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: true,
        transitionDuration: const Duration(milliseconds: 320),
        reverseTransitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (_, _, _) => const LyricsScreen(),
        transitionsBuilder: (_, anim, _, child) => FadeTransition(
          opacity:
              CurvedAnimation(parent: anim, curve: Curves.easeOutCubic),
          child: child,
        ),
      ),
    );
  }

  /// Bottom sheet with the AI DJ queue when one is active. Falls back
  /// to a "Playing from library" message when the generic queue owns
  /// the playhead (the now-playing controller's queue isn't exposed,
  /// so we surface the AI DJ one which is).
  void _openQueue(
    BuildContext context,
    WidgetRef ref,
    AiDjQueueState djQueue,
  ) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF14161A),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _QueueSheet(djQueue: djQueue),
    );
  }
}

/// Owns the per-tick layout work. Listens to the expansion controller
/// via an [AnimatedBuilder] — the outer [ExpandingPlayer] no longer
/// subscribes to the controller, so a frame-by-frame expand/collapse
/// rebuilds ONLY this widget's builder closure, not the four
/// provider-watching `ref.watch` calls in the outer build.
///
/// Everything that depends on `e` (rects, radii, colours) is computed
/// inside the builder. Everything that doesn't (song, accent, callbacks,
/// favorite state) is plumbed in via constructor params.
class _PlayerMorph extends StatelessWidget {
  const _PlayerMorph({
    required this.song,
    required this.expansion,
    required this.tabBarHeight,
    required this.miniBottomGap,
    required this.miniHeight,
    required this.miniHPad,
    required this.isPlaying,
    required this.loading,
    required this.hasPrev,
    required this.hasNext,
    required this.accent,
    required this.isFavorite,
    required this.onPlayPause,
    required this.onNext,
    required this.onPrev,
    required this.onLyrics,
    required this.onFavorite,
    required this.onMore,
    required this.onQueue,
  });

  final SongRow song;
  final PlayerExpansionController expansion;
  final double tabBarHeight;
  final double miniBottomGap;
  final double miniHeight;
  final double miniHPad;
  final bool isPlaying;
  final bool loading;
  final bool hasPrev;
  final bool hasNext;
  final Color accent;
  final bool isFavorite;
  final VoidCallback onPlayPause;
  final VoidCallback? onNext;
  final VoidCallback? onPrev;
  final VoidCallback onLyrics;
  final VoidCallback onFavorite;
  final VoidCallback onMore;
  final VoidCallback onQueue;

  @override
  Widget build(BuildContext context) {
    // MediaQuery sizeOf / paddingOf depend on only the relevant slices
    // of the inherited MediaQueryData, so we don't rebuild on unrelated
    // MQ changes (text scale, etc.).
    final size = MediaQuery.sizeOf(context);
    final mqPad = MediaQuery.paddingOf(context);
    final topInset = mqPad.top;
    final bottomInset = mqPad.bottom;

    // Layout values that depend ONLY on the viewport, not on `e`.
    // Computed once per outer build (which runs only on viewport /
    // provider changes), captured by the AnimatedBuilder closure.
    final miniTop =
        size.height - bottomInset - tabBarHeight - miniBottomGap - miniHeight;
    final miniRect = Rect.fromLTWH(
      miniHPad,
      miniTop,
      size.width - miniHPad * 2,
      miniHeight,
    );
    final fullRect = Offset.zero & size;
    final miniArtRect =
        Rect.fromLTWH(miniRect.left + 8, miniRect.top + 8, 56, 56);
    final fullArtSize = math.min(size.width - 100, 260.0);
    final fullArtTop = topInset + 86;
    final fullArtRect = Rect.fromLTWH(
      (size.width - fullArtSize) / 2,
      fullArtTop,
      fullArtSize,
      fullArtSize,
    );
    final transportRowY = size.height - bottomInset - 200;
    final miniNextRect = Rect.fromLTWH(
      miniRect.right - 8 - 48,
      miniRect.top + 8 + (56 - 48) / 2,
      48,
      48,
    );
    final miniPlayRect = Rect.fromLTWH(
      miniRect.right - 8 - 48 - 48,
      miniRect.top + 8 + (56 - 48) / 2,
      48,
      48,
    );
    final fullPlayRect =
        Rect.fromLTWH((size.width - 74) / 2, transportRowY, 74, 74);
    final fullNextRect =
        Rect.fromLTWH(size.width / 2 + 60, transportRowY + 6, 62, 62);

    return AnimatedBuilder(
      animation: expansion.animation,
      builder: (context, _) {
        final e = expansion.value;
        final atRest = e < 0.03;

        final cardRect = Rect.lerp(miniRect, fullRect, e)!;
        final cardRadius = ui.lerpDouble(22, 0, e)!;
        final artRect = Rect.lerp(miniArtRect, fullArtRect, e)!;
        final artRadius = ui.lerpDouble(12, LumenTokens.rLg, e)!;
        final playSize = ui.lerpDouble(48, 74, e)!;
        final nextSize = ui.lerpDouble(48, 62, e)!;
        final playRect = Rect.lerp(miniPlayRect, fullPlayRect, e)!;
        final nextRect = Rect.lerp(miniNextRect, fullNextRect, e)!;
        final glyphColor =
            Color.lerp(ExpandingPlayer.miniGlyphWhite, accent, e)!;

        return Stack(
            fit: StackFit.expand,
            clipBehavior: Clip.none,
            children: [
              // 1. Backdrop scrim.
              if (e > 0.0)
                Positioned.fill(
                  child: IgnorePointer(
                    child: Opacity(
                      opacity: (e * 1.5).clamp(0.0, 0.6),
                      child: const ColoredBox(color: Colors.black),
                    ),
                  ),
                ),

              // 2. The card. Tap-to-expand (when at rest) only — the
              //    drag-to-collapse handler lives on the overlay layer
                //    at the top of the Stack so it can intercept
              //    vertical drags from anywhere on the player,
              //    including the album cover, title text, and any
              //    chrome that would otherwise absorb hits.
              Positioned.fromRect(
                rect: cardRect,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: atRest ? expansion.expand : null,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(cardRadius),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(cardRadius),
                      child: BloomBackground(
                        song: song,
                        darkenStrength: 0.55,
                        // Bloom freezes audio-reactive work (FFT ticker
                        // + kick animations) when the player is in mini
                        // form; bg still shows the album palette, just
                        // static. Saves ~20 Hz FFT reads + 3
                        // AnimatedBuilders while the player isn't
                        // expanded.
                        audioReactive: e >= 0.2,
                      ),
                    ),
                  ),
                ),
              ),

              // 4. Mini-only chrome.
              if (e < 0.7)
                _MiniChrome(
                  song: song,
                  miniRect: miniRect,
                  opacity: ((0.7 - e) / 0.7).clamp(0.0, 1.0),
                  accent: accent,
                ),

              // 5. Full-only chrome.
              if (e > 0.3)
                _FullChrome(
                  song: song,
                  topInset: topInset,
                  bottomInset: bottomInset,
                  transportRowY: transportRowY,
                  fullArtRect: fullArtRect,
                  hasPrev: hasPrev,
                  accent: accent,
                  opacity: ((e - 0.3) / 0.7).clamp(0.0, 1.0),
                  onPrev: onPrev,
                  onDismiss: expansion.collapse,
                  onFavorite: onFavorite,
                  isFavorite: isFavorite,
                  onLyrics: onLyrics,
                  onQueue: onQueue,
                  onMore: onMore,
                ),

              // 6. Shared morphing artwork. Wrapped in IgnorePointer so
              //    the RenderImage doesn't absorb pointer events without
              //    handling them — without this, taps on the cover in
              //    mini form go nowhere (album art absorbs but has no
              //    gesture handler), and the drag overlay below can't
              //    receive its hits either. With IgnorePointer, hits on
              //    the cover propagate down through the Stack until they
              //    reach the card's tap handler (mini → expand) or the
              //    drag overlay (full → collapse on swipe).
              Positioned.fromRect(
                rect: artRect,
                child: IgnorePointer(
                  child: AlbumArt(
                    artworkPath: song.localArtworkPath,
                    seed: song.id,
                    size: artRect.width,
                    radius: artRadius,
                  ),
                ),
              ),

              // 7. Shared morphing play / pause.
              Positioned.fromRect(
                rect: playRect,
                child: _GlyphButton(
                  icon: loading
                      ? Icons.hourglass_top_rounded
                      : isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                  size: playSize,
                  color: glyphColor,
                  onTap: onPlayPause,
                ),
              ),

              // 8. Shared morphing next.
              Positioned.fromRect(
                rect: nextRect,
                child: _GlyphButton(
                  icon: Icons.fast_forward_rounded,
                  size: nextSize,
                  color: hasNext
                      ? glyphColor
                      : Colors.white.withValues(alpha: 0.20),
                  onTap: onNext,
                ),
              ),

              // 9. Drag-to-collapse overlay. Sits at the top of the
              //    z-order with HitTestBehavior.translucent and only
              //    vertical-drag handlers — no tap, no opaque hit. The
              //    translucent behavior lets the hit propagate down so
              //    InkWell buttons (play / next / favorite / etc.)
              //    still get their taps; the gesture arena routes any
              //    vertical motion exceeding slop to this overlay
              //    instead. Result: drag-down to collapse works from
              //    anywhere on the player — album cover, title text,
              //    chrome — without breaking button taps.
              Positioned.fromRect(
                rect: cardRect,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onVerticalDragUpdate: (d) => expansion.dragBy(d.delta.dy),
                  onVerticalDragEnd: (d) => expansion.endDrag(
                    velocity: d.velocity.pixelsPerSecond.dy,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Queue bottom sheet. Shows the AI DJ queue with the active row
/// highlighted; tapping a row jumps the DJ to that entry. Renders a
/// plain "playing from library" hint when the DJ is idle.
class _QueueSheet extends ConsumerWidget {
  const _QueueSheet({required this.djQueue});

  final AiDjQueueState djQueue;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = djQueue.queue;
    final active = djQueue.isActive && entries.isNotEmpty;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 14, 20, 8),
              child: Row(
                children: [
                  Icon(Icons.queue_music_rounded, color: Colors.white),
                  SizedBox(width: 10),
                  Text(
                    'Up next',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0x22FFFFFF)),
            if (!active)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 36,
                ),
                child: Text(
                  'Playing from your library. Use AI DJ for a curated queue.',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.65),
                    fontSize: 14,
                  ),
                ),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: entries.length,
                  itemBuilder: (_, i) {
                    final entry = entries[i];
                    final isCurrent = i == djQueue.currentIndex;
                    return _QueueRow(
                      entry: entry,
                      isCurrent: isCurrent,
                      onTap: () {
                        ref
                            .read(aiDjQueueControllerProvider.notifier)
                            .playAt(i);
                        Navigator.of(context).pop();
                      },
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _QueueRow extends StatelessWidget {
  const _QueueRow({
    required this.entry,
    required this.isCurrent,
    required this.onTap,
  });

  final AiDjQueueEntry entry;
  final bool isCurrent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final song = entry.song;
    return Material(
      color: isCurrent
          ? Colors.white.withValues(alpha: 0.06)
          : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: Row(
            children: [
              SizedBox(
                width: 44,
                height: 44,
                child: AlbumArt(
                  artworkPath: song.localArtworkPath,
                  seed: song.id,
                  size: 44,
                  radius: 8,
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
                      style: TextStyle(
                        color: Colors.white
                            .withValues(alpha: isCurrent ? 1.0 : 0.92),
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (song.artist != null)
                      Text(
                        song.artist!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.55),
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
              ),
              if (isCurrent)
                const Icon(
                  Icons.graphic_eq_rounded,
                  color: Colors.white,
                  size: 18,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GlyphButton extends StatelessWidget {
  const _GlyphButton({
    required this.icon,
    required this.size,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final double size;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    // Drop-shadow on the icon glyph removed — paying a `Shadow` per
    // transport button (play, next, prev) every frame during expansion
    // for an effect the bloom-darkened bg + bright glyph fill already
    // make unnecessary.
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Center(
          child: Icon(icon, size: size, color: color),
        ),
      ),
    );
  }
}

class _MiniChrome extends ConsumerWidget {
  const _MiniChrome({
    required this.song,
    required this.miniRect,
    required this.opacity,
    required this.accent,
  });

  final dynamic song; // SongRow — typed dynamic so we avoid the import.
  final Rect miniRect;
  final double opacity;
  final Color accent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Title + artist text. Sits between the mini cover and the play/next
    // glyphs. Width = mini width minus art (56) minus glyphs (48×2) minus
    // paddings (8 outer + 12 art gap + 4 trailing gap).
    final titleLeft = miniRect.left + 8 + 56 + 12;
    final titleRight = miniRect.right - 8 - 48 - 48 - 4;
    final titleTop = miniRect.top + 8 + 4;
    return IgnorePointer(
      ignoring: opacity < 0.05,
      child: Opacity(
        opacity: opacity,
        child: Stack(
          children: [
            // Title row.
            Positioned(
              left: titleLeft,
              right: math.max(0, MediaQuery.of(context).size.width -
                  titleRight),
              top: titleTop,
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
                      color: Colors.white,
                    ),
                  ),
                  if (song.artist != null)
                    Text(
                      song.artist!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.white.withValues(alpha: 0.65),
                      ),
                    ),
                ],
              ),
            ),
            // Slim progress strip.
            Positioned(
              left: miniRect.left + 12,
              right: MediaQuery.of(context).size.width -
                  miniRect.right + 12,
              top: miniRect.top + 8 + 56 + 6,
              child: const _SlimProgress(),
            ),
            // Drag pill at the bottom of the mini.
            Positioned(
              left: 0,
              right: 0,
              top: miniRect.bottom - 10,
              child: Center(
                child: Container(
                  width: 64,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(2),
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

class _SlimProgress extends ConsumerWidget {
  const _SlimProgress();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final position =
        ref.watch(playerPositionProvider).valueOrNull ?? Duration.zero;
    final duration =
        ref.watch(playerDurationProvider).valueOrNull ?? Duration.zero;
    final progress = duration.inMilliseconds <= 0
        ? 0.0
        : (position.inMilliseconds / duration.inMilliseconds)
            .clamp(0.0, 1.0);
    return ClipRRect(
      borderRadius: BorderRadius.circular(1),
      child: LinearProgressIndicator(
        value: progress,
        minHeight: 2,
        backgroundColor: Colors.white.withValues(alpha: 0.12),
        valueColor: AlwaysStoppedAnimation(
          Colors.white.withValues(alpha: 0.55),
        ),
      ),
    );
  }
}

class _FullChrome extends ConsumerWidget {
  const _FullChrome({
    required this.song,
    required this.topInset,
    required this.bottomInset,
    required this.transportRowY,
    required this.fullArtRect,
    required this.hasPrev,
    required this.accent,
    required this.opacity,
    required this.onPrev,
    required this.onDismiss,
    required this.onFavorite,
    required this.isFavorite,
    required this.onLyrics,
    required this.onQueue,
    required this.onMore,
  });

  final dynamic song;
  final double topInset;
  final double bottomInset;
  final double transportRowY;
  /// Final at-rest rect of the morphing artwork. The glass album card
  /// is positioned 18 px around it; the title + artist row sit below.
  final Rect fullArtRect;
  final bool hasPrev;
  final Color accent;
  final double opacity;
  final VoidCallback? onPrev;
  final VoidCallback onDismiss;
  final VoidCallback onFavorite;
  final bool isFavorite;
  final VoidCallback onLyrics;
  final VoidCallback onQueue;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final size = MediaQuery.of(context).size;

    // Album card geometry. The card hugs the art with 18 px padding on
    // three sides and extends below it for the FitTitle (≤ 30 px) +
    // gap + artist row (38 px) + bottom padding.
    const cardSidePad = 18.0;
    const artToTitleGap = 22.0;
    const titleHeight = 30.0;
    const titleToArtistGap = 12.0;
    const artistRowHeight = 38.0;
    const cardBottomPad = 18.0;
    final cardRect = Rect.fromLTRB(
      fullArtRect.left - cardSidePad,
      fullArtRect.top - cardSidePad,
      fullArtRect.right + cardSidePad,
      fullArtRect.bottom +
          artToTitleGap +
          titleHeight +
          titleToArtistGap +
          artistRowHeight +
          cardBottomPad,
    );
    final titleTop = fullArtRect.bottom + artToTitleGap;
    final artistRowTop = titleTop + titleHeight + titleToArtistGap;

    return IgnorePointer(
      ignoring: opacity < 0.05,
      child: Opacity(
        opacity: opacity,
        child: Stack(
          children: [
            // 1. Top chrome — chevron + eyebrow + more_horiz. Favorite
            //    moved into the album card per the Lumen handoff.
            Positioned(
              left: 0,
              right: 0,
              top: topInset + 8,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: Row(
                  children: [
                    _RoundIcon(
                      icon: Icons.keyboard_arrow_down,
                      onTap: onDismiss,
                    ),
                    Expanded(
                      child: Column(
                        children: [
                          Text(
                            song.album != null
                                ? 'PLAYING FROM ALBUM'
                                : 'PLAYING FROM YOUR LIBRARY',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                              color: Colors.white.withValues(alpha: 0.58),
                              shadows: const [
                                Shadow(
                                  color: Color.fromRGBO(0, 0, 0, 0.6),
                                  blurRadius: 6,
                                  offset: Offset(0, 1),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            song.album ?? song.artist ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                              shadows: [
                                Shadow(
                                  color: Color.fromRGBO(0, 0, 0, 0.6),
                                  blurRadius: 6,
                                  offset: Offset(0, 1),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    _RoundIcon(
                      icon: Icons.more_horiz_rounded,
                      onTap: onMore,
                    ),
                  ],
                ),
              ),
            ),

            // 2. Glass album card — sits behind the morphing artwork and
            //    extends below for the title + artist row. The art
            //    itself is rendered on top by the parent Stack's shared
            //    layer, so this is just the surrounding glass surface.
            Positioned.fromRect(
              rect: cardRect,
              child: const _GlassAlbumCard(),
            ),

            // 3. FitTitle — shrinks 30 → 18 to keep the title on one
            //    line within the card's horizontal extent.
            Positioned(
              left: fullArtRect.left,
              top: titleTop,
              width: fullArtRect.width,
              child: _FitTitle(text: song.title),
            ),

            // 4. Artist row — text + inline favorite + more_vert. The
            //    favorite and more buttons that used to live in the top
            //    chrome move here per the handoff layout.
            Positioned(
              left: fullArtRect.left,
              top: artistRowTop,
              width: fullArtRect.width,
              child: SizedBox(
                height: artistRowHeight,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        song.artist ?? 'Unknown artist',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.white.withValues(alpha: 0.72),
                        ),
                      ),
                    ),
                    _InlineIconButton(
                      icon: isFavorite
                          ? Icons.favorite
                          : Icons.favorite_border,
                      iconSize: 26,
                      color: isFavorite
                          ? const Color(0xFFFF5C7A)
                          : Colors.white.withValues(alpha: 0.76),
                      onTap: onFavorite,
                    ),
                    _InlineIconButton(
                      icon: Icons.more_vert_rounded,
                      iconSize: 24,
                      color: Colors.white.withValues(alpha: 0.58),
                      onTap: onMore,
                    ),
                  ],
                ),
              ),
            ),

            // 5. Big progress bar above the transport row.
            Positioned(
              left: 22,
              right: 22,
              top: transportRowY - 60,
              child: const _FullProgress(),
            ),

            // 6. Prev button — the shared layer owns play+next.
            Positioned(
              left: size.width / 2 - 122,
              top: transportRowY + 6,
              width: 62,
              height: 62,
              child: _GlyphButton(
                icon: Icons.fast_rewind_rounded,
                size: 62,
                color: hasPrev
                    ? accent
                    : Colors.white.withValues(alpha: 0.20),
                onTap: onPrev,
              ),
            ),

            // 7. Niche bar — Tune (placeholder, inactive until bass
            //    tweaks land) + Lyrics pill + Queue. Mirrors the Lumen
            //    handoff layout exactly.
            Positioned(
              left: 0,
              right: 0,
              bottom: bottomInset + 24,
              child: _NicheBar(
                accent: accent,
                onTune: () {},
                onLyrics: onLyrics,
                onQueue: onQueue,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The Lumen handoff's `AlbumCard` — translucent dark fill with a 1 px
/// white rim, a soft drop shadow, and a top-edge highlight gradient
/// that fakes an inset white shadow.
///
/// Previously wrapped in `BackdropFilter(σ=25)` for a live-blurred glass
/// look — that was a saveLayer + 25-sigma blur on a ~280×370 surface
/// every paint, the single most expensive widget on the full player.
/// The sibling round-icons and lyrics pill already dropped their
/// BackdropFilters for the same reason; the card now matches them with
/// a heavier-alpha tinted fill that reads the same against the bloom.
class _GlassAlbumCard extends StatelessWidget {
  const _GlassAlbumCard();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        // Bumped alpha 0.55 → 0.72 to compensate for the lost blur.
        color: const Color.fromRGBO(20, 20, 28, 0.72),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withValues(alpha: 0.10),
            Colors.transparent,
          ],
          stops: const [0.0, 0.25],
        ),
        boxShadow: const [
          BoxShadow(
            color: Color.fromRGBO(0, 0, 0, 0.55),
            blurRadius: 60,
            offset: Offset(0, 24),
          ),
        ],
      ),
    );
  }
}

/// Bare 38×38 InkWell wrapping a centred icon — used for the favorite
/// and more_vert buttons inside the album card's artist row. No glass
/// pill behind the icon; the buttons just sit in the card's content.
class _InlineIconButton extends StatelessWidget {
  const _InlineIconButton({
    required this.icon,
    required this.iconSize,
    required this.color,
    required this.onTap,
  });
  final IconData icon;
  final double iconSize;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: SizedBox(
          width: 38,
          height: 38,
          child: Icon(icon, size: iconSize, color: color),
        ),
      ),
    );
  }
}

/// Niche bar — Tune (inactive placeholder) | Lyrics pill | Queue. Tune
/// is a hook for the bass-tweaks panel from the Lumen design; it stays
/// inactive until that surface is wired up. The Lyrics pill takes the
/// flex space between the two glyphs.
class _NicheBar extends StatelessWidget {
  const _NicheBar({
    required this.accent,
    required this.onTune,
    required this.onLyrics,
    required this.onQueue,
  });

  final Color accent;
  final VoidCallback onTune;
  final VoidCallback onLyrics;
  final VoidCallback onQueue;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 22),
      child: Row(
        children: [
          _NicheGlyph(
            icon: Icons.tune_rounded,
            onTap: onTune,
            active: false,
          ),
          const SizedBox(width: 18),
          _LyricsPill(accent: accent, onTap: onLyrics),
          const SizedBox(width: 18),
          _NicheGlyph(
            icon: Icons.queue_music_rounded,
            onTap: onQueue,
          ),
        ],
      ),
    );
  }
}

class _FullProgress extends ConsumerWidget {
  const _FullProgress();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final position =
        ref.watch(playerPositionProvider).valueOrNull ?? Duration.zero;
    final duration =
        ref.watch(playerDurationProvider).valueOrNull ?? Duration.zero;
    final hasDuration = duration > Duration.zero;
    final maxMs =
        duration.inMilliseconds.toDouble().clamp(1.0, double.infinity);
    final valueMs =
        position.inMilliseconds.clamp(0, duration.inMilliseconds).toDouble();
    return Column(
      children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: Colors.white.withValues(alpha: 0.85),
            inactiveTrackColor: Colors.white.withValues(alpha: 0.18),
            thumbColor: Colors.white,
            trackHeight: 4,
            thumbShape:
                const RoundSliderThumbShape(enabledThumbRadius: 6),
            overlayShape:
                const RoundSliderOverlayShape(overlayRadius: 14),
          ),
          child: Slider(
            min: 0,
            max: maxMs,
            value: valueMs,
            onChanged: hasDuration
                ? (v) => ref
                    .read(nowPlayingProvider.notifier)
                    .seek(Duration(milliseconds: v.toInt()))
                : null,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _formatDuration(position),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withValues(alpha: 0.6),
                ),
              ),
              Text(
                '-${_formatDuration(duration - position)}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

String _formatDuration(Duration d) {
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$m:$s';
}

/// Glass icon circle (38×38) used in the top chrome — matches the Lumen
/// design system's `IconCircle`. Previously used a BackdropFilter with
/// σ=18 blur to read as live glass; that meant every visible round-icon
/// + the lyrics pill + the niche glyphs (5–6 of them at full mode)
/// each forced a saveLayer per frame, which on most Android devices
/// was the dominant per-frame cost on the full player. Switched to a
/// solid translucent fill with the same dark tint + top-edge gradient
/// + 1 px white border; the visual difference is small (the lit bloom
/// behind no longer warps through the circle, but the cover is mostly
/// dark anyway) and the saveLayers are gone.
class _RoundIcon extends StatelessWidget {
  const _RoundIcon({
    required this.icon,
    required this.onTap,
    this.tint,
    this.size = 38,
    this.iconSize = 18,
  });
  final IconData icon;
  final VoidCallback? onTap;
  final Color? tint;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onTap,
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              // Static dark fill — bumped alpha 0.55 → 0.72 to compensate
              // for the lost blur (the blur used to darken the bg under
              // the circle by itself).
              color: const Color.fromRGBO(20, 20, 28, 0.72),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.18),
              ),
              // Top-edge highlight to fake an inset white shadow.
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.white.withValues(alpha: 0.10),
                  Colors.transparent,
                ],
                stops: const [0.0, 0.5],
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color.fromRGBO(0, 0, 0, 0.35),
                  blurRadius: 24,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Icon(
              icon,
              size: iconSize,
              color: tint ?? Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

/// Larger glass circle (50×50) used in the niche bar's `Tune` and
/// `Queue` slots. Same construction as [_RoundIcon] but sized up and
/// with a 28 px glyph.
class _NicheGlyph extends StatelessWidget {
  const _NicheGlyph({
    required this.icon,
    required this.onTap,
    this.active = true,
  });
  final IconData icon;
  final VoidCallback? onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return _RoundIcon(
      icon: icon,
      onTap: active ? onTap : null,
      size: 50,
      iconSize: 28,
      tint: active
          ? Colors.white.withValues(alpha: 0.92)
          : Colors.white.withValues(alpha: 0.45),
    );
  }
}

/// Wide glass pill used as the centerpiece of the niche bar. The
/// `Lyrics` button — text-only, accent-coloured, expanded to fill the
/// space between the two niche glyphs.
class _LyricsPill extends StatelessWidget {
  const _LyricsPill({required this.accent, required this.onTap});
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Same swap as _RoundIcon: dropped the BackdropFilter(σ=18). The
    // pill is the centerpiece of the niche bar so its glass look mattered
    // a bit more than the round icons, but at full mode it sits on a
    // mostly-dark portion of the bloom; a static dark fill at higher
    // alpha is visually indistinguishable from the live-blurred version
    // and saves one more saveLayer per frame.
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onTap,
          child: Container(
            height: 50,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color.fromRGBO(20, 20, 28, 0.70),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.16),
              ),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.white.withValues(alpha: 0.08),
                  Colors.transparent,
                ],
                stops: const [0.0, 0.5],
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color.fromRGBO(0, 0, 0, 0.35),
                  blurRadius: 24,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Text(
              'Lyrics',
              style: TextStyle(
                color: accent,
                fontSize: 14,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Title text that shrinks 30 → 18 to fit on a single line — matches
/// the Lumen handoff's `FitTitle`. Uses TextPainter to measure each
/// candidate size; first one that fits wins.
///
/// Previously this re-ran up to 12 `TextPainter.layout()` calls on every
/// build, which meant during a player-expansion drag (the parent
/// rebuilds on every animation tick) it was doing ~720 text layouts a
/// second for an unchanged title. Cached now on `(text, maxWidth)` so
/// the measure runs only when one of those actually changes.
class _FitTitle extends StatefulWidget {
  const _FitTitle({required this.text});
  final String text;

  @override
  State<_FitTitle> createState() => _FitTitleState();
}

class _FitTitleState extends State<_FitTitle> {
  String? _measuredText;
  double? _measuredWidth;
  double _chosen = 18.0;

  double _measure(String text, double maxWidth) {
    if (text == _measuredText && maxWidth == _measuredWidth) return _chosen;
    var chosen = 18.0;
    for (var size = 30.0; size > 18.0; size -= 1.0) {
      final tp = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            fontSize: size,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.8,
            height: 1.08,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();
      if (tp.width <= maxWidth) {
        chosen = size;
        tp.dispose();
        break;
      }
      tp.dispose();
    }
    _measuredText = text;
    _measuredWidth = maxWidth;
    _chosen = chosen;
    return chosen;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final chosen = _measure(widget.text, constraints.maxWidth);
        return Text(
          widget.text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: chosen,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.8,
            height: 1.08,
            color: Colors.white,
          ),
        );
      },
    );
  }
}

// Suppress unused-import warnings for symbols only referenced in
// commented-out code paths during the migration.
// ignore: unused_element
void _keepImports() {
  HapticFeedback.lightImpact();
  AlbumColors.fallback;
}
