import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/database/app_database.dart';
import '../motion/lumen_route.dart';
import '../../features/library/library_actions.dart';
import '../../features/lyrics/share_lyrics.dart' show shareOriginFor;
import '../../features/nav/content_navigator_scope.dart';
import '../../features/player/now_playing_controller.dart';
import '../../features/player/playback_extras.dart';
import '../../features/playlists/providers.dart';
import '../screens/album_detail_screen.dart';
import '../screens/artist_detail_screen.dart';
import '../theme/app_theme.dart';
import 'album_art.dart';
import 'glass.dart';
import 'glass_kit.dart';

/// Long-press / "…" action sheet for a song. [fromPlayer] adds the global
/// playback controls (sleep timer + speed) on top of the per-song actions.
class SongActionsSheet extends ConsumerWidget {
  const SongActionsSheet({
    super.key,
    required this.song,
    this.fromPlayer = false,
    this.onRemoveFromPlaylist,
    this.contentNav,
  });

  final SongRow song;
  final bool fromPlayer;

  /// When set, shows a "Remove from this playlist" action (only wired in
  /// from the playlist detail screen).
  final VoidCallback? onRemoveFromPlaylist;

  /// The mobile shell's inner content Navigator, captured from the
  /// originating screen (the modal sheet itself mounts on the ROOT overlay,
  /// so it can't reach the scope). Used so "Go to artist/album" pushes into
  /// the persistent-chrome inner stack. Null on desktop → falls back to root.
  final GlobalKey<NavigatorState>? contentNav;

  static Future<void> show(
    BuildContext context,
    SongRow song, {
    bool fromPlayer = false,
    VoidCallback? onRemoveFromPlaylist,
  }) {
    // Capture the inner Navigator HERE (origin context is under the scope);
    // the sheet's own context will be a root-overlay descendant and can't.
    final contentNav = ContentNavigatorScope.maybeOf(context);
    return showGlassSheet<void>(
      context,
      child: SongActionsSheet(
        song: song,
        fromPlayer: fromPlayer,
        onRemoveFromPlaylist: onRemoveFromPlaylist,
        contentNav: contentNav,
      ),
    );
  }

  void _snack(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _addToPlaylist(BuildContext context) async {
    Navigator.of(context).pop();
    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _PickPlaylistSheet(song: song),
    );
  }

  void _push(BuildContext context, Widget screen) {
    // Pop the sheet (root overlay), then push the detail page onto the inner
    // content Navigator so the nav + mini player stay visible. Falls back to
    // the root navigator on desktop (no inner Navigator).
    final root = Navigator.of(context);
    root.pop();
    (contentNav?.currentState ?? root).pushLumen((_) => screen);
  }

  Future<void> _share(BuildContext context) async {
    // Capture the iOS popover anchor before popping the sheet (after pop the
    // context unmounts and the origin would fall back to screen-centre).
    final origin = shareOriginFor(context);
    Navigator.of(context).pop();
    final subject = '${song.title} — ${song.artist ?? ''}'.trim();
    try {
      final path = song.localFilePath;
      if (path.isNotEmpty && await File(path).exists()) {
        await Share.shareXFiles(
          [XFile(path)],
          subject: subject,
          sharePositionOrigin: origin,
        );
      } else {
        await Share.share(subject, sharePositionOrigin: origin);
      }
    } catch (_) {}
  }

