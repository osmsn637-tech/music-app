import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart'
    show
        AdaptiveGlass,
        GlassQuality,
        LiquidGlassSettings,
        LiquidRoundedSuperellipse;

import '../../core/services/volume_service.dart';
import '../../core/utils/album_colors.dart';
import '../../data/database/app_database.dart';
import '../../features/ai_dj/ai_dj_service.dart';
import '../../features/ai_dj/providers.dart';
import '../../features/automix/providers.dart';
import '../../features/connect/providers.dart';
import '../../features/library/album_colors_provider.dart';
import '../../features/nav/nav_collapse_controller.dart';
import '../../features/player/now_playing_controller.dart';
import '../../features/player/playback_modes.dart';
import '../../features/player/player_expansion_controller.dart';
import '../../features/player/player_service.dart';
import '../../features/player/providers.dart';
import '../screens/entity_nav.dart';
import '../screens/lyrics_screen.dart' show InlineLyrics;
import '../theme/app_theme.dart';
import 'album_art.dart';
import 'connect_sheet.dart';
import 'bloom_background.dart';
import 'liquid_nav_bar.dart' show NavGeometry;
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
  const ExpandingPlayer({super.key});

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
    final hasPrev = djActive ? djQueue.currentIndex > 0 : nowController.hasPrev;
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
        : AlbumColors.accentFromPalette(
            palette,
            fallback: const Color(0xFFFFA08F),
          );

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

    final navCollapse = NavCollapseScope.read(context);

    return _PlayerMorph(
      song: song,
      expansion: expansion,
      navCollapse: navCollapse,
      isPlaying: isPlaying,
      loading: loading,
      hasPrev: hasPrev,
      hasNext: hasNext,
      accent: accent,
      onPlayPause: onPlayPause,
      onNext: hasNext ? onNext : null,
      onPrev: hasPrev ? onPrev : null,
      onMore: () => SongActionsSheet.show(context, song, fromPlayer: true),
    );
  }

  /// Soft white that matches the mini-player's resolved icon colour.
  /// Kept as a static constant so [_PlayerMorph] (separate class) can
  /// share the value without each instance re-allocating a Color.
  static const Color miniGlyphWhite = _miniGlyphWhite;
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
class _PlayerMorph extends StatefulWidget {
  const _PlayerMorph({
    required this.song,
    required this.expansion,
    required this.navCollapse,
    required this.isPlaying,
    required this.loading,
    required this.hasPrev,
    required this.hasNext,
    required this.accent,
    required this.onPlayPause,
    required this.onNext,
    required this.onPrev,
    required this.onMore,
  });

  final SongRow song;
  final PlayerExpansionController expansion;
  final NavCollapseController navCollapse;
  final bool isPlaying;
  final bool loading;
  final bool hasPrev;
  final bool hasNext;
  final Color accent;
  final VoidCallback onPlayPause;
  final VoidCallback? onNext;
  final VoidCallback? onPrev;
  final VoidCallback onMore;

  @override
  State<_PlayerMorph> createState() => _PlayerMorphState();
}

