import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/services/volume_service.dart';
import '../../data/database/app_database.dart';
import '../../features/automix/providers.dart';
import '../../features/ai_dj/providers.dart';
import '../../features/connect/providers.dart';
import '../../features/library/artist_image_resolver.dart';
import '../../features/library/detail_providers.dart';
import '../../features/library/home_providers.dart';
import '../../features/library/library_actions.dart';
import '../../features/library/providers.dart';
import '../../features/nav/content_navigator_scope.dart';
import '../../features/playlists/providers.dart';
import '../../features/player/now_playing_controller.dart';
import '../../features/player/playback_modes.dart';
import '../../features/player/player_expansion_controller.dart';
import '../../features/player/providers.dart';
import '../../features/window/window_mode.dart';
import '../motion/fade_indexed_stack.dart';
import '../motion/lumen_route.dart';
import '../theme/app_theme.dart';
import '../widgets/album_art.dart';
import '../widgets/bloom_background.dart';
import '../widgets/connect_sheet.dart';
import '../widgets/glass_kit.dart';
import 'ai_dj_screen.dart';
import 'entity_nav.dart';
import 'home_screen.dart';
import 'home_shell_providers.dart';
import 'library_screen.dart';
import 'lyrics_screen.dart' show InlineLyrics;
import 'mac_mini_player.dart';
import 'playlist_detail_screen.dart';
import 'search_screen.dart';
import 'settings_screen.dart';
import 'sync_screen.dart';

// ─── Spotify palette ─────────────────────────────────────────────────────
// Local to the desktop shell — the rest of the app keeps its pink "Lumen"
// theme; only this Spotify-clone chrome uses these.
const _spBg = Color(0xFF000000); // window bg + gaps + bottom bar
const _spPanel = Color(0xFF121212); // the three rounded panels
const _spChip = Color(0xFF232323); // filter chip resting
const _spGreen = Color(0xFF1ED760); // active toggles, playing title
const _spText = Color(0xFFFFFFFF);
const _spMuted = Color(0xFFB3B3B3);
const _spTrack = Color(0x3DFFFFFF); // slider inactive track (~24% white)

/// Whether the desktop lyrics panel (overlaying the main content pane) is open.
final desktopLyricsOpenProvider = StateProvider<bool>((_) => false);

/// Whether the right-hand "Now Playing" panel is open.
final nowPlayingPanelOpenProvider = StateProvider<bool>((_) => false);

/// Whether the right panel shows the play queue instead (mutually exclusive
/// with the now-playing panel — Spotify shows the queue inline, not a popup).
final desktopQueueOpenProvider = StateProvider<bool>((_) => false);

/// Which "Your Library" filter the left rail shows: 0 = Songs (default),
/// 1 = Playlists, 2 = Albums, 3 = Artists.
final libraryFilterProvider = StateProvider<int>((_) => 0);

/// Assigned by [_MainPanelState] so [_go] (and any tab switch) can pop the
/// inner content stack back to the tab root — otherwise tapping a tab you're
/// already on, with a detail page open, would leave the stale page up.
GlobalKey<NavigatorState>? _desktopContentNav;

void _go(WidgetRef ref, int index) {
  _desktopContentNav?.currentState?.popUntil((r) => r.isFirst);
  ref.read(homeTabIndexProvider.notifier).state = index;
}

/// True while a text field (search / DJ prompt / dialog) holds focus, so the
/// shell's single-key media shortcuts yield to typing. [GlassField] already
/// swallows the conflicting keys via a descendant Shortcuts; this is a cheap
/// second line of defense for any other focused editable.
bool get _isTyping {
  final ctx = FocusManager.instance.primaryFocus?.context;
  if (ctx == null) return false;
  return ctx.widget is EditableText ||
      ctx.findAncestorWidgetOfExactType<EditableText>() != null;
}

/// Live favorite state for [song], read from the reactive [allSongsProvider]
/// (the now-playing SongRow's `isFavorite` snapshot goes stale after a toggle).
bool _isFav(WidgetRef ref, SongRow song) {
  final live = ref.watch(allSongsProvider).valueOrNull;
  final match = live?.cast<SongRow?>().firstWhere(
    (s) => s?.id == song.id,
    orElse: () => null,
  );
  return (match ?? song).isFavorite == 1;
}

/// Opens the play queue in the right panel (and closes the now-playing panel).
void _openQueuePanel(WidgetRef ref) {
  ref.read(nowPlayingPanelOpenProvider.notifier).state = false;
  ref.read(desktopQueueOpenProvider.notifier).state = true;
}

/// Like/save toggle — filled green when saved, outline otherwise. Live state
/// comes from [allSongsProvider] (see [_isFav]).
class _HeartButton extends ConsumerWidget {
  const _HeartButton({required this.song, this.size = 18});

  final SongRow song;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fav = _isFav(ref, song);
    return Pressable(
      onTap: () => ref.read(libraryActionsProvider).toggleFavorite(song),
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Icon(
          fav ? Icons.favorite : Icons.favorite_border,
          size: size,
          color: fav ? _spGreen : _spMuted,
        ),
      ),
    );
  }
}

/// Desktop-native shell, styled as a Spotify-desktop clone: a pure-black
/// frameless window holding three rounded `#121212` panels (Your Library
/// rail · main content · Now Playing) with 8px gaps, a custom draggable top
/// bar (Home + search + actions), and a full-width now-playing bar pinned to
/// the bottom. Chosen on macOS / Windows / Linux; the phone [HomeShell] still
/// drives iOS / Android.
class DesktopShell extends ConsumerStatefulWidget {
  const DesktopShell({super.key});