  Future<void> _remove(BuildContext context, WidgetRef ref) async {
    final ok = await showGlassConfirm(
      context,
      title: 'Remove from library?',
      body:
          'Deletes the downloaded file for "${song.title}". Re-sync from your '
          'server to get it back.',
      confirmLabel: 'Remove',
      destructive: true,
    );
    if (!ok) return;
    if (context.mounted) Navigator.of(context).pop();
    await ref.read(libraryActionsProvider).removeFromLibrary(song);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isFav = song.isFavorite == 1;
    final hasArtist = song.artist != null && song.artist!.isNotEmpty;
    final hasAlbum = song.album != null && song.album!.isNotEmpty;

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.82,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header.
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Row(
                children: [
                  AlbumArt(
                    artworkPath: song.localArtworkPath,
                    seed: song.id,
                    size: 46,
                    radius: 10,
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
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: LumenTokens.fg(context),
                          ),
                        ),
                        if (hasArtist)
                          Text(
                            song.artist!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: LumenTokens.fgDimOf(context),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Divider(
              height: 1,
              color: LumenTokens.fgDim2Of(context).withValues(alpha: 0.12),
            ),

            // Player-only: sleep timer + speed.
            if (fromPlayer) ...[
              _SleepTimerRow(),
              _SpeedRow(),
              Divider(
                height: 1,
                color: LumenTokens.fgDim2Of(context).withValues(alpha: 0.12),
              ),
            ],

            _SheetAction(
              icon: Icons.queue_play_next_rounded,
              label: 'Play next',
              onTap: () {
                ref.read(nowPlayingProvider.notifier).playNext(song);
                Navigator.of(context).pop();
                _snack(context, 'Playing next');
              },
            ),
            _SheetAction(
              icon: Icons.queue_music_rounded,
              label: 'Add to queue',
              onTap: () {
                ref.read(nowPlayingProvider.notifier).addToQueue(song);
                Navigator.of(context).pop();
                _snack(context, 'Added to queue');
              },
            ),
            _SheetAction(
              icon: isFav
                  ? Icons.favorite_rounded
                  : Icons.favorite_border_rounded,
              label: isFav ? 'Remove from favorites' : 'Add to favorites',
              onTap: () async {
                await ref.read(libraryActionsProvider).toggleFavorite(song);
                if (context.mounted) Navigator.of(context).pop();
              },
            ),
            _SheetAction(
              icon: Icons.playlist_add_rounded,
              label: 'Add to playlist',
              onTap: () => _addToPlaylist(context),
            ),
            if (onRemoveFromPlaylist != null)
              _SheetAction(
                icon: Icons.playlist_remove_rounded,
                label: 'Remove from this playlist',
                onTap: () {
                  Navigator.of(context).pop();
                  onRemoveFromPlaylist!();
                },
              ),
            if (hasArtist)
              _SheetAction(
                icon: Icons.person_outline_rounded,
                label: 'Go to artist',
                onTap: () =>
                    _push(context, ArtistDetailScreen(artist: song.artist!)),
              ),
            if (hasAlbum)
              _SheetAction(
                icon: Icons.album_outlined,
                label: 'Go to album',
                onTap: () =>
                    _push(context, AlbumDetailScreen(album: song.album!)),
              ),
            _SheetAction(
              icon: Icons.ios_share_rounded,
              label: 'Share',
              onTap: () => _share(context),
            ),
            _SheetAction(
              icon: Icons.info_outline_rounded,
              label: 'Song info',
              onTap: () {
                Navigator.of(context).pop();
                showGlassSheet<void>(context, child: _SongInfoView(song: song));
              },
            ),
            _SheetAction(
              icon: Icons.delete_outline_rounded,
              label: 'Remove from library',
              destructive: true,
              onTap: () => _remove(context, ref),
            ),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }
}

class _SheetAction extends StatelessWidget {
  const _SheetAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.trailing,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Widget? trailing;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final color = destructive
        ? Theme.of(context).colorScheme.error
        : LumenTokens.fg(context);
    return Pressable(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        child: Row(
          children: [
            Icon(icon, size: 22, color: color),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ),
            ?trailing,
          ],
        ),
      ),
    );
  }
}

String _fmtRemaining(Duration d) =>
    '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

class _SleepTimerRow extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final remaining = ref.watch(sleepTimerProvider);
    final label = remaining == null ? 'Off' : _fmtRemaining(remaining);
    return _SheetAction(
      icon: Icons.bedtime_outlined,
      label: 'Sleep timer',
      trailing: Text(
        label,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: remaining == null
              ? LumenTokens.fgDimOf(context)
              : LumenTokens.accent,
        ),
      ),
      onTap: () async {
        final picked = await showGlassSheet<int>(
          context,
          child: _OptionList<int>(
            title: 'Sleep timer',
            options: const [
              ('Off', 0),
              ('15 minutes', 15),
              ('30 minutes', 30),
              ('45 minutes', 45),
              ('1 hour', 60),
            ],
            selected: remaining == null ? 0 : -1,
          ),
        );
        if (picked == null) return;
        final c = ref.read(sleepTimerProvider.notifier);
        if (picked == 0) {
          c.cancel();
        } else {
          c.start(Duration(minutes: picked));
        }
      },
    );
  }
}

