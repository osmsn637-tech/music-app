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
  bool _queueOpen = false;

  void _toggleQueue() {
    setState(() => _queueOpen = !_queueOpen);
    WindowMode.setQueueOpen(_queueOpen);
  }

  @override
  Widget build(BuildContext context) {
    final song = ref.watch(nowPlayingProvider);
    final playing =
        ref.watch(playerStateStreamProvider).valueOrNull?.playing ?? false;
    final np = ref.read(nowPlayingProvider.notifier);

    // Cover ⇄ lyrics pager. Flexible (not a fixed height) so it can NEVER
    // overflow the window — macOS reserves ~31px we don't control — and just
    // shrinks if short. A smaller fixed square when the queue is open.
    final pager = _MiniPager(
      song: song,
      onRestore: () => WindowMode.exitMini(ref),
    );

    return Scaffold(
      backgroundColor: const Color(0xFF0B0B0E),
      body: Column(
        children: [
          if (_queueOpen)
            SizedBox(height: 200, child: pager)
          else
            Expanded(child: pager),
          // The cover is a swipe surface now (swipe LEFT for lyrics), so
          // window-dragging moves to this strip — drag the progress/controls
          // area to move the window. Buttons inside still tap normally.
          DragToMoveArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const _MiniProgressBar(),
                _MiniControls(
                  song: song,
                  playing: playing,
                  controller: np,
                  queueOpen: _queueOpen,
                  onToggleQueue: _toggleQueue,
                ),
              ],
            ),
          ),
          if (_queueOpen) ...[
            const Divider(height: 1),
            Expanded(child: _MiniQueue(controller: np)),
          ],
        ],
      ),
    );
  }
}

/// The cover ⇄ lyrics pager. Page 0 is the full square album cover, page 1 is
/// the synced lyrics; swipe horizontally to flip. The restore button and a
/// 2-dot page indicator overlay both pages.
class _MiniPager extends StatefulWidget {
  const _MiniPager({required this.song, required this.onRestore});

  final SongRow? song;
  final VoidCallback onRestore;

  @override
  State<_MiniPager> createState() => _MiniPagerState();
}

class _MiniPagerState extends State<_MiniPager> {
  final _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // The cover doubles as a window-drag surface (one-finger click-drag
        // moves the window) AND a lyrics pager. To keep those from fighting,
        // ONLY two-finger trackpad swipes page to lyrics — the PageView's
        // drag devices are restricted to `trackpad` (pan-zoom events), while
        // [_WindowMoveArea] claims one-finger mouse/touch drags for moving the
        // window. The two device kinds are disjoint, so there's no arena clash.
        _WindowMoveArea(
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(context).copyWith(
              dragDevices: const {PointerDeviceKind.trackpad},
            ),
            child: PageView(
              controller: _controller,
              onPageChanged: (p) => setState(() => _page = p),
              children: [
                // Page 0 — full square cover (uncropped via AspectRatio).
                Center(
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: _ArtFill(
                      path: widget.song?.localArtworkPath,
                      seed: widget.song?.id ?? 'idle',
                    ),
                  ),
                ),
                // Page 1 — synced lyrics for the current song.
                const InlineLyrics(),
              ],
            ),
          ),
        ),
        // Restore-to-full-app, on a dark disc so it reads on bright covers.
        Positioned(
          top: 8,
          right: 8,
          child: GestureDetector(
            onTap: widget.onRestore,
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
        // Tap the dots to flip cover ⇄ lyrics. Gives mouse-only users (no
        // two-finger trackpad swipe) a way to reach the lyrics page; the
        // trackpad swipe via the PageView keeps working too.
        Positioned(
          left: 0,
          right: 0,
          bottom: 6,
          child: Center(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _controller.animateToPage(
                _page == 0 ? 1 : 0,
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeOutCubic,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: _PageDots(count: 2, active: _page),
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

/// A pill-style page indicator (the active dot elongates).
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
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: i == active ? 16 : 6,
            height: 6,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: i == active ? 0.9 : 0.4),
              borderRadius: BorderRadius.circular(3),
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
    required this.queueOpen,
    required this.onToggleQueue,
  });

  final SongRow? song;
  final bool playing;
  final NowPlayingController controller;
  final bool queueOpen;
  final VoidCallback onToggleQueue;

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
                // Queue toggle on the right.
                Align(
                  alignment: Alignment.centerRight,
                  child: _MiniIcon(
                    Icons.queue_music_rounded,
                    size: 20,
                    active: queueOpen,
                    onTap: onToggleQueue,
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
  const _MiniQueue({required this.controller});

  final NowPlayingController controller;

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
          padding: const EdgeInsets.symmetric(vertical: 4),
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
