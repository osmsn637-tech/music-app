import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/player/now_playing_controller.dart';
import '../../features/player/player_expansion_controller.dart';
import '../widgets/expanding_player.dart';
import '../widgets/glass_tab_bar.dart';
import '../widgets/profile_sheet.dart';
import '../widgets/stage_background.dart';
import 'ai_dj_screen.dart';
import 'home_screen.dart';
import 'home_shell_providers.dart';
import 'library_screen.dart';
import 'search_screen.dart';

/// Tab-bar visual height (excluding the bottom safe-area inset). Matches
/// the GlassTabBar's intrinsic height — kept here as a constant because
/// the ExpandingPlayer needs to know it to compute the mini rect's top.
const double kHomeShellTabBarHeight = 66;

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
              child: _OffstageWhenPlayerCovered(
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
            // Sticky tab bar — always visible regardless of scroll
            // direction. The expanding player overlays on top of it
            // when the user opens the player, so the tab bar can
            // safely stay anchored here.
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: GlassTabBar(
                tabs: HomeShell._tabs,
                activeIndex: index,
                onChanged: (i) =>
                    ref.read(homeTabIndexProvider.notifier).state = i,
              ),
            ),
            // Unified mini/full player. Sits on top of everything in
            // the home shell so the full-form fully covers the tab
            // bar at e=1, while the mini-form (e=0) floats just above
            // the tab bar. Owns its own gesture handling for
            // tap-to-expand and drag-to-collapse.
            if (hasNowPlaying)
              Positioned.fill(
                child: ExpandingPlayer(
                  tabBarHeight: kHomeShellTabBarHeight,
                ),
              ),
          ],
        ),
      );

    final shell = StageBackground(child: scaffold);

    // Hosts the AnimationController behind PlayerExpansionScope.of(...) /
    // .read(...) calls from the entire subtree. Wrapping at this level
    // means every tab (Home, Search, Library, Playlist detail, AI DJ)
    // can call `.expand()` to open the player without pushing a route.
    //
    // _ShellBackHandler sits inside the scope so it can subscribe to the
    // expansion controller and provide a fully reactive PopScope — one
    // that updates canPop both when Riverpod providers change (tab index)
    // AND when the animation crosses the expanded/mini threshold.
    return PlayerExpansionScope(
      child: _ShellBackHandler(
        tabIndex: index,
        onGoHome: () =>
            ref.read(homeTabIndexProvider.notifier).state = 0,
        child: shell,
      ),
    );
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

/// Wraps its [child] in an [Offstage] that flips on whenever the
/// player's expansion controller is at e ≥ 0.97 — i.e. the player is
/// fully covering the screen. The covered subtree (home content + the
/// static StageBackground layer) keeps its widget state but stops
/// painting and stops accepting pointer events, so the GPU and CPU
/// don't waste cycles on a screen the user can't see.
///
/// Listens directly to the controller (one cheap listener), flips the
/// [_covered] bool via setState only when the threshold is crossed —
/// 2 rebuilds per full expand/collapse, not 60 per second.
class _OffstageWhenPlayerCovered extends StatefulWidget {
  const _OffstageWhenPlayerCovered({required this.child});

  final Widget child;

  @override
  State<_OffstageWhenPlayerCovered> createState() =>
      _OffstageWhenPlayerCoveredState();
}

class _OffstageWhenPlayerCoveredState
    extends State<_OffstageWhenPlayerCovered> {
  PlayerExpansionController? _expansion;
  bool _covered = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final exp = PlayerExpansionScope.read(context);
    if (!identical(exp, _expansion)) {
      _expansion?.removeListener(_onExpansionChanged);
      _expansion = exp;
      _expansion!.addListener(_onExpansionChanged);
      _onExpansionChanged();
    }
  }

  void _onExpansionChanged() {
    final next = (_expansion?.value ?? 0) >= 0.97;
    if (next == _covered) return;
    setState(() => _covered = next);
  }

  @override
  void dispose() {
    _expansion?.removeListener(_onExpansionChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Offstage(offstage: _covered, child: widget.child);
  }
}

/// Handles the system back button for the home shell by wrapping its
/// [child] in a [PopScope].
///
/// Two cases are intercepted (in priority order):
///  1. **Player expanded** — back collapses the player; stays on the
///     current tab.
///  2. **Non-home tab active** — back navigates to tab 0 (Home).
///
/// When on the Home tab with the player mini or absent the pop is
/// allowed through so the app can exit normally.
///
/// Subscribes to [PlayerExpansionController] directly (same pattern as
/// [_OffstageWhenPlayerCovered]) so [canPop] updates at the expand/
/// collapse threshold rather than waiting for a Riverpod rebuild.
class _ShellBackHandler extends StatefulWidget {
  const _ShellBackHandler({
    required this.tabIndex,
    required this.onGoHome,
    required this.child,
  });

  final int tabIndex;
  final VoidCallback onGoHome;
  final Widget child;

  @override
  State<_ShellBackHandler> createState() => _ShellBackHandlerState();
}

class _ShellBackHandlerState extends State<_ShellBackHandler> {
  PlayerExpansionController? _expansion;

  /// True when expansion value ≥ 0.05 — the same threshold used
  /// previously in the ExpandingPlayer's PopScope.
  bool _playerExpanded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final exp = PlayerExpansionScope.read(context);
    if (!identical(exp, _expansion)) {
      _expansion?.removeListener(_onExpansionChanged);
      _expansion = exp;
      _expansion!.addListener(_onExpansionChanged);
      _onExpansionChanged();
    }
  }

  void _onExpansionChanged() {
    final next = (_expansion?.value ?? 0) >= 0.05;
    if (next == _playerExpanded) return;
    setState(() => _playerExpanded = next);
  }

  @override
  void dispose() {
    _expansion?.removeListener(_onExpansionChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final onHomeTab = widget.tabIndex == 0;
    return PopScope(
      // Allow the app to exit only when the player is mini/absent AND
      // the Home tab is already active — every other state intercepts
      // back to do the right thing first.
      canPop: onHomeTab && !_playerExpanded,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_playerExpanded) {
          // Priority 1: collapse the full-screen player.
          _expansion?.collapse();
        } else if (!onHomeTab) {
          // Priority 2: return to the Home tab.
          widget.onGoHome();
        }
      },
      child: widget.child,
    );
  }
}
