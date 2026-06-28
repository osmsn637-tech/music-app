import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../../data/database/app_database.dart';
import '../../features/connect/providers.dart';
import '../../features/player/now_playing_controller.dart';
import '../../features/player/providers.dart';
import '../../features/window/window_mode.dart';
import '../theme/app_theme.dart';
import '../widgets/album_art.dart';
import '../widgets/connect_sheet.dart';
import '../widgets/glass_kit.dart';
import 'lyrics_screen.dart' show InlineLyrics;

/// Floating macOS mini-player. The full square album cover sits on top; the
/// song name and centered transport (with the queue toggle) sit BELOW it on a
/// dark strip, so the artwork is never obscured. The queue button grows the
/// window to reveal the up-next list; the restore button (top-right of the
/// cover) brings the full app back. Drag the cover to move the window.
class MacMiniPlayer extends ConsumerStatefulWidget {
  const MacMiniPlayer({super.key});

  @override
  ConsumerState<MacMiniPlayer> createState() => _MacMiniPlayerState();
}

class _MacMiniPlayerState extends ConsumerState<MacMiniPlayer> {
  // Infinite pager — cover (i%3==0) → lyrics (i%3==1) → queue (i%3==2) → loop.
  // Start at a high multiple of 3 so it can swipe both directions forever.
  static const int _start = 3000;
  late final PageController _controller;
  int _page = _start;