  /// Same page set + order as the phone shell so [homeTabIndexProvider]
  /// (0 = Home, 1 = Flacko, 2 = Search, 3 = Library) maps identically.
  static const _pages = <Widget>[
    HomeScreen(),
    AiDjScreen(),
    SearchScreen(),
    LibraryScreen(),
  ];

  @override
  ConsumerState<DesktopShell> createState() => _DesktopShellState();
}

class _DesktopShellState extends ConsumerState<DesktopShell> {
  // Inner Navigator for the main content panel. Album / artist / playlist
  // detail pages push HERE so the sidebar, top bar, and bottom player bar stay
  // put instead of the page full-covering the window.
  final GlobalKey<NavigatorState> _contentNavKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    // Seed the volume baseline from the real system volume so the ↑/↓
    // shortcuts bump from the actual level even before the player bar's
    // _VolumeControl has mounted.
    VolumeService.instance.refresh();
    _desktopContentNav = _contentNavKey;
  }

  @override
  void dispose() {
    if (_desktopContentNav == _contentNavKey) _desktopContentNav = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Auto-open the right "Now Playing" panel when a new song starts — unless
    // the queue panel is deliberately open (they share the slot, so don't yank
    // that away).
    ref.listen<SongRow?>(nowPlayingProvider, (prev, next) {
      if (next != null &&
          next.id != prev?.id &&
          !ref.read(desktopQueueOpenProvider)) {
        ref.read(nowPlayingPanelOpenProvider.notifier).state = true;
      }
    });

    final hasNowPlaying = ref.watch(nowPlayingProvider) != null;
    final lyricsOpen = ref.watch(desktopLyricsOpenProvider) && hasNowPlaying;
    final queueOpen = ref.watch(desktopQueueOpenProvider) && hasNowPlaying;
    // Queue takes the right panel over now-playing when both are toggled.
    final panelOpen =
        ref.watch(nowPlayingPanelOpenProvider) && hasNowPlaying && !queueOpen;
    // Keep the Live Connect socket alive app-wide. .notifier = no rebuild storm.
    ref.watch(connectServiceProvider.notifier);

    final miniMode = ref.watch(miniModeProvider);

    // _ShortcutHost wraps BOTH modes so the keyboard shortcuts (incl. ⌘M to
    // toggle the mini-player) fire from the mini window too, not just the
    // full shell.
    return _ShortcutHost(
      child: miniMode
          ? const MacMiniPlayer()
          // PlayerExpansionScope so the feature screens' `...expand()` calls
          // resolve (harmless here — the player lives in the bottom bar).
          : PlayerExpansionScope(
              // Inner content Navigator shared with the sidebar / player bar
              // (which sit outside the panel) so their album/artist links push
              // INTO the panel. overlaysContent:false — the bar lays out below
              // the panel here, so pushed pages don't reserve a bottom gap.
              child: ContentNavigatorScope(
                navKey: _contentNavKey,
                overlaysContent: false,
                // Material ancestor — without it every Text in the top bar /
                // sidebar / player bar gets Flutter's yellow "no Material"
                // debug underline.
                child: Material(
                  color: _spBg,
                  child: Column(
                    children: [
                      const _TopBar(),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const _LibraryPanel(),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _MainPanel(
                                  navKey: _contentNavKey,
                                  lyricsOpen: lyricsOpen,
                                ),
                              ),
                              if (queueOpen) ...[
                                const SizedBox(width: 8),
                                const _QueueRightPanel(),
                              ] else if (panelOpen) ...[
                                const SizedBox(width: 8),
                                const _NowPlayingPanel(),
                              ],
                            ],
                          ),
                        ),
                      ),
                      // Always present (Spotify-style) — shows an idle state
                      // when nothing's playing. Keeps the mini-player popout +
                      // device/connect controls reachable at all times.
                      const _PlayerBar(),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}

// ─── Keyboard shortcuts ──────────────────────────────────────────────────

/// Wraps the shell in an autofocused [CallbackShortcuts] so global media keys
/// work without clicking. Every single-key binding is guarded by [_isTyping]
/// so it no-ops while an editable is focused, and [GlassField] additionally
/// swallows these keys at the field via a descendant Shortcuts → so typing in
/// search / the DJ prompt is never hijacked.
///
///   Space            play / pause          S        shuffle
///   → / ←            next / previous       R        cycle repeat
///   ⇧→ / ⇧←          seek ±10s             L        lyrics panel
///   ↑ / ↓            volume ±5%            Q        now-playing panel
///   ⌘M               toggle mini-player ⟷ full
class _ShortcutHost extends ConsumerStatefulWidget {
  const _ShortcutHost({required this.child});

  final Widget child;

  @override
  ConsumerState<_ShortcutHost> createState() => _ShortcutHostState();
}

class _ShortcutHostState extends ConsumerState<_ShortcutHost> {
  // Held explicitly so we can re-grab focus when the window flips full ⇄ mini.
  // The swap tears down whatever held focus, which would otherwise leave the
  // CallbackShortcuts subtree with no focused descendant → every key dropped
  // (that's why ⌘M couldn't restore the window from the mini-player).
  final FocusNode _node = FocusNode(debugLabel: 'shell-shortcuts');

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final np = ref.read(nowPlayingProvider.notifier);

    // On every full ⇄ mini switch, re-request focus once the new subtree is
    // built so ⌘M and the other media keys keep firing in whichever window is
    // now showing — without needing to click it first.
    ref.listen<bool>(miniModeProvider, (_, _) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_node.context != null) _node.requestFocus();
      });
    });

    // Wrap a shortcut so it no-ops while a text field is focused.
    VoidCallback guard(VoidCallback cb) => () {
      if (_isTyping) return;
      cb();
    };

    void togglePlay() {
      final playing =
          ref.read(playerStateStreamProvider).valueOrNull?.playing ?? false;
      playing ? np.pause() : np.resume();
    }

    void seekBy(int seconds) {
      final pos = ref.read(playerPositionProvider).valueOrNull ?? Duration.zero;
      final dur = ref.read(playerDurationProvider).valueOrNull ?? Duration.zero;
      var target = pos + Duration(seconds: seconds);
      if (target < Duration.zero) target = Duration.zero;
      if (dur > Duration.zero && target > dur) target = dur;
      np.seek(target);
    }

    void bumpVolume(double delta) {
      final v = (VolumeService.instance.volume.value + delta).clamp(0.0, 1.0);
      VolumeService.instance.setVolume(v);
    }

    void toggleProvider(StateProvider<bool> p) {
      final n = ref.read(p.notifier);
      n.state = !n.state;
    }

    // CallbackShortcuts must be the ANCESTOR of the focused node — key events
    // bubble UP from the focus to it.
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.space): guard(togglePlay),
        const SingleActivator(LogicalKeyboardKey.arrowRight): guard(
          () => np.next(),
        ),
        const SingleActivator(LogicalKeyboardKey.arrowLeft): guard(
          () => np.previous(),
        ),
        const SingleActivator(LogicalKeyboardKey.arrowRight, shift: true): guard(
          () => seekBy(10),
        ),
        const SingleActivator(LogicalKeyboardKey.arrowLeft, shift: true): guard(
          () => seekBy(-10),
        ),
        const SingleActivator(LogicalKeyboardKey.arrowUp): guard(
          () => bumpVolume(0.05),
        ),
        const SingleActivator(LogicalKeyboardKey.arrowDown): guard(
          () => bumpVolume(-0.05),
        ),
        const SingleActivator(LogicalKeyboardKey.keyS): guard(np.toggleShuffle),
        const SingleActivator(LogicalKeyboardKey.keyR): guard(np.cycleRepeat),
        const SingleActivator(LogicalKeyboardKey.keyL): guard(
          () => toggleProvider(desktopLyricsOpenProvider),
        ),
        const SingleActivator(LogicalKeyboardKey.keyQ): guard(
          () => toggleProvider(nowPlayingPanelOpenProvider),
        ),
        // ⌘M toggles the mini-player ⟷ full window. (We freed ⌘M from the
        // macOS "Minimize" menu item in MainMenu.xib so it reaches here.)
        const SingleActivator(LogicalKeyboardKey.keyM, meta: true): () {
          if (ref.read(miniModeProvider)) {
            WindowMode.exitMini(ref);
          } else {
            WindowMode.enterMini(ref);
          }
        },
      },
      child: Focus(
        focusNode: _node,
        autofocus: true,
        child: widget.child,
      ),
    );
  }
}

