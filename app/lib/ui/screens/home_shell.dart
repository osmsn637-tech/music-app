import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/connect/providers.dart';
import '../../features/nav/content_navigator_scope.dart';
import '../../features/nav/nav_collapse_controller.dart';
import '../motion/fade_indexed_stack.dart';
import '../../features/player/now_playing_controller.dart';
import '../../features/player/player_expansion_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/expanding_player.dart';
import '../widgets/liquid_nav_bar.dart';
import '../widgets/profile_sheet.dart';
import '../widgets/stage_background.dart';
import 'ai_dj_screen.dart';
import 'home_screen.dart';
import 'home_shell_providers.dart';
import 'library_screen.dart';
import 'search_screen.dart';

/// Tab indices on [homeTabIndexProvider]. Kept stable: legacy callers
/// (Home's "Start Station" feature card, deep links into Search /
/// Library) still set the index directly, so reshuffling would break
/// them. Search is rendered as a separate button on the floating nav
/// rather than inside the tab pill — the indices don't reflect the
/// visual order anymore, only the IndexedStack page order.
const _kHomeTab = 0;
const _kFlackoTab = 1;
const _kSearchTab = 2;
const _kLibraryTab = 3;

/// The three slots that live inside the floating nav's tab pill, in
/// display order. The Search tab lives outside the pill (rendered as a
/// separate button), so it's intentionally absent here.
const _kPillTabIndices = [_kHomeTab, _kFlackoTab, _kLibraryTab];

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  static const _pillTabs = [
    NavTabSpec(
      icon: Icons.home_outlined,
      activeIcon: Icons.home_rounded,
      label: 'Home',
    ),
    NavTabSpec(
      icon: Icons.auto_awesome_outlined,
      activeIcon: Icons.auto_awesome,
      label: 'Flacko',
      accent: true,
    ),
    NavTabSpec(
      icon: Icons.library_music_outlined,
      activeIcon: Icons.library_music_rounded,
      label: 'Library',
    ),
  ];

  static const _searchTab = NavTabSpec(
    icon: Icons.search,
    activeIcon: Icons.search,
    label: 'Search',
  );

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell>
    with SingleTickerProviderStateMixin {
  static const _pages = <Widget>[
    HomeScreen(),
    AiDjScreen(),
    SearchScreen(),
    LibraryScreen(),
  ];

  late final NavCollapseController _navCollapse;

  /// True once the list has settled at the very top while collapsed. The
  /// nav doesn't unwind the instant it reaches the top — it arms here, and
  /// the *next* upward swipe at the top is what actually expands it.
  bool _topArmed = false;

  /// Inner Navigator for the content area. Detail pages (album/artist/
  /// playlist) push HERE rather than on the root navigator, so the floating
  /// nav bar + mini player (later siblings in the body Stack) keep painting
  /// over them and stay usable on every browse page.
  final GlobalKey<NavigatorState> _contentNavKey = GlobalKey<NavigatorState>();

  /// True whenever the inner Navigator has a route above its root. Drives the
  /// back-button priority; kept fresh by [_innerNavObserver].
  final ValueNotifier<bool> _hasInnerRoute = ValueNotifier<bool>(false);
  late final _InnerNavObserver _innerNavObserver;

  @override
  void initState() {
    super.initState();
    _navCollapse = NavCollapseController(vsync: this);
    _innerNavObserver = _InnerNavObserver(_syncInnerDepth);
    // Restore the previous session (song + queue + position), staged
    // paused, so the app comes up where the user left off.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(nowPlayingProvider.notifier).restoreSession();
      }
    });
  }

  void _syncInnerDepth() {
    // ValueNotifier no-ops when the value is unchanged, so the initial root
    // push (false → false) can't trip a setState-during-build.
    _hasInnerRoute.value = _contentNavKey.currentState?.canPop() ?? false;
  }

  @override
  void dispose() {
    _hasInnerRoute.dispose();
    _navCollapse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasNowPlaying = ref.watch(nowPlayingProvider) != null;
    final index = ref.watch(homeTabIndexProvider);
    // Keep the Live Connect socket alive so this phone can be handed playback.
    ref.watch(connectServiceProvider.notifier);

    // Map the home-shell tab index → pill slot (-1 when on Search, which
    // doesn't live in the pill).
    final pillIndex = _kPillTabIndices.indexOf(index);
    final searchActive = index == _kSearchTab;

    void selectPillSlot(int slot) {
      // Tapping a tab lands on its root — drop any open detail page first.
      _contentNavKey.currentState?.popUntil((r) => r.isFirst);
      final target = _kPillTabIndices[slot];
      ref.read(homeTabIndexProvider.notifier).state = target;
      _navCollapse.expand();
    }

    void selectSearch() {
      _contentNavKey.currentState?.popUntil((r) => r.isFirst);
      ref.read(homeTabIndexProvider.notifier).state = _kSearchTab;
      _navCollapse.expand();
    }

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
          // here.
          Positioned.fill(
            child: _OffstageWhenPlayerCovered(
              child: Material(
                type: MaterialType.transparency,
                // Inner Navigator: the tabs are its root route; detail pages
                // push on top WITHIN this content area, while the nav + mini
                // player (later siblings below) keep painting over them.
                child: Navigator(
                  key: _contentNavKey,
                  observers: [_innerNavObserver],
                  onGenerateRoute: (settings) => MaterialPageRoute(
                    settings: settings,
                    builder: (_) =>
                        _TabHost(pages: _pages, onScroll: _handleScroll),
                  ),
                ),
              ),
            ),
          ),
          // Soft top frost so tab content dissolves under the status bar /
          // profile button instead of hard-cutting. Pointer-transparent.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: MediaQuery.of(context).padding.top + 56,
            child: IgnorePointer(
              child: ClipRect(
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),
          // Top-right profile button. Fades with the nav collapse so a
          // fully scrolled feed reads cleanly.
          Positioned(
            top: MediaQuery.of(context).padding.top + 12,
            right: 16,
            child: AnimatedBuilder(
              animation: _navCollapse.animation,
              builder: (context, child) {
                final opacity = (1.0 - _navCollapse.value * 1.4).clamp(
                  0.0,
                  1.0,
                );
                return Opacity(
                  opacity: opacity,
                  child: IgnorePointer(ignoring: opacity < 0.05, child: child),
                );
              },
              child: _ProfileButton(),
            ),
          ),
          // Floating nav — tab pill + separate search button.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: LiquidNavBar(
              tabs: HomeShell._pillTabs,
              activePillIndex: pillIndex,
              onTabSelected: selectPillSlot,
              search: HomeShell._searchTab,
              searchActive: searchActive,
              onSearch: selectSearch,
              onExpandRequest: _navCollapse.expand,
            ),
          ),
          // Unified mini/full player. Sits on top of everything in
          // the home shell so the full-form fully covers the nav at
          // e=1, while the mini-form lerps between its at-rest row
          // and the inline slot beside the tab pill / search button.
          // Mini player fades + rises in on the first song (and sinks out
          // when playback clears). Keyed on presence only, so a song change
          // while it's already visible never re-animates it.
          Positioned.fill(
            child: AnimatedSwitcher(
              duration: LumenTokens.mBase,
              switchInCurve: LumenTokens.lumenDecelerate,
              switchOutCurve: LumenTokens.lumenAccelerate,
              transitionBuilder: (child, anim) => FadeTransition(
                opacity: anim,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 0.06),
                    end: Offset.zero,
                  ).animate(anim),
                  child: child,
                ),
              ),
              child: hasNowPlaying
                  ? const ExpandingPlayer(key: ValueKey('player'))
                  : const SizedBox.shrink(key: ValueKey('noplayer')),
            ),
          ),
        ],
      ),
    );

    final shell = StageBackground(child: scaffold);

    // Hosts the AnimationController behind PlayerExpansionScope.of(...)
    // / .read(...) for the entire subtree, and wraps it in the nav-
    // collapse scope so the mini-player and the nav share one source
    // of truth for the collapsed↔expanded morph.
    return NavCollapseScope(
      controller: _navCollapse,
      child: PlayerExpansionScope(
        child: ContentNavigatorScope(
          navKey: _contentNavKey,
          child: _ShellBackHandler(
            tabIndex: index,
            contentNavKey: _contentNavKey,
            hasInnerRoute: _hasInnerRoute,
            onGoHome: () =>
                ref.read(homeTabIndexProvider.notifier).state = _kHomeTab,
            child: shell,
          ),
        ),
      ),
    );
  }

  /// Scroll-driven collapse. Direction.reverse (user is scrolling down,
  /// revealing more content) collapses the nav into the single-row inline
  /// layout. It then *stays* collapsed through upward scrolling — and even
  /// after reaching the top it does NOT unwind on that same gesture. Hitting
  /// the top only *arms* it; the next upward swipe at the top is what expands
  /// it back out. The Search tab is exempt — its pill has no active slot to
  /// anchor a collapse around, so we leave the nav at rest there.
  bool _handleScroll(ScrollNotification n) {
    final tabIndex = ref.read(homeTabIndexProvider);
    if (!_kPillTabIndices.contains(tabIndex)) return false;

    final atTop = n.metrics.pixels <= 12;

    if (_navCollapse.isCollapsed) {
      if (atTop) {
        // The gesture that carried us to the top ending is what arms it —
        // so the unwind needs a fresh swipe, not the touch that hit the top.
        if (n is ScrollEndNotification) {
          _topArmed = true;
        } else if (_topArmed &&
            n is UserScrollNotification &&
            n.direction == ScrollDirection.forward) {
          _navCollapse.expand();
          _topArmed = false;
        }
      } else {
        // Scrolled away from the top → disarm.
        _topArmed = false;
      }
    } else {
      _topArmed = false;
    }

    if (n is UserScrollNotification) {
      if (n.direction == ScrollDirection.reverse && !_navCollapse.isCollapsed) {
        if (n.metrics.maxScrollExtent - n.metrics.pixels > 80) {
          _navCollapse.collapse();
        }
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
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
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
/// Cases intercepted, in priority order:
///  1. **Player expanded** — back collapses the player.
///  2. **Inner detail page open** — back pops the inner content Navigator
///     (album/artist/playlist), keeping the nav + mini player.
///  3. **Non-home tab active** — back navigates to tab 0 (Home).
class _ShellBackHandler extends StatefulWidget {
  const _ShellBackHandler({
    required this.tabIndex,
    required this.contentNavKey,
    required this.hasInnerRoute,
    required this.onGoHome,
    required this.child,
  });

  final int tabIndex;
  final GlobalKey<NavigatorState> contentNavKey;
  final ValueListenable<bool> hasInnerRoute;
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
  void initState() {
    super.initState();
    widget.hasInnerRoute.addListener(_onInnerRouteChanged);
  }

  void _onInnerRouteChanged() {
    // Keep canPop fresh as the inner depth crosses 0↔1.
    if (mounted) {
      setState(() {});
    }
  }

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
    widget.hasInnerRoute.removeListener(_onInnerRouteChanged);
    _expansion?.removeListener(_onExpansionChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final onHomeTab = widget.tabIndex == _kHomeTab;
    final hasInner = widget.hasInnerRoute.value;
    return PopScope(
      canPop: onHomeTab && !_playerExpanded && !hasInner,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_playerExpanded) {
          _expansion?.collapse();
        } else if (hasInner) {
          widget.contentNavKey.currentState?.maybePop();
        } else if (!onHomeTab) {
          widget.onGoHome();
        }
      },
      child: widget.child,
    );
  }
}

/// The inner Navigator's root route — the tab pages. A ConsumerWidget so it
/// rebuilds on tab change (watching [homeTabIndexProvider]) WITHOUT
/// regenerating the route. The scroll listener is scoped HERE rather than
/// around the whole inner Navigator, so only tab-page scrolls drive the nav
/// collapse — detail-page scrolls live in sibling routes and never reach it.
class _TabHost extends ConsumerWidget {
  const _TabHost({required this.pages, required this.onScroll});

  final List<Widget> pages;
  final bool Function(ScrollNotification) onScroll;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final index = ref.watch(homeTabIndexProvider);
    return NotificationListener<ScrollNotification>(
      onNotification: onScroll,
      child: FadeIndexedStack(index: index, children: pages),
    );
  }
}

/// Watches the inner Navigator's depth so the shell can keep [_hasInnerRoute]
/// in sync for the back-button priority.
class _InnerNavObserver extends NavigatorObserver {
  _InnerNavObserver(this._onChanged);
  final VoidCallback _onChanged;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _onChanged();
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _onChanged();
  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _onChanged();
  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      _onChanged();
}