  @override
  void initState() {
    super.initState();
    _controller = PageController(initialPage: _start);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Animate forward to the next page of [type] (0 cover, 1 lyrics, 2 queue).
  void _goToType(int type) {
    final base = _page - (_page % 3);
    var target = base + type;
    if (target < _page) target += 3; // always go forward, never snap back
    if (target == _page) return;
    _controller.animateToPage(
      target,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final song = ref.watch(nowPlayingProvider);
    final playing =
        ref.watch(playerStateStreamProvider).valueOrNull?.playing ?? false;
    final np = ref.read(nowPlayingProvider.notifier);

    return Scaffold(
      backgroundColor: const Color(0xFF0B0B0E),
      body: Column(
        children: [
          Expanded(
            child: _MiniPager(
              song: song,
              controller: _controller,
              page: _page,
              onPageChanged: (p) => setState(() => _page = p),
              onRestore: () => WindowMode.exitMini(ref),
            ),
          ),
          // Drag the controls strip to move the window. Buttons still tap.
          DragToMoveArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const _MiniProgressBar(),
                _MiniControls(
                  song: song,
                  playing: playing,
                  controller: np,
                  queueActive: _page % 3 == 2,
                  // Toggle: on the queue page, tapping the button takes
                  // you back to the cover; otherwise it opens the queue.
                  onQueue: () => _goToType(_page % 3 == 2 ? 0 : 2),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Infinite cover ⇄ lyrics ⇄ queue pager. `index % 3` selects the page and it
/// loops forever both directions. The restore button and a tappable 3-dot
/// indicator overlay every page.
class _MiniPager extends StatelessWidget {
  const _MiniPager({
    required this.song,
    required this.controller,
    required this.page,
    required this.onPageChanged,
    required this.onRestore,
  });

  final SongRow? song;
  final PageController controller;
  final int page;
  final ValueChanged<int> onPageChanged;
  final VoidCallback onRestore;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // One-finger click-drag moves the window ([_WindowMoveArea]); only
        // two-finger trackpad swipes page (dragDevices = trackpad). The two
        // device kinds are disjoint, so there's no gesture-arena clash.
        _WindowMoveArea(
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(
              context,
            ).copyWith(dragDevices: const {PointerDeviceKind.trackpad}),
            child: PageView.builder(
              controller: controller,
              onPageChanged: onPageChanged,
              itemBuilder: (context, index) {
                switch (index % 3) {
                  case 0: // cover (uncropped via AspectRatio)
                    return Center(
                      child: AspectRatio(
                        aspectRatio: 1,
                        child: _ArtFill(
                          path: song?.localArtworkPath,
                          seed: song?.id ?? 'idle',
                        ),
                      ),
                    );
                  case 1: // synced lyrics
                    return const InlineLyrics();
                  default: // up-next queue
                    return const _MiniQueuePage();
                }
              },
            ),
          ),
        ),
        // Restore-to-full-app, on a dark disc so it reads on bright covers.
        Positioned(
          top: 8,
          right: 8,
          child: GestureDetector(
            onTap: onRestore,
            child: Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.4),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.open_in_full_rounded,
                size: 14,
                color: Colors.white,
              ),
            ),
          ),
        ),
        // Tap the dots to advance to the next page (also gives mouse-only users
        // a way to page without a two-finger swipe).
        Positioned(
          left: 0,
          right: 0,
          bottom: 6,
          child: Center(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => controller.animateToPage(
                page + 1,
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeOutCubic,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: _PageDots(count: 3, active: page % 3),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

const double _kMiniQueueHeaderH = 32;

/// The up-next queue rendered as a pager page (header + scrollable list).
class _MiniQueuePage extends ConsumerWidget {
  const _MiniQueuePage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(nowPlayingProvider.notifier);
    return Stack(
      children: [
        Positioned.fill(
          child: _MiniQueue(
            controller: controller,
            topInset: _kMiniQueueHeaderH,
          ),
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: ClipRect(
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: Container(
                height: _kMiniQueueHeaderH,
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: const BoxDecoration(
                  color: Color(0x0AFFFFFF),
                  border: Border(bottom: BorderSide(color: Color(0x14FFFFFF))),
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.queue_music_rounded,
                      size: 14,
                      color: Colors.white70,
                    ),
                    SizedBox(width: 6),
                    Text(
                      'Up Next',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Moves the window on a one-finger click-drag — mouse, single-finger
/// trackpad click-drag, or touch — by handing the drag to the OS via
/// [WindowManager.startDragging]. Two-finger trackpad swipes arrive as
/// pan-zoom events on [PointerDeviceKind.trackpad], which this recognizer
/// deliberately excludes, so they fall through to the cover's PageView and
/// flip to lyrics instead of moving the window. The pan recognizer only
/// fires after the touch slop, so a plain click (e.g. the restore button)
/// never starts a drag.
class _WindowMoveArea extends StatelessWidget {
  const _WindowMoveArea({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return RawGestureDetector(
      behavior: HitTestBehavior.translucent,
      gestures: <Type, GestureRecognizerFactory>{
        PanGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<PanGestureRecognizer>(
              () => PanGestureRecognizer(
                supportedDevices: const {
                  PointerDeviceKind.mouse,
                  PointerDeviceKind.touch,
                  PointerDeviceKind.stylus,
                  PointerDeviceKind.unknown,
                },
              ),
              (recognizer) =>
                  recognizer.onStart = (_) => windowManager.startDragging(),
            ),
      },
      child: child,
    );
  }
}

/// Page indicator: the current page reads as a bigger round dot, the two
/// other pages as smaller flanking pills.
class _PageDots extends StatelessWidget {
  const _PageDots({required this.count, required this.active});

  final int count;
  final int active;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            // Active → a bigger circle (radius == half side); inactive →
            // a smaller, shorter pill.
            width: i == active ? 9 : 7,
            height: i == active ? 9 : 4,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: i == active ? 0.95 : 0.4),
              borderRadius: BorderRadius.circular(i == active ? 4.5 : 2),
            ),
          ),
      ],
    );
  }
}

/// The strip below the cover: centered song name, centered transport, and the
/// queue toggle pinned to the right of the transport row.
class _MiniControls extends ConsumerWidget {
  const _MiniControls({
    required this.song,
    required this.playing,
    required this.controller,
    required this.queueActive,
    required this.onQueue,
  });

  final SongRow? song;
  final bool playing;
  final NowPlayingController controller;
  final bool queueActive;
  final VoidCallback onQueue;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final onAnother = ref.watch(
      connectServiceProvider.select((c) => c.activeRemote != null),
    );
    return SizedBox(
      height: 120,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              song?.title ?? 'Nothing playing',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14.5,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              song?.artist ?? '—',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.66),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 12),
            // Transport centered; queue toggle on the right without shifting it.
            Stack(
              alignment: Alignment.center,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _MiniIcon(
                      Icons.skip_previous_rounded,
                      size: 26,
                      onTap: () => controller.previous(),
                    ),
                    const SizedBox(width: 10),
                    _MiniPlay(
                      playing: playing,
                      onTap: () =>
                          playing ? controller.pause() : controller.resume(),
                    ),
                    const SizedBox(width: 10),
                    _MiniIcon(
                      Icons.skip_next_rounded,
                      size: 26,
                      onTap: () => controller.next(),
                    ),
                  ],
                ),
                // Handoff (Live Connect) on the left — push/pull playback to
                // another device.
                Align(
                  alignment: Alignment.centerLeft,
                  child: _MiniIcon(
                    onAnother ? Icons.cast_connected : Icons.cast,
                    size: 20,
                    active: onAnother,
                    onTap: () => showConnectSheet(context),
                  ),
                ),
                // Queue button — jumps straight to the queue pager page.
                Align(
                  alignment: Alignment.centerRight,
                  child: _MiniIcon(
                    Icons.queue_music_rounded,
                    size: 20,
                    active: queueActive,
                    onTap: onQueue,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Album cover scaled to cover the (square) card, with the gradient fallback.
class _ArtFill extends StatelessWidget {
  const _ArtFill({required this.path, required this.seed});

  final String? path;
  final String seed;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final side = c.biggest.longestSide.isFinite
            ? c.biggest.longestSide
            : 300.0;
        return ClipRect(
          child: OverflowBox(
            minWidth: side,
            minHeight: side,
            maxWidth: side,
            maxHeight: side,
            child: AlbumArt(
              artworkPath: path,
              seed: seed,
              size: side,
              radius: 0,
            ),
          ),
        );
      },
    );
  }
}

class _MiniProgressBar extends ConsumerWidget {
  const _MiniProgressBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pos = ref.watch(playerPositionProvider).valueOrNull ?? Duration.zero;
    final dur = ref.watch(playerDurationProvider).valueOrNull ?? Duration.zero;
    final frac = dur.inMilliseconds <= 0
        ? 0.0
        : (pos.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0);
    return SizedBox(
      height: 3,
      child: Row(
        children: [
          Expanded(
            flex: (frac * 1000).round(),
            child: Container(color: LumenTokens.accent),
          ),
          Expanded(
            flex: 1000 - (frac * 1000).round(),
            child: Container(color: Colors.white.withValues(alpha: 0.10)),
          ),
        ],
      ),
    );
  }
}

class _MiniQueue extends StatelessWidget {
  const _MiniQueue({required this.controller, this.topInset = 0});

  final NowPlayingController controller;
  final double topInset;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<QueueView>(
      valueListenable: controller.queueView,
      builder: (context, view, _) {
        if (view.queue.isEmpty) {
          return Center(
            child: Text(
              'Queue is empty',
              style: TextStyle(
                color: LumenTokens.fgDimOf(context),
                fontSize: 12.5,
              ),
            ),
          );
        }
        return ListView.builder(
          padding: EdgeInsets.only(top: topInset + 4, bottom: 4),
          itemCount: view.queue.length,
          itemBuilder: (context, i) {
            final s = view.queue[i];
            final current = i == view.index;
            return Pressable(
              onTap: () => controller.jumpTo(i),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                child: Row(
                  children: [
                    AlbumArt(
                      artworkPath: s.localArtworkPath,
                      seed: s.id,
                      size: 30,
                      radius: 6,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        s.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: current
                              ? LumenTokens.accent
                              : LumenTokens.fg(context),
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (current)
                      const Icon(
                        Icons.equalizer_rounded,
                        size: 15,
                        color: LumenTokens.accent,
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _MiniPlay extends StatelessWidget {
  const _MiniPlay({required this.playing, required this.onTap});

  final bool playing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: const BoxDecoration(
          color: LumenTokens.accent,
          shape: BoxShape.circle,
        ),
        child: AnimatedSwitcher(
          duration: LumenTokens.mFast,
          transitionBuilder: (child, anim) => ScaleTransition(
            scale: Tween<double>(begin: 0.6, end: 1).animate(anim),
            child: FadeTransition(opacity: anim, child: child),
          ),
          child: Icon(
            playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
            key: ValueKey(playing),
            color: Colors.white,
            size: 24,
          ),
        ),
      ),
    );
  }
}

class _MiniIcon extends StatelessWidget {
  const _MiniIcon(
    this.icon, {
    required this.onTap,
    this.size = 20,
    this.active = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final double size;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Icon(
          icon,
          size: size,
          color: active ? LumenTokens.accent : Colors.white,
        ),
      ),
    );
  }
}