// ─── Top bar ─────────────────────────────────────────────────────────────

class _TopBar extends ConsumerWidget {
  const _TopBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final index = ref.watch(homeTabIndexProvider);
    final onAnother = ref.watch(
      connectServiceProvider.select((c) => c.activeRemote != null),
    );
    return SizedBox(
      height: 64,
      // The whole bar drags the (frameless) window; button taps still register
      // because DragToMoveArea only claims pans, not taps.
      child: DragToMoveArea(
        // Left inset clears the macOS traffic lights; right padding for actions.
        child: Padding(
          padding: const EdgeInsets.only(left: 80, right: 16),
          child: Row(
            children: [
              _CircleButton(
                icon: index == 0 ? Icons.home_rounded : Icons.home_outlined,
                active: index == 0,
                onTap: () => _go(ref, 0),
              ),
              const SizedBox(width: 8),
              // Expanded (not Flexible+Spacer — those split the slack and
              // re-squeeze the pill); the pill caps at 360 via its own
              // ConstrainedBox and left-aligns, the empty space acts as the
              // spacer, and it shrinks cleanly at the 720px minimum.
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _SearchPill(
                    active: index == 2,
                    onTap: () => _go(ref, 2),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              _FlackoPill(active: index == 1, onTap: () => _go(ref, 1)),
              const SizedBox(width: 14),
              _TopIcon(
                icon: Icons.picture_in_picture_alt_rounded,
                tooltip: 'Mini player',
                onTap: () => WindowMode.enterMini(ref),
              ),
              const SizedBox(width: 6),
              _TopIcon(
                icon: onAnother ? Icons.cast_connected : Icons.devices_rounded,
                active: onAnother,
                tooltip: 'Connect to a device',
                onTap: () => showConnectSheet(context),
              ),
              const SizedBox(width: 6),
              _TopIcon(
                icon: Icons.sync_rounded,
                tooltip: 'Sync library',
                onTap: () => Navigator.of(
                  context,
                ).pushLumen((_) => const SyncScreen(), axis: LumenAxis.fade),
              ),
              const SizedBox(width: 12),
              _CircleButton(
                icon: Icons.person_rounded,
                filledBg: true,
                onTap: () => Navigator.of(
                  context,
                ).pushLumen((_) => const SettingsScreen(), axis: LumenAxis.fade),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CircleButton extends StatelessWidget {
  const _CircleButton({
    required this.icon,
    required this.onTap,
    this.active = false,
    this.filledBg = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool active;
  final bool filledBg;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: filledBg ? const Color(0xFF1F1F1F) : const Color(0xFF1A1A1A),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 24, color: active ? _spText : _spMuted),
      ),
    );
  }
}

class _SearchPill extends StatelessWidget {
  const _SearchPill({required this.active, required this.onTap});

  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      // Caps at 360 on wide windows but shrinks on narrow ones so the top bar
      // never overflows at the 720px minimum.
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: const Color(0xFF1F1F1F),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: active
                  ? Colors.white.withValues(alpha: 0.7)
                  : Colors.transparent,
            ),
          ),
          child: Row(
            children: [
              const Icon(Icons.search_rounded, size: 24, color: _spText),
            const SizedBox(width: 10),
            Text(
              'What do you want to play?',
              style: TextStyle(
                color: _spMuted,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            const Spacer(),
            Container(width: 1, height: 24, color: Colors.white.withValues(alpha: 0.18)),
            const SizedBox(width: 12),
            const Icon(Icons.grid_view_rounded, size: 22, color: _spMuted),
          ],
        ),
      ),
      ),
    );
  }
}

class _FlackoPill extends StatelessWidget {
  const _FlackoPill({required this.active, required this.onTap});

  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: active ? _spGreen.withValues(alpha: 0.16) : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.auto_awesome,
              size: 18,
              color: active ? _spGreen : _spMuted,
            ),
            const SizedBox(width: 8),
            Text(
              'Flacko',
              style: TextStyle(
                color: active ? _spGreen : _spMuted,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopIcon extends StatelessWidget {
  const _TopIcon({
    required this.icon,
    required this.onTap,
    this.active = false,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool active;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final btn = Pressable(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(icon, size: 20, color: active ? _spGreen : _spMuted),
      ),
    );
    return tooltip == null ? btn : Tooltip(message: tooltip!, child: btn);
  }
}

// ─── Left "Your Library" panel ───────────────────────────────────────────

class _LibraryPanel extends ConsumerWidget {
  const _LibraryPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(libraryFilterProvider);
    const names = ['Songs', 'Playlists', 'Albums', 'Artists'];
    return Container(
      width: 288,
      decoration: BoxDecoration(
        color: _spPanel,
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header — tapping the title opens the full Library tab.
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 10, 8),
            child: Row(
              children: [
                Expanded(
                  child: Pressable(
                    onTap: () => _go(ref, 3),
                    child: Row(
                      children: const [
                        Icon(
                          Icons.library_music_rounded,
                          size: 22,
                          color: _spMuted,
                        ),
                        SizedBox(width: 12),
                        Text(
                          'Your Library',
                          style: TextStyle(
                            color: _spMuted,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                _TopIcon(
                  icon: Icons.add_rounded,
                  tooltip: 'Create',
                  onTap: () => _go(ref, 3),
                ),
              ],
            ),
          ),
          // Filter chips — switch which library list the rail shows.
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              children: [
                for (var i = 0; i < names.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: _Chip(
                      label: names[i],
                      selected: filter == i,
                      onTap: () =>
                          ref.read(libraryFilterProvider.notifier).state = i,
                    ),
                  ),
              ],
            ),
          ),
          // Search-in-library + sort row.
          const Padding(
            padding: EdgeInsets.fromLTRB(18, 4, 14, 8),
            child: Row(
              children: [
                Icon(Icons.search_rounded, size: 18, color: _spMuted),
                Spacer(),
                Text(
                  'Recents',
                  style: TextStyle(
                    color: _spMuted,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(width: 6),
                Icon(Icons.swap_vert_rounded, size: 18, color: _spMuted),
              ],
            ),
          ),
          Expanded(child: _LibraryList(filter: filter)),
        ],
      ),
    );
  }
}

/// The scrollable body of the left rail — real playlists / albums / artists
/// from the existing library providers, switched by [filter].
class _LibraryList extends ConsumerWidget {
  const _LibraryList({required this.filter});

  final int filter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Real artist photos for the avatar circles, falling back to seeded art
    // when a photo isn't synced — same source the artist page + mobile use.
    final resolver = ref.watch(artistImageResolverProvider).valueOrNull;
    switch (filter) {
      case 2: // Albums
        return ref
            .watch(albumsProvider)
            .when(
              loading: _loading,
              error: _error,
              data: (albums) => albums.isEmpty
                  ? _empty('No albums yet')
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      itemCount: albums.length,
                      itemBuilder: (_, i) {
                        final a = albums[i];
                        return _LibRow(
                          leading: AlbumArt(
                            artworkPath: a.coverPath,
                            seed: a.coverSeed,
                            size: 48,
                            radius: 6,
                          ),
                          title: a.name,
                          subtitle: 'Album · ${a.artist}',
                          onTap: () => openAlbum(context, a.name),
                        );
                      },
                    ),
            );
      case 3: // Artists
        return ref
            .watch(allArtistsProvider)
            .when(
              loading: _loading,
              error: _error,
              data: (artists) => artists.isEmpty
                  ? _empty('No artists yet')
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      itemCount: artists.length,
                      itemBuilder: (_, i) {
                        final ar = artists[i];
                        return _LibRow(
                          leading: AlbumArt(
                            artworkPath: resolver?.localPath(ar.name),
                            seed: 'artist_${ar.name}',
                            size: 48,
                            radius: 24,
                          ),
                          title: ar.name,
                          subtitle:
                              'Artist · ${ar.songCount} '
                              'song${ar.songCount == 1 ? '' : 's'}',
                          onTap: () => openArtist(context, ar.name),
                        );
                      },
                    ),
            );
      case 1: // Playlists
        return ref
            .watch(allPlaylistsProvider)
            .when(
              loading: _loading,
              error: _error,
              data: (playlists) => playlists.isEmpty
                  ? _empty('No playlists yet')
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      itemCount: playlists.length,
                      itemBuilder: (_, i) {
                        final pl = playlists[i];
                        return _LibRow(
                          leading: AlbumArt(
                            seed: 'pl_${pl.id}',
                            size: 48,
                            radius: 6,
                          ),
                          title: pl.name,
                          subtitle: 'Playlist',
                          onTap: () => contentNavigator(context).pushLumen(
                            (_) => PlaylistDetailScreen(playlistId: pl.id),
                            axis: LumenAxis.fade,
                          ),
                        );
                      },
                    ),
            );
      default: // Songs
        return ref
            .watch(allSongsProvider)
            .when(
              loading: _loading,
              error: _error,
              data: (songs) => songs.isEmpty
                  ? _empty('No songs yet')
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      itemCount: songs.length,
                      itemBuilder: (_, i) {
                        final s = songs[i];
                        return _LibRow(
                          leading: AlbumArt(
                            artworkPath: s.localArtworkPath,
                            seed: s.id,
                            size: 48,
                            radius: 6,
                          ),
                          title: s.title,
                          subtitle: 'Song · ${s.artist}',
                          // Play the song against the full songs list as the
                          // queue; the right Now Playing panel auto-opens.
                          onTap: () {
                            ref
                                .read(aiDjQueueControllerProvider.notifier)
                                .deactivate();
                            ref
                                .read(nowPlayingProvider.notifier)
                                .playFromQueue(songs, i);
                          },
                        );
                      },
                    ),
            );
    }
  }

  static Widget _loading() => const Center(
    child: Padding(
      padding: EdgeInsets.all(24),
      child: SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    ),
  );

  static Widget _error(Object e, StackTrace _) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(
        'Error: $e',
        style: const TextStyle(color: _spMuted, fontSize: 12),
      ),
    ),
  );

  static Widget _empty(String text) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(color: _spMuted, fontSize: 13),
      ),
    ),
  );
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.onTap,
    this.selected = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: selected ? _spText : _spChip,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.black : _spText,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _LibRow extends StatelessWidget {
  const _LibRow({
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  /// A cover/avatar widget (e.g. [AlbumArt]) shown in the 48px slot.
  final Widget leading;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            SizedBox(width: 48, height: 48, child: leading),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _spText,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: _spMuted, fontSize: 13),
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

// ─── Main content panel ──────────────────────────────────────────────────

class _MainPanel extends ConsumerStatefulWidget {
  const _MainPanel({required this.navKey, required this.lyricsOpen});

  final GlobalKey<NavigatorState> navKey;
  final bool lyricsOpen;

  @override
  ConsumerState<_MainPanel> createState() => _MainPanelState();
}

class _MainPanelState extends ConsumerState<_MainPanel> {
  // Per-tab Spotify-style hero tint that fades into the panel.
  static Color _tint(int i) => switch (i) {
    0 => const Color(0xFF1E5C3A), // Home — muted green
    1 => const Color(0xFF3A2E6B), // Flacko — indigo
    2 => const Color(0xFF2A4D6B), // Search — blue
    _ => const Color(0xFF4A3A2E), // Library — warm brown
  };

  @override
  Widget build(BuildContext context) {
    final index = ref.watch(homeTabIndexProvider);
    // Any tab change returns the inner stack to the tab root (defensive — tab
    // taps also pop via _go, which covers the same-tab case a provider listen
    // can't see).
    ref.listen<int>(homeTabIndexProvider, (_, _) {
      widget.navKey.currentState?.popUntil((r) => r.isFirst);
    });

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: ColoredBox(
        color: _spPanel,
        child: Material(
          type: MaterialType.transparency,
          child: Stack(
            children: [
              // Decorative gradient hero behind the content (non-interactive).
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: 320,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          _tint(index).withValues(alpha: 0.45),
                          _spPanel.withValues(alpha: 0.0),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              // Inner Navigator: the tab pages are its root route; album /
              // artist / playlist detail pages push on top WITHIN the panel, so
              // the sidebar, top bar, and bottom player bar keep painting.
              Positioned.fill(
                child: Navigator(
                  key: widget.navKey,
                  onGenerateRoute: (settings) => MaterialPageRoute(
                    settings: settings,
                    builder: (_) => const _MainTabs(),
                  ),
                ),
              ),
              Positioned.fill(
                child: AnimatedSwitcher(
                  duration: LumenTokens.mBase,
                  switchInCurve: LumenTokens.lumenDecelerate,
                  switchOutCurve: LumenTokens.lumenAccelerate,
                  child: widget.lyricsOpen
                      ? const _DesktopLyricsPanel(key: ValueKey('lyrics'))
                      : const SizedBox.shrink(key: ValueKey('nolyrics')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The inner Navigator's root route — the four tab pages. A ConsumerWidget so
/// switching tabs ([homeTabIndexProvider]) rebuilds the stack here without
/// rebuilding the Navigator itself (which would drop any open detail page).
class _MainTabs extends ConsumerWidget {
  const _MainTabs();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final index = ref.watch(homeTabIndexProvider);
    return FadeIndexedStack(index: index, children: DesktopShell._pages);
  }
}

// ─── Right "Now Playing" panel ───────────────────────────────────────────

class _NowPlayingPanel extends ConsumerWidget {
  const _NowPlayingPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final song = ref.watch(nowPlayingProvider);
    if (song == null) return const SizedBox.shrink();
    final controller = ref.read(nowPlayingProvider.notifier);
    return Container(
      width: 340,
      decoration: BoxDecoration(
        color: _spPanel,
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 10, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    song.album ?? song.artist ?? 'Now Playing',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _spText,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                _TopIcon(
                  icon: Icons.close_rounded,
                  onTap: () =>
                      ref.read(nowPlayingPanelOpenProvider.notifier).state =
                          false,
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: AlbumArt(
                      artworkPath: song.localArtworkPath,
                      seed: song.id,
                      size: 308,
                      radius: 0,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Pressable(
                            onTap: () => openAlbum(context, song.album),
                            child: Text(
                              song.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: _spText,
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          if (song.artist != null)
                            Pressable(
                              onTap: () => openArtist(context, song.artist),
                              child: Text(
                                song.artist!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: _spMuted,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    _HeartButton(song: song, size: 24),
                  ],
                ),
                const SizedBox(height: 26),
                Row(
                  children: [
                    const Text(
                      'Next in queue',
                      style: TextStyle(
                        color: _spText,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    Pressable(
                      onTap: () => _openQueuePanel(ref),
                      child: const Text(
                        'Open queue',
                        style: TextStyle(
                          color: _spMuted,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ValueListenableBuilder<QueueView>(
                  valueListenable: controller.queueView,
                  builder: (context, view, _) {
                    final nextIndex = view.index + 1;
                    if (nextIndex < 0 || nextIndex >= view.queue.length) {
                      return Text(
                        'End of queue',
                        style: TextStyle(
                          color: _spMuted.withValues(alpha: 0.7),
                          fontSize: 13,
                        ),
                      );
                    }
                    final s = view.queue[nextIndex];
                    return Pressable(
                      onTap: () => controller.jumpTo(nextIndex),
                      child: Row(
                        children: [
                          AlbumArt(
                            artworkPath: s.localArtworkPath,
                            seed: s.id,
                            size: 48,
                            radius: 6,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  s.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: _spText,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  s.artist ?? 'Unknown artist',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: _spMuted,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Bottom now-playing bar ──────────────────────────────────────────────

class _PlayerBar extends ConsumerWidget {
  const _PlayerBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final song = ref.watch(nowPlayingProvider);
    if (song == null) {
      // Idle bar — stays present (Spotify-style) so the chrome and the
      // minimize / connect controls are reachable before anything plays.
      final onAnotherIdle = ref.watch(
        connectServiceProvider.select((c) => c.activeRemote != null),
      );
      return Container(
        height: 80,
        color: _spBg,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            Expanded(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(
                      Icons.music_note_rounded,
                      color: _spMuted,
                    ),
                  ),
                  const SizedBox(width: 14),
                  const Text(
                    'Nothing playing',
                    style: TextStyle(
                      color: _spMuted,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.25),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.play_arrow_rounded,
                color: Colors.black54,
                size: 22,
              ),
            ),
            Expanded(
              child: Align(
                alignment: Alignment.centerRight,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _BarIcon(
                      icon: onAnotherIdle
                          ? Icons.cast_connected
                          : Icons.devices_rounded,
                      size: 20,
                      active: onAnotherIdle,
                      onTap: () => showConnectSheet(context),
                    ),
                    const SizedBox(width: 14),
                    _BarIcon(
                      icon: Icons.picture_in_picture_alt_rounded,
                      size: 20,
                      onTap: () => WindowMode.enterMini(ref),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    final snap = ref.watch(playerStateStreamProvider).valueOrNull;
    final playing = snap?.playing ?? false;
    final modes = ref.watch(playbackModesProvider);
    final np = ref.read(nowPlayingProvider.notifier);
    final lyricsOpen = ref.watch(desktopLyricsOpenProvider);
    final panelOpen = ref.watch(nowPlayingPanelOpenProvider);
    final queueOpen = ref.watch(desktopQueueOpenProvider);
    final automixOn = ref.watch(autoMixEnabledProvider);
    final onAnother = ref.watch(
      connectServiceProvider.select((c) => c.activeRemote != null),
    );

    return Container(
      height: 80,
      color: _spBg,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          // LEFT — cover + meta.
          Expanded(
            flex: 3,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Pressable(
                    onTap: () =>
                        ref.read(nowPlayingPanelOpenProvider.notifier).state =
                            !panelOpen,
                    child: AlbumArt(
                      artworkPath: song.localArtworkPath,
                      seed: song.id,
                      size: 56,
                      radius: 6,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Flexible(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Pressable(
                          onTap: () => openAlbum(context, song.album),
                          child: Text(
                            song.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: _spText,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(height: 3),
                        Pressable(
                          onTap: () => openArtist(context, song.artist),
                          child: Text(
                            song.artist ?? 'Unknown artist',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: _spMuted,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  _HeartButton(song: song),
                ],
              ),
            ),
          ),
          // CENTER — transport + seek. Expanded + capped width so it stays
          // centered on wide windows and shrinks (transport scales down) on
          // narrow ones instead of overflowing.
          Expanded(
            flex: 4,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 540),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _BarIcon(
                            icon: Icons.shuffle_rounded,
                            active: modes.shuffle,
                            size: 20,
                            onTap: np.toggleShuffle,
                          ),
                          const SizedBox(width: 20),
                          _BarIcon(
                            icon: Icons.skip_previous_rounded,
                            size: 28,
                            onTap: () => np.previous(),
                          ),
                          const SizedBox(width: 12),
                          _WhitePlayButton(
                            playing: playing,
                            onTap: () => playing ? np.pause() : np.resume(),
                          ),
                          const SizedBox(width: 12),
                          _BarIcon(
                            icon: Icons.skip_next_rounded,
                            size: 28,
                            onTap: () => np.next(),
                          ),
                          const SizedBox(width: 20),
                          _BarIcon(
                            icon: modes.repeat == QueueRepeatMode.one
                                ? Icons.repeat_one_rounded
                                : Icons.repeat_rounded,
                            active: modes.repeat != QueueRepeatMode.off,
                            size: 20,
                            onTap: np.cycleRepeat,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    _SpotifySeekBar(fallbackMs: song.durationMs ?? 0),
                  ],
                ),
              ),
            ),
          ),
          // RIGHT — view toggles + volume. FittedBox so the cluster scales
          // down on narrow windows instead of overflowing.
          Expanded(
            flex: 3,
            child: Align(
              alignment: Alignment.centerRight,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _BarIcon(
                      icon: Icons.art_track_rounded,
                      size: 20,
                      active: panelOpen,
                      onTap: () {
                        ref.read(desktopQueueOpenProvider.notifier).state =
                            false;
                        ref.read(nowPlayingPanelOpenProvider.notifier).state =
                            !panelOpen;
                      },
                    ),
                    const SizedBox(width: 14),
                    _BarIcon(
                      icon: Icons.lyrics_rounded,
                      size: 20,
                      active: lyricsOpen,
                      onTap: () {
                        final n = ref.read(desktopLyricsOpenProvider.notifier);
                        n.state = !n.state;
                      },
                    ),
                    const SizedBox(width: 14),
                    // AutoMix — beat-matched / harmonic transitions on
                    // auto-advance (falls back to a plain crossfade when a
                    // track has no analysis sidecar).
                    _BarIcon(
                      icon: Icons.auto_awesome_rounded,
                      size: 20,
                      active: automixOn,
                      onTap: () => ref
                          .read(autoMixEnabledProvider.notifier)
                          .update((v) => !v),
                    ),
                    const SizedBox(width: 14),
                    _BarIcon(
                      icon: Icons.queue_music_rounded,
                      size: 20,
                      active: queueOpen,
                      onTap: () {
                        if (queueOpen) {
                          ref.read(desktopQueueOpenProvider.notifier).state =
                              false;
                        } else {
                          _openQueuePanel(ref);
                        }
                      },
                    ),
                    const SizedBox(width: 14),
                    _BarIcon(
                      icon: onAnother
                          ? Icons.cast_connected
                          : Icons.devices_rounded,
                      size: 20,
                      active: onAnother,
                      onTap: () => showConnectSheet(context),
                    ),
                    const SizedBox(width: 14),
                    const _VolumeControl(),
                    const SizedBox(width: 14),
                    // Minimize to the floating mini-player.
                    _BarIcon(
                      icon: Icons.picture_in_picture_alt_rounded,
                      size: 20,
                      onTap: () => WindowMode.enterMini(ref),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WhitePlayButton extends StatelessWidget {
  const _WhitePlayButton({required this.playing, required this.onTap});

  final bool playing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: const BoxDecoration(color: _spText, shape: BoxShape.circle),
        child: AnimatedSwitcher(
          duration: LumenTokens.mFast,
          transitionBuilder: (child, anim) => ScaleTransition(
            scale: Tween<double>(begin: 0.6, end: 1).animate(anim),
            child: FadeTransition(opacity: anim, child: child),
          ),
          child: Icon(
            playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
            key: ValueKey(playing),
            color: Colors.black,
            size: 22,
          ),
        ),
      ),
    );
  }
}

class _BarIcon extends StatelessWidget {
  const _BarIcon({
    required this.icon,
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
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Padding(
            padding: const EdgeInsets.all(3),
            child: Icon(icon, size: size, color: active ? _spGreen : _spMuted),
          ),
          // Spotify's "active" green dot under the glyph.
          if (active)
            const Positioned(
              bottom: -3,
              child: CircleAvatar(radius: 2, backgroundColor: _spGreen),
            ),
        ],
      ),
    );
  }
}

/// Spotify-style scrubber: white fill that turns green on hover, thumb only
/// visible on hover. Holds a local drag value so the thumb doesn't fight the
/// position stream while dragging.
class _SpotifySeekBar extends ConsumerStatefulWidget {
  const _SpotifySeekBar({required this.fallbackMs});

  final int fallbackMs;

  @override
  ConsumerState<_SpotifySeekBar> createState() => _SpotifySeekBarState();
}

class _SpotifySeekBarState extends ConsumerState<_SpotifySeekBar>
    with SingleTickerProviderStateMixin {
  double? _dragValue;
  bool _hover = false;

  // Gentle pink pulse while AutoMix blends two tracks; eased back to 0 after.
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

  String _fmt(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<bool>(autoMixMixingProvider, (_, next) => _onMixingChanged(next));
    final mixing = ref.watch(autoMixMixingProvider);

    final pos = ref.watch(playerPositionProvider).valueOrNull ?? Duration.zero;
    final dur =
        ref.watch(playerDurationProvider).valueOrNull ??
        Duration(milliseconds: widget.fallbackMs);
    final totalMs = dur.inMilliseconds <= 0 ? 1 : dur.inMilliseconds;
    final value = _dragValue ?? (pos.inMilliseconds / totalMs).clamp(0.0, 1.0);

    const mixAccent = LumenTokens.accent; // app pink for the "mixing" state

    return Row(
      children: [
        SizedBox(
          width: 40,
          child: Text(
            _fmt(pos),
            textAlign: TextAlign.right,
            style: const TextStyle(
              color: _spMuted,
              fontSize: 11,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Stack(
            alignment: Alignment.center,
            children: [
              MouseRegion(
                onEnter: (_) => setState(() => _hover = true),
                onExit: (_) => setState(() => _hover = false),
                child: AnimatedBuilder(
                  animation: _glow,
                  builder: (context, _) {
                    final g = _glow.value; // 0 (idle) → 1 (peak glow)
                    final fill = Color.lerp(
                      _hover ? _spGreen : _spText,
                      mixAccent,
                      g,
                    )!;
                    return DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: g > 0.02
                            ? [
                                BoxShadow(
                                  color: mixAccent.withValues(alpha: 0.32 * g),
                                  blurRadius: 6 + 16 * g,
                                  spreadRadius: 0.5 * g,
                                ),
                              ]
                            : null,
                      ),
                      child: SliderTheme(
                        data: SliderThemeData(
                          trackHeight: 4,
                          activeTrackColor: fill,
                          inactiveTrackColor: _spTrack,
                          thumbColor: _spText,
                          overlayColor: Colors.transparent,
                          thumbShape: RoundSliderThumbShape(
                            enabledThumbRadius: _hover ? 6 : 0,
                          ),
                          overlayShape: const RoundSliderOverlayShape(
                            overlayRadius: 0,
                          ),
                        ),
                        child: Slider(
                          value: value.toDouble(),
                          onChanged: (v) => setState(() => _dragValue = v),
                          onChangeEnd: (v) {
                            ref
                                .read(nowPlayingProvider.notifier)
                                .seek(
                                  Duration(
                                    milliseconds: (v * totalMs).round(),
                                  ),
                                );
                            setState(() => _dragValue = null);
                          },
                        ),
                      ),
                    );
                  },
                ),
              ),
              // "Mixing" pill — fades in over the glowing bar during a blend.
              IgnorePointer(
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 250),
                  opacity: mixing ? 1 : 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.auto_awesome_rounded,
                          size: 12,
                          color: mixAccent,
                        ),
                        SizedBox(width: 5),
                        Text(
                          'Mixing',
                          style: TextStyle(
                            color: mixAccent,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 40,
          child: Text(
            _fmt(dur),
            style: const TextStyle(
              color: _spMuted,
              fontSize: 11,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }
}

/// Volume glyph + 93px slider bound to the system volume (white → green on
/// hover, like Spotify).
class _VolumeControl extends StatefulWidget {
  const _VolumeControl();

  @override
  State<_VolumeControl> createState() => _VolumeControlState();
}

class _VolumeControlState extends State<_VolumeControl> {
  bool _hover = false;

  @override
  void initState() {
    super.initState();
    // Seed the thumb with the current system volume. We never register
    // volume_controller's listener (it deactivates the shared audio session).
    VolumeService.instance.refresh();
  }

  IconData _glyph(double v) {
    if (v <= 0.001) return Icons.volume_off_rounded;
    if (v < 0.5) return Icons.volume_down_rounded;
    return Icons.volume_up_rounded;
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: VolumeService.instance.volume,
      builder: (context, volume, _) {
        final v = volume.clamp(0.0, 1.0);
        final fill = _hover ? _spGreen : _spText;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_glyph(v), size: 20, color: _spMuted),
            const SizedBox(width: 4),
            SizedBox(
              width: 93,
              child: MouseRegion(
                onEnter: (_) => setState(() => _hover = true),
                onExit: (_) => setState(() => _hover = false),
                child: SliderTheme(
                  data: SliderThemeData(
                    trackHeight: 4,
                    activeTrackColor: fill,
                    inactiveTrackColor: _spTrack,
                    thumbColor: _spText,
                    overlayColor: Colors.transparent,
                    thumbShape: RoundSliderThumbShape(
                      enabledThumbRadius: _hover ? 6 : 0,
                    ),
                    overlayShape: const RoundSliderOverlayShape(
                      overlayRadius: 0,
                    ),
                  ),
                  child: Slider(
                    value: v,
                    onChanged: VolumeService.instance.setVolume,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ─── Up-next queue sheet ─────────────────────────────────────────────────

/// Inline right-side queue panel (Spotify-style) — replaces the old modal
/// sheet. Mutually exclusive with [_NowPlayingPanel].
class _QueueRightPanel extends ConsumerWidget {
  const _QueueRightPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(nowPlayingProvider.notifier);
    return Container(
      width: 340,
      decoration: BoxDecoration(
        color: _spPanel,
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 10, 8),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Queue',
                    style: TextStyle(
                      color: _spText,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                _TopIcon(
                  icon: Icons.close_rounded,
                  onTap: () =>
                      ref.read(desktopQueueOpenProvider.notifier).state = false,
                ),
              ],
            ),
          ),
          Expanded(
            child: ValueListenableBuilder<QueueView>(
              valueListenable: controller.queueView,
              builder: (context, view, _) {
                if (view.queue.isEmpty) {
                  return const Center(
                    child: Text(
                      'Queue is empty',
                      style: TextStyle(color: _spMuted, fontSize: 13),
                    ),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.only(bottom: 12),
                  itemCount: view.queue.length,
                  itemBuilder: (context, i) {
                    final s = view.queue[i];
                    final isCurrent = i == view.index;
                    return Pressable(
                      onTap: () => controller.jumpTo(i),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 7,
                        ),
                        child: Row(
                          children: [
                            AlbumArt(
                              artworkPath: s.localArtworkPath,
                              seed: s.id,
                              size: 44,
                              radius: 6,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    s.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: isCurrent ? _spGreen : _spText,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    s.artist ?? 'Unknown artist',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: _spMuted,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (isCurrent)
                              const Icon(
                                Icons.equalizer_rounded,
                                color: _spGreen,
                                size: 18,
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Lyrics panel (over the main content) ────────────────────────────────

class _DesktopLyricsPanel extends ConsumerWidget {
  const _DesktopLyricsPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final song = ref.watch(nowPlayingProvider);
    if (song == null) return const SizedBox.shrink();
    return Stack(
      fit: StackFit.expand,
      children: [
        BloomBackground(song: song, darkenStrength: 0.62, audioReactive: false),
        Positioned(
          left: 28,
          top: 22,
          right: 64,
          child: Row(
            children: [
              AlbumArt(
                artworkPath: song.localArtworkPath,
                seed: song.id,
                size: 44,
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
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (song.artist != null)
                      Text(
                        song.artist!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.66),
                          fontSize: 13,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 84),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: const InlineLyrics(),
            ),
          ),
        ),
        Positioned(
          top: 14,
          right: 16,
          child: _TopIcon(
            icon: Icons.close_rounded,
            onTap: () =>
                ref.read(desktopLyricsOpenProvider.notifier).state = false,
          ),
        ),
      ],
    );
  }
}