class _PlayerMorphState extends State<_PlayerMorph>
    with TickerProviderStateMixin {
  /// Lyrics-shown morph (0 = art big & lyrics hidden, 1 = art shrunk
  /// to thumbnail at top-left & lyrics fill the freed space).
  /// Owned here because the toggle is player-internal UI state, not
  /// part of the now-playing model.
  late final AnimationController _lyricsController;

  /// Queue-shown morph (0 = art big & queue hidden, 1 = art shrunk to
  /// thumbnail & the up-next list fills the freed space). Mutually
  /// exclusive with [_lyricsController] — opening one closes the other.
  late final AnimationController _queueController;

  /// Controls-reveal morph for full-page lyrics (0 = controls shown,
  /// 1 = controls hidden & the lyrics grow to fill the screen). Driven by
  /// swipe gestures on the lyric list: a downward swipe hides the controls;
  /// an upward swipe re-shows them, but only on the *second* upward swipe
  /// (the first one just arms the reveal — see [_onLyricsScroll]).
  late final AnimationController _controlsReveal;

  /// True once the user has made one upward swipe while the controls are
  /// hidden; the next upward swipe actually reveals them.
  bool _revealArmed = false;

  /// Album-cover grow/shrink on play/pause (0 = paused/small, 1 = playing/
  /// big). Animated so the size change eases in instead of snapping.
  late final AnimationController _playController;

  @override
  void initState() {
    super.initState();
    _lyricsController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
      reverseDuration: const Duration(milliseconds: 260),
      value: 0,
    );
    _queueController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
      reverseDuration: const Duration(milliseconds: 260),
      value: 0,
    );
    _controlsReveal = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
      value: 0,
    );
    _playController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
      value: widget.isPlaying ? 1.0 : 0.0,
    );
    // Collapsing the player must always restore the controls so they're
    // never stuck hidden on the next expand.
    widget.expansion.animation.addListener(_resetControlsOnCollapse);
  }

  @override
  void didUpdateWidget(covariant _PlayerMorph oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying != oldWidget.isPlaying) {
      _playController.animateTo(
        widget.isPlaying ? 1.0 : 0.0,
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  void dispose() {
    widget.expansion.animation.removeListener(_resetControlsOnCollapse);
    _controlsReveal.dispose();
    _queueController.dispose();
    _playController.dispose();
    _lyricsController.dispose();
    super.dispose();
  }

  void _resetControlsOnCollapse() {
    if (widget.expansion.value < 0.85 && _controlsReveal.value != 0) {
      _controlsReveal.value = 0;
      _revealArmed = false;
    }
    // Fully collapsed → snap the lyrics/queue surfaces back to the cover so the
    // NEXT expand always opens on the album art, never straight into lyrics or
    // the queue. Below e≈0.03 both surfaces are already invisible (full chrome
    // only renders above e>0.3), so this is an instant, unseen reset.
    if (widget.expansion.value < 0.03) {
      if (_lyricsController.value != 0) _lyricsController.value = 0;
      if (_queueController.value != 0) _queueController.value = 0;
    }
  }

  /// Swipe handler for the lyric list. Scrolling DOWN into the lyrics hides the
  /// transport (full-page lyrics); scrolling back UP brings it back — but only
  /// on the *second* upward swipe, so a casual scroll-back doesn't pop the
  /// controls in unexpectedly.
  void _onLyricsScroll(ScrollDirection dir) {
    // Only meaningful while actually viewing lyrics on the open player.
    if (_lyricsController.value < 0.5 || widget.expansion.value < 0.9) return;
    if (dir == ScrollDirection.reverse) {
      // Scrolling down (deeper into the lyrics) → hide the controls.
      _revealArmed = false;
      if (_controlsReveal.value == 0) _controlsReveal.forward();
    } else if (dir == ScrollDirection.forward) {
      // Scrolling back up → reveal, but require a second swipe.
      if (_controlsReveal.value > 0) {
        if (_revealArmed) {
          _controlsReveal.reverse();
          _revealArmed = false;
        } else {
          _revealArmed = true;
        }
      }
    }
  }

  void _toggleLyrics() {
    if (_lyricsController.value > 0.5) {
      // Leaving lyrics → always restore the controls.
      _controlsReveal.value = 0;
      _revealArmed = false;
      _lyricsController.animateTo(0, curve: Curves.easeOutCubic);
    } else {
      // Mutually exclusive with the queue surface.
      if (_queueController.value > 0) {
        _queueController.animateTo(0, curve: Curves.easeOutCubic);
      }
      _lyricsController.animateTo(1, curve: Curves.easeOutCubic);
    }
  }

  void _toggleQueue() {
    if (_queueController.value > 0.5) {
      _queueController.animateTo(0, curve: Curves.easeOutCubic);
    } else {
      // Mutually exclusive with the lyrics surface.
      if (_lyricsController.value > 0) {
        _controlsReveal.value = 0;
        _revealArmed = false;
        _lyricsController.animateTo(0, curve: Curves.easeOutCubic);
      }
      _queueController.animateTo(1, curve: Curves.easeOutCubic);
    }
  }

  /// Convenience accessors to the inner widget's props — _PlayerMorph
  /// used to be a StatelessWidget so the build body reads them as
  /// bare identifiers. Re-expose them as no-prefix locals via getters
  /// to keep the build body unchanged below.
  SongRow get song => widget.song;
  PlayerExpansionController get expansion => widget.expansion;
  NavCollapseController get navCollapse => widget.navCollapse;
  bool get isPlaying => widget.isPlaying;
  bool get loading => widget.loading;
  bool get hasPrev => widget.hasPrev;
  bool get hasNext => widget.hasNext;
  Color get accent => widget.accent;
  VoidCallback get onPlayPause => widget.onPlayPause;
  VoidCallback? get onNext => widget.onNext;
  VoidCallback? get onPrev => widget.onPrev;
  VoidCallback get onMore => widget.onMore;

  @override
  Widget build(BuildContext context) {
    // MediaQuery sizeOf / paddingOf depend on only the relevant slices
    // of the inherited MediaQueryData, so we don't rebuild on unrelated
    // MQ changes (text scale, etc.).
    final size = MediaQuery.sizeOf(context);
    final mqPad = MediaQuery.paddingOf(context);
    final topInset = mqPad.top;
    final bottomInset = mqPad.bottom;

    // Geometry comes from NavGeometry so the mini-player lines up with
    // the floating nav exactly. The mini has two "at-rest" shapes:
    //   * rest    (collapse=0): own row above the expanded nav,
    //     full width
    //   * inline  (collapse=1): between the (shrunk) collapsed tab
    //     pill and search button on a single, shorter row
    // The nav row itself shrinks on collapse — rowHeightRest at the
    // top, rowHeightCollapsed at the bottom — so the inline rect is
    // anchored to the collapsed row's height, not the rest one.
    final navBottomY = size.height - bottomInset - NavGeometry.bottomInset;
    final navRowTopRest = navBottomY - NavGeometry.rowHeightRest;
    final navRowTopCollapsed = navBottomY - NavGeometry.rowHeightCollapsed;

    final miniRestRect = Rect.fromLTRB(
      NavGeometry.hInset,
      navRowTopRest - NavGeometry.rowGap - NavGeometry.miniRestHeight,
      size.width - NavGeometry.hInset,
      navRowTopRest - NavGeometry.rowGap,
    );
    final miniInlineRect = Rect.fromLTRB(
      NavGeometry.hInset +
          NavGeometry.squareSideCollapsed +
          NavGeometry.inlineGap,
      navRowTopCollapsed,
      size.width -
          NavGeometry.hInset -
          NavGeometry.squareSideCollapsed -
          NavGeometry.inlineGap,
      navBottomY,
    );

    final fullRect = Offset.zero & size;
    // Bigger cover on the open player. Capped by width (side margins) and by
    // the vertical room above the fixed transport stack (everything below sits
    // at fixed offsets from the bottom), so it never crowds the title row /
    // scrubber on shorter phones.
    final artMaxH = size.height - bottomInset - topInset - 434;
    final fullArtSize = math.min(
      math.min(size.width - 72, 320.0),
      math.max(210.0, artMaxH),
    );
    final fullArtTop = topInset + 86;
    final fullArtRect = Rect.fromLTWH(
      (size.width - fullArtSize) / 2,
      fullArtTop,
      fullArtSize,
      fullArtSize,
    );
    // When lyrics is shown the art shrinks to this small thumbnail
    // tucked under the source eyebrow at the top-left, leaving the
    // big rect free for the lyrics list. Geometry mirrors the iOS 26
    // Apple Music "lyrics-on" header layout.
    const lyricsThumbSize = 60.0;
    final lyricsThumbRect = Rect.fromLTWH(
      24,
      topInset + 56,
      lyricsThumbSize,
      lyricsThumbSize,
    );
    final transportRowY = size.height - bottomInset - 200;
    final fullPlayRect = Rect.fromLTWH(
      (size.width - 74) / 2,
      transportRowY,
      74,
      74,
    );
    final fullNextRect = Rect.fromLTWH(
      size.width / 2 + 60,
      transportRowY + 6,
      62,
      62,
    );

    return AnimatedBuilder(
      animation: Listenable.merge([
        expansion.animation,
        navCollapse.animation,
        _lyricsController,
        _queueController,
        _controlsReveal,
        _playController,
      ]),
      builder: (context, _) {
        final e = expansion.value;
        final c = navCollapse.value;
        final zL = _lyricsController.value;
        final zQ = _queueController.value;
        // Either surface (lyrics or queue) shrinks the art to a thumbnail and
        // morphs the title to the top — so the shared geometry tracks the max.
        final z = math.max(zL, zQ);
        // Full-page lyrics controls-hide. Only effective while actually
        // viewing lyrics on the fully-open player, so a half-open morph, the
        // queue surface, or a collapsing player never hides the transport.
        final hEff = (zL > 0.5 && e > 0.85) ? _controlsReveal.value : 0.0;
        final chromeOpacity = (1.0 - hEff).clamp(0.0, 1.0);
        final atRest = e < 0.03;

        // Mini rect lerps from rest → inline based on nav collapse.
        final miniRect = Rect.lerp(miniRestRect, miniInlineRect, c)!;

        // Chrome sizes lerp with c so the pill's content stays
        // proportionate when squeezed into the shorter inline row
        // (NavGeometry.rowHeightCollapsed = 48).
        final miniArtSize = ui.lerpDouble(52, 36, c)!;
        final miniBtnSize = ui.lerpDouble(40, 32, c)!;
        final miniArtRect = Rect.fromLTWH(
          miniRect.left + 8,
          miniRect.top + (miniRect.height - miniArtSize) / 2,
          miniArtSize,
          miniArtSize,
        );
        final miniNextRect = Rect.fromLTWH(
          miniRect.right - 8 - miniBtnSize,
          miniRect.top + (miniRect.height - miniBtnSize) / 2,
          miniBtnSize,
          miniBtnSize,
        );
        final miniPlayRect = Rect.fromLTWH(
          miniRect.right - 8 - miniBtnSize - 4 - miniBtnSize,
          miniRect.top + (miniRect.height - miniBtnSize) / 2,
          miniBtnSize,
          miniBtnSize,
        );
        final miniRadius = ui.lerpDouble(22, 30, c)!;

        final cardRect = Rect.lerp(miniRect, fullRect, e)!;
        final cardRadius = ui.lerpDouble(miniRadius, 0, e)!;

        // Full-mode art rect lerps from "big centred" → "small top-
        // left thumbnail" as the lyrics toggle animates in. The
        // expansion lerp (mini → full) chains on top so an in-flight
        // expansion still lands on the right resting rect.
        final fullArtRectZ = Rect.lerp(fullArtRect, lyricsThumbRect, z)!;
        final artRect = Rect.lerp(miniArtRect, fullArtRectZ, e)!;
        // Apple's vinyl-rise tell, but pronounced: the cover grows big while
        // playing (1.10) and shrinks back to its resting size when paused
        // (0.92). Driven by _playController so it eases in/out. Only applied
        // at full mode (e≈1) and suppressed once lyrics is up.
        final fullScale = ui.lerpDouble(0.92, 1.10, _playController.value)!;
        final artScale = ui.lerpDouble(1.0, fullScale, e * (1 - z))!;
        final artRadius = ui.lerpDouble(12, LumenTokens.rLg, e)!;
        final playSize = ui.lerpDouble(miniBtnSize, 74, e)!;
        final nextSize = ui.lerpDouble(miniBtnSize, 62, e)!;
        final playRect = Rect.lerp(miniPlayRect, fullPlayRect, e)!;
        final nextRect = Rect.lerp(miniNextRect, fullNextRect, e)!;
        // Mini glyphs sit on the frosted pill (light in day mode) → use a
        // dark glyph there; they lerp to the album accent as it expands.
        final glyphColor = Color.lerp(
          Theme.of(context).brightness == Brightness.light
              ? const Color(0xF2111111)
              : ExpandingPlayer.miniGlyphWhite,
          accent,
          e,
        )!;

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
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Bloom — visible once the player starts
                    // expanding. Skipped entirely at mini so the FFT
                    // ticker + 3 curtain rebuilds don't grind while
                    // the player is collapsed.
                    if (e > 0.05)
                      Positioned.fill(
                        child: Opacity(
                          opacity: ((e - 0.05) / 0.30).clamp(0.0, 1.0),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(cardRadius),
                            child: BloomBackground(
                              song: song,
                              darkenStrength: 0.55,
                              audioReactive: e >= 0.2,
                            ),
                          ),
                        ),
                      ),
                    // iOS 26 liquid-glass pill — sits in front of the
                    // bloom layer and fades out as the player expands
                    // so the mini form reads as a frosted pill and
                    // the full form reads as the album-tinted bloom
                    // surface.
                    if (e < 0.5)
                      Positioned.fill(
                        child: Opacity(
                          opacity: ((0.5 - e) / 0.5).clamp(0.0, 1.0),
                          // Real iOS-26 Liquid Glass (refraction + rim
                          // specular) in place of the old flat
                          // BackdropFilter frost. `standard` quality uses
                          // the lightweight calibrated shader — cheap
                          // enough to keep up with the expand morph and it
                          // degrades cleanly on Windows/web (premium is
                          // Impeller-only). glassColor ≈ the old 8% white
                          // fill so the tint reads the same.
                          child: AdaptiveGlass(
                            shape: LiquidRoundedSuperellipse(
                              borderRadius: cardRadius,
                            ),
                            // On iOS/Impeller, premium uses the native
                            // scene graph and samples only the surface
                            // behind the pill. `standard` (Skia shader)
                            // with no LiquidGlassScope blurs the whole
                            // backdrop → the full-screen blur bug.
                            quality: GlassQuality.premium,
                            settings: const LiquidGlassSettings(
                              blur: 12,
                              thickness: 16,
                              glassColor: Color(0x14FFFFFF),
                              lightIntensity: 0.6,
                              glowIntensity: 0.35,
                            ),
                            child: const SizedBox.expand(),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),

            // 3. Frosted-glass sheet — when the queue / lyrics surface is
            //    open the whole player reads as ONE sheet of frosted glass
            //    over a blurred bloom; the cover, title, and controls then
            //    sit on top of it. Fades in with z (max of lyrics + queue),
            //    so the cover-only view keeps its vivid bloom untouched.
            if (e > 0.3 && z > 0.01)
              Positioned.fromRect(
                rect: cardRect,
                child: IgnorePointer(
                  child: Opacity(
                    opacity: ((e - 0.3) / 0.7).clamp(0.0, 1.0) * z,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(cardRadius),
                      child: BackdropFilter(
                        filter: ui.ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                        child: Container(
                          color: Colors.white.withValues(alpha: 0.06),
                        ),
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
                miniArtSize: miniArtSize,
                miniBtnSize: miniBtnSize,
                opacity: ((0.7 - e) / 0.7).clamp(0.0, 1.0),
                collapse: c,
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
                lyricsThumbRect: lyricsThumbRect,
                hasPrev: hasPrev,
                isPlaying: isPlaying,
                accent: accent,
                opacity: ((e - 0.3) / 0.7).clamp(0.0, 1.0),
                lyricsValue: zL,
                queueValue: zQ,
                controlsReveal: hEff,
                onPrev: onPrev,
                onDismiss: expansion.collapse,
                onToggleLyrics: _toggleLyrics,
                onToggleQueue: _toggleQueue,
                onLyricsScroll: _onLyricsScroll,
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
                child: Transform.scale(
                  scale: artScale,
                  child: AlbumArt(
                    artworkPath: song.localArtworkPath,
                    seed: song.id,
                    size: artRect.width,
                    radius: artRadius,
                  ),
                ),
              ),
            ),

            // 7. Shared morphing play / pause. Fades out with the rest of
            //    the transport when controls auto-hide for full-page lyrics
            //    (the shared transport half lives here, not in _FullChrome).
            Positioned.fromRect(
              rect: playRect,
              child: Opacity(
                opacity: chromeOpacity,
                child: IgnorePointer(
                  ignoring: hEff > 0.5,
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
              ),
            ),

            // 8. Shared morphing next.
            Positioned.fromRect(
              rect: nextRect,
              child: Opacity(
                opacity: chromeOpacity,
                child: IgnorePointer(
                  ignoring: hEff > 0.5,
                  child: _GlyphButton(
                    icon: Icons.fast_forward_rounded,
                    size: nextSize,
                    color: hasNext
                        ? glyphColor
                        : Colors.white.withValues(alpha: 0.20),
                    onTap: onNext,
                  ),
                ),
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
            //
            //    EXCEPT in lyrics mode: there the overlay would win the
            //    lyric list's vertical scroll gesture, so it shrinks to just
            //    the top header strip (grabber + thumbnail + title). Drag the
            //    header to collapse; the lyrics below scroll freely.
            Positioned.fromRect(
              rect: z > 0.5
                  ? Rect.fromLTRB(
                      cardRect.left,
                      cardRect.top,
                      cardRect.right,
                      lyricsThumbRect.bottom + 8,
                    )
                  : cardRect,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onVerticalDragUpdate: (d) => expansion.dragBy(d.delta.dy),
                onVerticalDragEnd: (d) =>
                    expansion.endDrag(velocity: d.velocity.pixelsPerSecond.dy),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Inline up-next surface — replaces the old modal queue sheet. Fills the
/// freed area when the queue button is active (mirrors the inline lyrics
/// surface). Shows the AI DJ queue (tap to jump) when the DJ owns the
/// playhead; otherwise the reorderable generic playback queue. A playback-
/// mode control strip (repeat · shuffle · infinity · automix) sits pinned
/// below the list.
/// Heights of the frosted header / controls bars that the queue list
/// scrolls behind. The list is padded by these so the first and last
/// rows clear the glass at rest, then slide *under* it — staying visible
/// (blurred) through the glass instead of hard-cutting at the edge.
const double _kQueueHeaderH = 38;
const double _kQueueControlsH = 64;

class _InlineQueue extends ConsumerWidget {
  const _InlineQueue();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final djQueue = ref.watch(aiDjQueueControllerProvider);
    final entries = djQueue.queue;
    final djActive = djQueue.isActive && entries.isNotEmpty;
    // Stack (not Column): the list fills the whole surface and the two
    // glass bars are overlaid on top, so songs scroll *behind* them and
    // read through the frosted blur.
    return Stack(
      children: [
        Positioned.fill(
          child: djActive
              ? ListView.builder(
                  padding: const EdgeInsets.only(
                    top: _kQueueHeaderH,
                    bottom: _kQueueControlsH + 8,
                  ),
                  itemCount: entries.length,
                  itemBuilder: (_, i) {
                    final entry = entries[i];
                    return _QueueRow(
                      entry: entry,
                      isCurrent: i == djQueue.currentIndex,
                      onTap: () => ref
                          .read(aiDjQueueControllerProvider.notifier)
                          .playAt(i),
                    );
                  },
                )
              : const _GenericQueueList(inline: true),
        ),
        // Frosted "Up Next" header — the song list scrolls behind it.
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: ClipRect(
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 22, sigmaY: 22),
              child: Container(
                height: _kQueueHeaderH,
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(horizontal: 24),
                decoration: const BoxDecoration(
                  color: Color(0x0AFFFFFF),
                  border: Border(bottom: BorderSide(color: Color(0x14FFFFFF))),
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.queue_music_rounded,
                      size: 18,
                      color: Color(0xB3FFFFFF),
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Up Next',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        // Frosted controls strip — songs scroll behind it as well.
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: ClipRect(
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 22, sigmaY: 22),
              child: const _QueueControlsRow(),
            ),
          ),
        ),
      ],
    );
  }
}

/// Playback-mode control strip below the inline queue: repeat, shuffle,
/// infinity (never-ending queue — auto-continues with another album by the
/// same artist when it runs out), and automix (beat-matched transitions).
/// Active state uses the app's pink accent — NOT the album-cover tint.
class _QueueControlsRow extends ConsumerWidget {
  const _QueueControlsRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final modes = ref.watch(playbackModesProvider);
    final controller = ref.read(nowPlayingProvider.notifier);
    final automixOn = ref.watch(autoMixEnabledProvider);
    const pink = LumenTokens.accent;
    final dim = Colors.white.withValues(alpha: 0.6);

    final repeatOn = modes.repeat != QueueRepeatMode.off;
    final repeatIcon = modes.repeat == QueueRepeatMode.one
        ? Icons.repeat_one_rounded
        : Icons.repeat_rounded;

    return Container(
      decoration: const BoxDecoration(
        // Faint fill so the frosted blur behind it reads as glass.
        color: Color(0x0AFFFFFF),
        border: Border(top: BorderSide(color: Color(0x14FFFFFF))),
      ),
      padding: const EdgeInsets.fromLTRB(28, 10, 28, 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _QueueControl(
            icon: repeatIcon,
            label: 'Repeat',
            active: repeatOn,
            accent: pink,
            dim: dim,
            onTap: controller.cycleRepeat,
          ),
          _QueueControl(
            icon: Icons.shuffle_rounded,
            label: 'Shuffle',
            active: modes.shuffle,
            accent: pink,
            dim: dim,
            onTap: controller.toggleShuffle,
          ),
          _QueueControl(
            icon: Icons.all_inclusive_rounded,
            label: 'Infinity',
            active: modes.endless,
            accent: pink,
            dim: dim,
            onTap: controller.toggleEndless,
          ),
          _QueueControl(
            icon: Icons.auto_awesome_rounded,
            label: 'Automix',
            active: automixOn,
            accent: pink,
            dim: dim,
            onTap: () =>
                ref.read(autoMixEnabledProvider.notifier).update((v) => !v),
          ),
        ],
      ),
    );
  }
}

class _QueueControl extends StatelessWidget {
  const _QueueControl({
    required this.icon,
    required this.label,
    required this.active,
    required this.accent,
    required this.dim,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final Color accent;
  final Color dim;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = active ? accent : dim;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 24, color: color),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// The generic playback queue (library / artist / album / playlist),
/// reorderable, with per-row remove and tap-to-jump.
class _GenericQueueList extends ConsumerWidget {
  const _GenericQueueList({this.inline = false});

  /// When embedded in the player's inline queue surface (vs. a modal sheet):
  /// fills its bounded parent + scrolls instead of shrink-wrapping, and a
  /// tap-to-jump doesn't pop any route.
  final bool inline;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(nowPlayingProvider.notifier);
    return ValueListenableBuilder<QueueView>(
      valueListenable: controller.queueView,
      builder: (context, qv, _) {
        final queue = qv.queue;
        if (queue.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 36),
            child: Text(
              'Nothing queued. Play a song or album to build a queue.',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.65),
                fontSize: 14,
              ),
            ),
          );
        }
        return ReorderableListView.builder(
          shrinkWrap: !inline,
          buildDefaultDragHandles: false,
          // Inline: clear the frosted header/controls bars at rest, then
          // scroll behind them. Modal sheet: just a small bottom gutter.
          padding: EdgeInsets.only(
            top: inline ? _kQueueHeaderH : 0,
            bottom: (inline ? _kQueueControlsH : 0) + 8,
          ),
          itemCount: queue.length,
          onReorder: controller.reorderQueue,
          itemBuilder: (context, i) {
            final s = queue[i];
            final isCurrent = i == qv.index;
            return _GenericQueueRow(
              key: ValueKey('${s.id}_$i'),
              song: s,
              index: i,
              isCurrent: isCurrent,
              onTap: () {
                controller.jumpTo(i);
                if (!inline) Navigator.of(context).pop();
              },
              onRemove: isCurrent ? null : () => controller.removeFromQueue(i),
            );
          },
        );
      },
    );
  }
}

class _GenericQueueRow extends StatelessWidget {
  const _GenericQueueRow({
    super.key,
    required this.song,
    required this.index,
    required this.isCurrent,
    required this.onTap,
    required this.onRemove,
  });

  final SongRow song;
  final int index;
  final bool isCurrent;
  final VoidCallback onTap;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            AlbumArt(
              artworkPath: song.localArtworkPath,
              seed: song.id,
              size: 42,
              radius: 8,
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
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isCurrent ? LumenTokens.accent : Colors.white,
                    ),
                  ),
                  if (song.artist != null)
                    Text(
                      song.artist!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.55),
                      ),
                    ),
                ],
              ),
            ),
            if (isCurrent)
              const Padding(
                padding: EdgeInsets.only(right: 8),
                child: Icon(
                  Icons.graphic_eq_rounded,
                  size: 18,
                  color: LumenTokens.accent,
                ),
              ),
            if (onRemove != null)
              _GlyphButton(
                icon: Icons.remove_circle_outline_rounded,
                size: 22,
                color: Colors.white.withValues(alpha: 0.5),
                onTap: onRemove!,
              ),
            ReorderableDragStartListener(
              index: index,
              child: Padding(
                padding: const EdgeInsets.only(left: 6),
                child: Icon(
                  Icons.drag_handle_rounded,
                  size: 22,
                  color: Colors.white.withValues(alpha: 0.4),
                ),
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
                        color: Colors.white.withValues(
                          alpha: isCurrent ? 1.0 : 0.92,
                        ),
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
    required this.miniArtSize,
    required this.miniBtnSize,
    required this.opacity,
    required this.collapse,
    required this.accent,
  });

  final dynamic song; // SongRow — typed dynamic so we avoid the import.
  final Rect miniRect;
  final double miniArtSize;
  final double miniBtnSize;
  final double opacity;

  /// Nav-collapse value (0 = at-rest, 1 = inline). Used to fade the
  /// rest-only chrome (artist subtitle) as the mini squeezes into the
  /// inline slot — Apple Music's collapsed pill is single-line.
  final double collapse;
  final Color accent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Title + artist text sits between the mini cover and the
    // play/next glyphs. Widths and positions follow the lerped mini
    // chrome sizes so the row stays tight at both endpoints.
    final titleLeft = miniRect.left + 8 + miniArtSize + 12;
    final titleRight = miniRect.right - 8 - miniBtnSize - 4 - miniBtnSize - 4;
    final maxWidth = math.max(0.0, titleRight - titleLeft);

    // Rest-only chrome (artist subtitle) fades out as collapse → 1.
    final restOnlyOpacity = (1.0 - collapse * 1.6).clamp(0.0, 1.0);
    final showArtist = song.artist != null && restOnlyOpacity > 0.05;

    // Centre the title block vertically in the mini rect — works for
    // both single-line (inline) and two-line (rest) variants because
    // the column hugs its content.
    final blockTop =
        miniRect.top + miniRect.height / 2 - (showArtist ? 22 : 11);

    final titleSize = ui.lerpDouble(16, 14, collapse)!;

    return IgnorePointer(
      ignoring: opacity < 0.05,
      child: Opacity(
        opacity: opacity,
        child: Stack(
          children: [
            Positioned(
              left: titleLeft,
              top: blockTop,
              width: maxWidth,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    song.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: titleSize,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                      // Theme-aware: the mini bar is a frosted pill, light
                      // in day mode — white text would wash out there.
                      color: LumenTokens.fg(context),
                      height: 1.1,
                    ),
                  ),
                  if (showArtist)
                    Opacity(
                      opacity: restOnlyOpacity,
                      child: Text(
                        song.artist!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: LumenTokens.fgDimOf(context),
                          height: 1.2,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Full-mode chrome. iOS 26 Apple Music layout:
///
///   - Grabber pill (top centre, drag affordance)
///   - Source eyebrow ("PLAYING FROM ALBUM · Name")
///   - Album art (rendered by the shared morphing layer above; we just
///     read [fullArtRect] / [lyricsThumbRect] for layout maths)
///   - Title row (title + artist + more button), left-aligned
///   - Slim scrubber + time labels
///   - Transport row (prev + shared play/next)
///   - Volume slider with speaker glyphs
///   - Actions row — Lyrics · Connect · Queue
///
/// When [lyricsValue] or [queueValue] animates from 0 → 1, the title row
/// morphs from "below big art" to "next to the small thumbnail at top-left"
/// and the matching surface ([InlineLyrics] / [_InlineQueue]) fades in to
/// fill the freed area.
class _FullChrome extends ConsumerWidget {
  const _FullChrome({
    required this.song,
    required this.topInset,
    required this.bottomInset,
    required this.transportRowY,
    required this.fullArtRect,
    required this.lyricsThumbRect,
    required this.hasPrev,
    required this.isPlaying,
    required this.accent,
    required this.opacity,
    required this.lyricsValue,
    required this.queueValue,
    required this.controlsReveal,
    required this.onPrev,
    required this.onDismiss,
    required this.onToggleLyrics,
    required this.onToggleQueue,
    required this.onLyricsScroll,
    required this.onMore,
  });

  final dynamic song;
  final double topInset;
  final double bottomInset;
  final double transportRowY;
  final Rect fullArtRect;
  final Rect lyricsThumbRect;
  final bool hasPrev;
  final bool isPlaying;
  final Color accent;
  final double opacity;

  /// 0 = art mode, 1 = lyrics mode.
  final double lyricsValue;

  /// 0 = art mode, 1 = inline-queue mode. Shares the art-shrink / title
  /// morph with [lyricsValue] (the geometry tracks whichever is larger).
  final double queueValue;

  /// 0 = controls shown, 1 = controls hidden & lyrics fill the screen.
  final double controlsReveal;
  final VoidCallback? onPrev;
  final VoidCallback onDismiss;
  final VoidCallback onToggleLyrics;
  final VoidCallback onToggleQueue;

  /// Forwarded from the lyric list's scroll gestures so the host can
  /// hide/reveal the transport (swipe down = hide; 2nd swipe up = show).
  final void Function(ScrollDirection direction) onLyricsScroll;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final size = MediaQuery.sizeOf(context);
    // Either surface (lyrics or queue) drives the art-shrink + title morph.
    final z = math.max(lyricsValue, queueValue);

    // Vertical layout — anchored to the bottom edge of the screen so
    // every chrome row sits at the same absolute position on a given
    // device regardless of art size.
    final scrubberTop = transportRowY - 60;
    final volumeTop = size.height - bottomInset - 130;
    final actionsBottom = bottomInset + 18;

    // Title row morph. At z=0 it sits in a full-width block below the
    // big artwork; at z=1 it slots next to the small thumbnail at the
    // top so the rest of the screen is free for lyrics.
    final titleRectAtRest = Rect.fromLTRB(
      24,
      fullArtRect.bottom + 22,
      size.width - 24,
      fullArtRect.bottom + 22 + 58,
    );
    final titleRectAtLyrics = Rect.fromLTRB(
      lyricsThumbRect.right + 12,
      lyricsThumbRect.top + 2,
      size.width - 24,
      lyricsThumbRect.bottom + 2,
    );
    final titleRect = Rect.lerp(titleRectAtRest, titleRectAtLyrics, z)!;

    // Lyrics / queue surface fills the visual area where the big art used to
    // be. Top edge tracks z so the surface enters from the art's top edge
    // (z<0.3 ≈ behind the art) and ends up below the thumbnail at z=1.
    final surfaceTop = ui.lerpDouble(
      fullArtRect.top,
      lyricsThumbRect.bottom + 8,
      z,
    )!;
    // When the lyrics controls hide on swipe-down, the pane grows down into
    // the freed space (full-page lyrics). InlineLyrics' percentage-based
    // ListView padding re-anchors itself as the viewport grows. The queue
    // surface never hides the controls (controlsReveal stays 0 for it).
    final surfaceBottom = ui.lerpDouble(
      scrubberTop - 12,
      size.height - bottomInset - 12,
      controlsReveal,
    )!;
    final surfaceRect = Rect.fromLTRB(0, surfaceTop, size.width, surfaceBottom);

    // Bottom-control fade driven by the auto-hide reveal.
    final chromeOpacity = (1.0 - controlsReveal).clamp(0.0, 1.0);
    final chromeGone = controlsReveal > 0.5;

    return IgnorePointer(
      ignoring: opacity < 0.05,
      child: Opacity(
        opacity: opacity,
        child: Stack(
          children: [
            // 1. Grabber pill.
            Positioned(
              left: 0,
              right: 0,
              top: topInset + 8,
              child: const _Grabber(),
            ),

            // 2. Source eyebrow.
            Positioned(
              left: 24,
              right: 24,
              top: topInset + 24,
              child: _SourceEyebrow(song: song),
            ),

            // 3. Inline lyrics — fades in as lyricsValue → 1.
            if (lyricsValue > 0.01)
              Positioned.fromRect(
                rect: surfaceRect,
                child: Opacity(
                  opacity: ((lyricsValue - 0.3) / 0.7).clamp(0.0, 1.0),
                  child: InlineLyrics(onScrollGesture: onLyricsScroll),
                ),
              ),

            // 3b. Inline up-next queue — fades in as queueValue → 1.
            if (queueValue > 0.01)
              Positioned.fromRect(
                rect: surfaceRect,
                child: Opacity(
                  opacity: ((queueValue - 0.3) / 0.7).clamp(0.0, 1.0),
                  child: const _InlineQueue(),
                ),
              ),

            // 4. Title row.
            Positioned.fromRect(
              rect: titleRect,
              child: _TitleRow(song: song, lyricsValue: z, onMore: onMore),
            ),

            // 5. Slim scrubber + time labels.
            Positioned(
              left: 22,
              right: 22,
              top: scrubberTop,
              height: 50,
              child: Opacity(
                opacity: chromeOpacity,
                child: IgnorePointer(
                  ignoring: chromeGone,
                  child: _SlimScrubber(accent: accent),
                ),
              ),
            ),

            // 6. Prev button (play+next are shared with the mini layer).
            Positioned(
              left: size.width / 2 - 122,
              top: transportRowY + 6,
              width: 62,
              height: 62,
              child: Opacity(
                opacity: chromeOpacity,
                child: IgnorePointer(
                  ignoring: chromeGone,
                  child: _GlyphButton(
                    icon: Icons.fast_rewind_rounded,
                    size: 62,
                    color: hasPrev
                        ? accent
                        : Colors.white.withValues(alpha: 0.20),
                    onTap: onPrev,
                  ),
                ),
              ),
            ),

            // 7. Volume row.
            Positioned(
              left: 22,
              right: 22,
              top: volumeTop,
              height: 30,
              child: Opacity(
                opacity: chromeOpacity,
                child: IgnorePointer(
                  ignoring: chromeGone,
                  child: const _VolumeRow(),
                ),
              ),
            ),

            // 8. Actions row — Lyrics · Connect · Queue.
            Positioned(
              left: 0,
              right: 0,
              bottom: actionsBottom,
              height: 48,
              child: Opacity(
                opacity: chromeOpacity,
                child: IgnorePointer(
                  ignoring: chromeGone,
                  child: _ActionsRow(
                    accent: accent,
                    lyricsActive: lyricsValue > 0.5,
                    queueActive: queueValue > 0.5,
                    onToggleLyrics: onToggleLyrics,
                    onToggleQueue: onToggleQueue,
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

/// Tiny rounded pill at the top centre of the player. Purely visual —
/// the drag-to-collapse handler lives on the parent's gesture overlay.
class _Grabber extends StatelessWidget {
  const _Grabber();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 36,
        height: 5,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.32),
          borderRadius: BorderRadius.circular(3),
        ),
      ),
    );
  }
}

/// "PLAYING FROM ALBUM · *Name*" line above the artwork. Reads the
/// song's album / artist; falls back to "PLAYING FROM YOUR LIBRARY".
class _SourceEyebrow extends StatelessWidget {
  const _SourceEyebrow({required this.song});
  final dynamic song;

  @override
  Widget build(BuildContext context) {
    final eyebrow = song.album != null
        ? 'PLAYING FROM ALBUM'
        : 'PLAYING FROM YOUR LIBRARY';
    final name = song.album ?? song.artist ?? '';
    return Column(
      children: [
        Text(
          eyebrow,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
            color: Colors.white.withValues(alpha: 0.55),
          ),
        ),
        if (name.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                PlayerExpansionScope.maybeRead(context)?.collapse();
                if (song.album != null) {
                  openAlbum(context, song.album);
                } else {
                  openArtist(context, song.artist);
                }
              },
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Left-aligned title + artist with a trailing "…" button. Font sizes
/// lerp down as the player flips to lyrics mode so the row stays
/// proportionate next to the small album-art thumbnail.
class _TitleRow extends StatelessWidget {
  const _TitleRow({
    required this.song,
    required this.lyricsValue,
    required this.onMore,
  });

  final dynamic song;
  final double lyricsValue;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final titleSize = ui.lerpDouble(22, 16, lyricsValue)!;
    final artistSize = ui.lerpDouble(15, 12, lyricsValue)!;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                song.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: titleSize,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                  color: Colors.white,
                  height: 1.15,
                ),
              ),
              if (song.artist != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      PlayerExpansionScope.maybeRead(context)?.collapse();
                      openArtist(context, song.artist);
                    },
                    child: Text(
                      song.artist!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: artistSize,
                        fontWeight: FontWeight.w600,
                        color: Colors.white.withValues(alpha: 0.65),
                        height: 1.2,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        _GlyphButton(
          icon: Icons.more_horiz_rounded,
          size: 28,
          color: Colors.white.withValues(alpha: 0.75),
          onTap: onMore,
        ),
      ],
    );
  }
}

/// Slim Apple-style scrubber — thin track, small thumb that grows on drag,
/// monotype time labels below. While AutoMix is blending two tracks the bar
/// glows pink and the labels cross-fade to "Mixing".
class _SlimScrubber extends ConsumerStatefulWidget {
  const _SlimScrubber({required this.accent});
  final Color accent;

  @override
  ConsumerState<_SlimScrubber> createState() => _SlimScrubberState();
}

class _SlimScrubberState extends ConsumerState<_SlimScrubber>
    with SingleTickerProviderStateMixin {
  // While dragging, hold the scrubbed position locally and DON'T seek —
  // playback keeps going at the live spot; the seek commits on release.
  double? _dragMs;

  // Drives the "mixing" glow: a gentle pink pulse while a transition runs,
  // eased back to 0 when it ends.
  late final AnimationController _glow;

  @override
  void initState() {
    super.initState();
    _glow = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
  }

  @override
  void dispose() {
    _glow.dispose();
    super.dispose();
  }

  void _onMixingChanged(bool mixing) {
    if (mixing) {
      _glow.repeat(min: 0.4, max: 1.0, reverse: true);
    } else {
      _glow.stop();
      _glow.animateTo(
        0,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<bool>(
      autoMixMixingProvider,
      (_, next) => _onMixingChanged(next),
    );
    final mixing = ref.watch(autoMixMixingProvider);

    final position =
        ref.watch(playerPositionProvider).valueOrNull ?? Duration.zero;
    final duration =
        ref.watch(playerDurationProvider).valueOrNull ?? Duration.zero;
    final hasDuration = duration > Duration.zero;
    final maxMs = duration.inMilliseconds.toDouble().clamp(
      1.0,
      double.infinity,
    );
    final liveMs = position.inMilliseconds
        .clamp(0, duration.inMilliseconds)
        .toDouble();
    final valueMs = (_dragMs ?? liveMs).clamp(0.0, maxMs);
    final shownPos = Duration(milliseconds: valueMs.toInt());

    final labelStyle = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w600,
      color: Colors.white.withValues(alpha: 0.55),
      fontFeatures: LumenTokens.tnum,
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedBuilder(
          animation: _glow,
          builder: (context, _) {
            final g = _glow.value; // 0 (idle) → 1 (peak glow)
            final trackColor = Color.lerp(
              Colors.white.withValues(alpha: 0.85),
              LumenTokens.accent,
              g,
            )!;
            return DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                boxShadow: g > 0.02
                    ? [
                        BoxShadow(
                          color: LumenTokens.accent.withValues(alpha: 0.32 * g),
                          blurRadius: 6 + 16 * g,
                          spreadRadius: 0.5 * g,
                        ),
                      ]
                    : null,
              ),
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: trackColor,
                  inactiveTrackColor: Colors.white.withValues(alpha: 0.18),
                  thumbColor: Colors.white,
                  trackHeight: 3,
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 5,
                  ),
                  overlayShape: const RoundSliderOverlayShape(
                    overlayRadius: 12,
                  ),
                ),
                child: Slider(
                  min: 0,
                  max: maxMs,
                  value: valueMs,
                  onChanged: hasDuration
                      ? (v) => setState(() => _dragMs = v)
                      : null,
                  onChangeEnd: hasDuration
                      ? (v) {
                          ref
                              .read(nowPlayingProvider.notifier)
                              .seek(Duration(milliseconds: v.toInt()));
                          setState(() => _dragMs = null);
                        }
                      : null,
                ),
              ),
            );
          },
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 280),
            child: mixing
                ? const Row(
                    key: ValueKey('mixing'),
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.auto_awesome_rounded,
                        size: 13,
                        color: LumenTokens.accent,
                      ),
                      SizedBox(width: 6),
                      Text(
                        'Mixing',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: LumenTokens.accent,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  )
                : Row(
                    key: const ValueKey('times'),
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(_formatDuration(shownPos), style: labelStyle),
                      Text(
                        '-${_formatDuration(duration - shownPos)}',
                        style: labelStyle,
                      ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}

/// Horizontal volume slider bracketed by speaker.min/speaker.max
/// glyphs — drives system volume via the volume_controller plugin so
/// the iPhone's hardware volume keys stay in sync with the slider.
class _VolumeRow extends StatefulWidget {
  const _VolumeRow();

  @override
  State<_VolumeRow> createState() => _VolumeRowState();
}

class _VolumeRowState extends State<_VolumeRow> {
  @override
  void initState() {
    super.initState();
    // Read the current system volume so the thumb starts in the right
    // place. We deliberately do NOT register volume_controller's listener
    // — it deactivates the shared AVAudioSession on teardown (stopping
    // SoLoud on collapse) and forces `.mixWithOthers` (dropping the
    // lock-screen now-playing widget). See [VolumeService].
    VolumeService.instance.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final dim = Colors.white.withValues(alpha: 0.55);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(Icons.volume_down_rounded, size: 20, color: dim),
        Expanded(
          child: ValueListenableBuilder<double>(
            valueListenable: VolumeService.instance.volume,
            builder: (context, volume, _) => SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: Colors.white.withValues(alpha: 0.75),
                inactiveTrackColor: Colors.white.withValues(alpha: 0.18),
                thumbColor: Colors.white,
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
              ),
              child: Slider(
                min: 0,
                max: 1,
                value: volume.clamp(0.0, 1.0),
                onChanged: VolumeService.instance.setVolume,
              ),
            ),
          ),
        ),
        Icon(Icons.volume_up_rounded, size: 22, color: dim),
      ],
    );
  }
}

/// Three equally-spaced glyph buttons — Lyrics · Connect · Queue.
/// Lyrics (left) toggles the inline lyrics surface; Connect (middle) opens
/// the Live Connect device picker; Queue (right) toggles the inline up-next
/// surface. Shuffle / repeat / infinity now live in the queue surface's
/// control strip, so they're no longer here.
class _ActionsRow extends ConsumerWidget {
  const _ActionsRow({
    required this.accent,
    required this.lyricsActive,
    required this.queueActive,
    required this.onToggleLyrics,
    required this.onToggleQueue,
  });

  final Color accent;
  final bool lyricsActive;
  final bool queueActive;
  final VoidCallback onToggleLyrics;
  final VoidCallback onToggleQueue;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dim = Colors.white.withValues(alpha: 0.72);
    final onAnother = ref.watch(
      connectServiceProvider.select((c) => c.activeRemote != null),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 38),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Lyrics (left) — Apple-Music-style quote-bubble glyph.
          _GlyphButton(
            icon: Icons.lyrics_rounded,
            size: 28,
            color: lyricsActive ? accent : dim,
            onTap: onToggleLyrics,
          ),
          // Connect (middle) — hand playback to / pull it from another device.
          _GlyphButton(
            icon: onAnother ? Icons.cast_connected : Icons.cast,
            size: 26,
            color: onAnother ? accent : dim,
            onTap: () => showConnectSheet(context),
          ),
          // Queue (right) — toggles the inline up-next surface.
          _GlyphButton(
            icon: Icons.queue_music_rounded,
            size: 28,
            color: queueActive ? accent : dim,
            onTap: onToggleQueue,
          ),
        ],
      ),
    );
  }
}

String _formatDuration(Duration d) {
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$m:$s';
}