class _SpeedRow extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final speed = ref.watch(playbackSpeedProvider);
    return _SheetAction(
      icon: Icons.speed_rounded,
      label: 'Playback speed',
      trailing: Text(
        '${speed}x',
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: speed == 1.0
              ? LumenTokens.fgDimOf(context)
              : LumenTokens.accent,
        ),
      ),
      onTap: () async {
        final picked = await showGlassSheet<double>(
          context,
          child: _OptionList<double>(
            title: 'Playback speed',
            options: const [
              ('0.5x', 0.5),
              ('0.75x', 0.75),
              ('Normal', 1.0),
              ('1.25x', 1.25),
              ('1.5x', 1.5),
              ('2x', 2.0),
            ],
            selected: speed,
          ),
        );
        if (picked == null) return;
        ref.read(playbackSpeedProvider.notifier).set(picked);
      },
    );
  }
}

/// Generic single-select list used by the sleep-timer / speed pickers.
class _OptionList<T> extends StatelessWidget {
  const _OptionList({
    required this.title,
    required this.options,
    required this.selected,
  });

  final String title;
  final List<(String, T)> options;
  final T selected;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(title, style: glassEyebrow(context)),
          ),
        ),
        for (final (label, value) in options)
          Pressable(
            onTap: () => Navigator.of(context).pop(value),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: LumenTokens.fg(context),
                      ),
                    ),
                  ),
                  if (value == selected)
                    const Icon(
                      Icons.check_rounded,
                      size: 20,
                      color: LumenTokens.accent,
                    ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 6),
      ],
    );
  }
}

class _SongInfoView extends StatelessWidget {
  const _SongInfoView({required this.song});

  final SongRow song;

  String _dur(int? ms) {
    if (ms == null || ms <= 0) return '—';
    final s = ms ~/ 1000;
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final rows = <(String, String)>[
      ('Title', song.title),
      ('Artist', song.artist ?? '—'),
      ('Album', song.album ?? '—'),
      if (song.genre != null && song.genre!.isNotEmpty) ('Genre', song.genre!),
      ('Duration', _dur(song.durationMs)),
      if (song.bpm != null) ('BPM', '${song.bpm}'),
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
          child: Text(
            'Song info',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: LumenTokens.fg(context),
            ),
          ),
        ),
        for (final (label, value) in rows)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 80,
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: LumenTokens.fgDim2Of(context),
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    value,
                    style: TextStyle(
                      fontSize: 14,
                      color: LumenTokens.fg(context),
                    ),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 10),
      ],
    );
  }
}

class _PickPlaylistSheet extends ConsumerWidget {
  const _PickPlaylistSheet({required this.song});

  final SongRow song;

  Future<void> _createAndAdd(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final name = await showGlassDialog<String>(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'New playlist',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: LumenTokens.fg(context),
            ),
          ),
          const SizedBox(height: 16),
          GlassField(controller: controller, autofocus: true, hint: 'Name'),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: GlassButton(
                  label: 'Cancel',
                  expand: true,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: GlassButton(
                  label: 'Create',
                  primary: true,
                  expand: true,
                  onPressed: () =>
                      Navigator.of(context).pop(controller.text.trim()),
                ),
              ),
            ],
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    await ref
        .read(libraryActionsProvider)
        .createPlaylistWithSong(name: name, songId: song.id);
    if (!context.mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Added to "$name"')));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlists = ref.watch(allPlaylistsProvider);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.5,
      maxChildSize: 0.85,
      builder: (ctx, scroll) => Glass(
        strong: true,
        shape: const BorderRadius.vertical(top: Radius.circular(24)),
        child: playlists.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error: $e')),
          data: (list) => ListView(
            controller: scroll,
            padding: const EdgeInsets.only(top: 12, bottom: 12),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text('Add to playlist', style: glassEyebrow(context)),
              ),
              _SheetAction(
                icon: Icons.add_rounded,
                label: 'New playlist',
                onTap: () => _createAndAdd(context, ref),
              ),
              for (final pl in list)
                _SheetAction(
                  icon: Icons.queue_music_rounded,
                  label: pl.name,
                  onTap: () async {
                    await ref
                        .read(libraryActionsProvider)
                        .addToPlaylist(playlistId: pl.id, songId: song.id);
                    if (!context.mounted) return;
                    Navigator.of(context).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Added to "${pl.name}"')),
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}
