import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/providers.dart';
import '../../features/player/now_playing_controller.dart';
import '../widgets/glass_tab_bar.dart';
import '../widgets/live_wallpaper.dart';
import '../widgets/mini_player.dart';
import '../widgets/profile_sheet.dart';
import '../widgets/stage_background.dart';
import 'ai_dj_screen.dart';
import 'home_screen.dart';
import 'home_shell_providers.dart';
import 'library_screen.dart';
import 'search_screen.dart';

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  static const _tabs = [
    TabSpec(
      icon: Icons.home_outlined,
      activeIcon: Icons.home_rounded,
      label: 'Home',
    ),
    TabSpec(
      icon: Icons.auto_awesome_outlined,
      activeIcon: Icons.auto_awesome,
      label: 'Flacko',
      accent: true,
    ),
    TabSpec(
      icon: Icons.search,
      activeIcon: Icons.search,
      label: 'Search',
    ),
    TabSpec(
      icon: Icons.library_music_outlined,
      activeIcon: Icons.library_music_rounded,
      label: 'Library',
    ),
  ];

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  static const _pages = <Widget>[
    HomeScreen(),
    AiDjScreen(),
    SearchScreen(),
    LibraryScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final hasNowPlaying = ref.watch(nowPlayingProvider) != null;
    final index = ref.watch(homeTabIndexProvider);
    final navVisible = ref.watch(navVisibleProvider);
    final liveWallpaper = ref.watch(liveWallpaperProvider);

    final scaffold = Scaffold(
        backgroundColor: Colors.transparent,
        extendBodyBehindAppBar: true,
        extendBody: true,
        body: Stack(
          children: [
            // Transparent Material wrapper around every tab body so each
            // screen — and every InkWell / IconButton / SongTile inside —
            // has a guaranteed Material ancestor regardless of what
            // BackdropFilters, Stacks, or Glass surfaces sit between them.
            //
            // IndexedStack instead of PageView: tab switching is now tap-
            // only (no swipe-between-tabs), so we don't need a Scrollable
            // here. Removing the PageView also removes a gesture-arena
            // participant that was competing with the inner ListView's
            // vertical drags — vertical scrolling inside any tab is
            // unblocked across the full body.
            Positioned.fill(
              child: Material(
                type: MaterialType.transparency,
                child: NotificationListener<ScrollNotification>(
                  onNotification: (n) =>
                      _handleScroll(ref, n, navVisible: navVisible),
                  child: IndexedStack(
                    index: index,
                    children: _pages,
                  ),
                ),
              ),
            ),
            // Top-right profile button overlay — also fades with the nav so
            // a fully scrolled feed is uninterrupted.
            Positioned(
              top: MediaQuery.of(context).padding.top + 12,
              right: 16,
              child: AnimatedOpacity(
                opacity: navVisible ? 1 : 0,
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOut,
                child: IgnorePointer(
                  ignoring: !navVisible,
                  child: _ProfileButton(),
                ),
              ),
            ),
            // Floating mini-player + glass tab bar. The mini-player is
            // always visible while a song is loaded — only the tab bar
            // collapses out on downward scroll, and the mini-player rides
            // the closing gap down to the bottom edge.
            Positioned(
              left: 0,
              right: 0,
              bottom: MediaQuery.of(context).padding.bottom,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (hasNowPlaying) const MiniPlayer(),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 260),
                    curve: Curves.easeOutCubic,
                    alignment: Alignment.topCenter,
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOut,
                      opacity: navVisible ? 1 : 0,
                      child: navVisible
                          ? GlassTabBar(
                              tabs: HomeShell._tabs,
                              activeIndex: index,
                              onChanged: (i) => ref
                                  .read(homeTabIndexProvider.notifier)
                                  .state = i,
                            )
                          : const SizedBox(width: double.infinity, height: 0),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

    return liveWallpaper
        ? LiveWallpaperBackground(child: scaffold)
        : StageBackground(child: scaffold);
  }

  bool _handleScroll(
    WidgetRef ref,
    ScrollNotification n, {
    required bool navVisible,
  }) {
    // Snap the bar back the moment we hit the top, so a quick flick to the
    // top doesn't leave the nav stranded off-screen.
    if (n.metrics.pixels <= 12 && !navVisible) {
      ref.read(navVisibleProvider.notifier).state = true;
      return false;
    }
    if (n is UserScrollNotification) {
      final dir = n.direction;
      if (dir == ScrollDirection.reverse && navVisible) {
        // Don't hide the bar when there's nothing to scroll into — it would
        // just leave the user with no way to switch tabs.
        if (n.metrics.maxScrollExtent - n.metrics.pixels > 80) {
          ref.read(navVisibleProvider.notifier).state = false;
        }
      } else if (dir == ScrollDirection.forward && !navVisible) {
        ref.read(navVisibleProvider.notifier).state = true;
      }
    }
    return false;
  }
}

class _ProfileButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: () => ProfileSheet.show(context),
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: 0.1),
            border:
                Border.all(color: Colors.white.withValues(alpha: 0.12)),
          ),
          child: const Icon(Icons.person_rounded, size: 20),
        ),
      ),
    );
  }
}
