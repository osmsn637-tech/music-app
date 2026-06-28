import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database/app_database.dart';
import '../../features/library/library_actions.dart';
import '../../features/library/providers.dart';
import '../../features/nav/content_navigator_scope.dart';
import '../../features/player/now_playing_controller.dart';
import '../../features/player/providers.dart';
import '../../features/playlists/providers.dart';
import '../../features/player/player_expansion_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/glass.dart';
import '../widgets/glass_kit.dart';
import '../widgets/playlist_cover.dart';
import '../widgets/song_actions.dart';
import '../widgets/song_tile.dart';

class PlaylistDetailScreen extends ConsumerWidget {
  const PlaylistDetailScreen({super.key, required this.playlistId});

  final String playlistId;

  Future<void> _openSong(
    BuildContext context,
    WidgetRef ref,
    List<SongRow> queue,
    int index,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(nowPlayingProvider.notifier).playFromQueue(queue, index);
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not play file: $e')),
      );
      return;
    }
    if (!context.mounted) return;
    PlayerExpansionScope.read(context).expand();
  }

  /// Glass action sheet for the top-bar overflow button.
  Future<void> _showMenu(
    BuildContext context,
    WidgetRef ref,
    PlaylistRow pl,
  ) async {
    Widget action(
      IconData icon,
      String label,
      VoidCallback onTap, {
      Color? color,
    }) {
      return Pressable(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          child: Row(
            children: [
              Icon(icon, size: 20, color: color ?? LumenTokens.fg(context)),
              const SizedBox(width: 14),
              Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: color ?? LumenTokens.fg(context),
                ),
              ),
            ],
          ),
        ),
      );
    }

    await showGlassSheet<void>(
      context,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          action(Icons.edit_outlined, 'Rename', () {
            Navigator.pop(context);
            _rename(context, ref, pl);
          }),
          action(Icons.copy_all_outlined, 'Duplicate', () async {
            Navigator.pop(context);
            final messenger = ScaffoldMessenger.of(context);
            await ref.read(playlistRepositoryProvider).duplicate(pl.id);
            messenger.showSnackBar(
              SnackBar(content: Text('Duplicated "${pl.name}"')),
            );
          }),
          action(
            Icons.delete_outline,
            'Delete playlist',
            () {
              Navigator.pop(context);
              _delete(context, ref, pl);
            },
            color: Theme.of(context).colorScheme.error,
          ),
        ],
      ),
    );
  }

  Future<void> _rename(
    BuildContext context,
    WidgetRef ref,
    PlaylistRow pl,
  ) async {
    final controller = TextEditingController(text: pl.name);
    final newName = await showGlassDialog<String>(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Rename playlist',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
              color: LumenTokens.fg(context),
            ),
          ),
          const SizedBox(height: 16),
          GlassField(
            controller: controller,
            autofocus: true,
            hint: 'Name',
            onSubmitted: (v) => Navigator.pop(context, v.trim()),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: GlassButton(
                  label: 'Cancel',
                  expand: true,
                  onPressed: () => Navigator.pop(context),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: GlassButton(
                  label: 'Save',
                  primary: true,
                  expand: true,
                  onPressed: () =>
                      Navigator.pop(context, controller.text.trim()),
                ),
              ),
            ],
          ),
        ],
      ),
    );
    controller.dispose();
    if (newName != null && newName.isNotEmpty && newName != pl.name) {
      await ref.read(playlistRepositoryProvider).rename(pl.id, newName);
    }
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    PlaylistRow pl,
  ) async {
    final confirm = await showGlassConfirm(
      context,
      title: 'Delete playlist?',
      body: 'Removes "${pl.name}". The songs themselves are not deleted.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!confirm) return;
    await ref.read(playlistRepositoryProvider).delete(pl.id);
    if (!context.mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pl = ref
        .watch(allPlaylistsProvider)
        .maybeWhen(
          data: (list) => list.where((p) => p.id == playlistId).firstOrNull,
          orElse: () => null,
        );
    final songs = ref.watch(playlistSongsProvider(playlistId));
    final nowPlayingId = ref.watch(nowPlayingProvider)?.id;
    final isPlaying =
        ref.watch(playerStateStreamProvider).valueOrNull?.playing ?? false;
    final chrome = hasPersistentChrome(context);
    final bottomPad = chrome ? LumenTokens.bottomSafePad : 40.0;

    return StageScaffold(
      actions: [
        if (pl != null)
          GlassIconButton(
            icon: Icons.more_horiz,
            onTap: () => _showMenu(context, ref, pl),
          ),
      ],
      floatingActionButton: Padding(
        // Lift the FAB above the persistent nav + mini player (mobile only).
        padding: EdgeInsets.only(bottom: chrome ? 96 : 0),
        child: GlassButton(
          label: 'Add songs',
          icon: Icons.add,
          primary: true,
          onPressed: () => _showAddSongs(context, ref),
        ),
      ),
      body: songs.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (list) {
          final header = _PlaylistHeader(
            key: const ValueKey('playlist-header'),
            playlistId: playlistId,
            name: pl?.name ?? 'Playlist',
            songs: list,
            canEdit: pl != null,
            onEdit: pl == null ? null : () => _rename(context, ref, pl),
            onPlay: list.isEmpty
                ? null
                : () => _openSong(context, ref, list, 0),
            onShuffle: list.isEmpty
                ? null
                : () {
                    final shuffled = [...list]..shuffle();
                    _openSong(context, ref, shuffled, 0);
                  },
          );
          if (list.isEmpty) {
            return ListView(
              padding: EdgeInsets.only(bottom: bottomPad),
              children: [
                header,
                _Empty(playlistId: playlistId),
              ],
            );
          }
          return ReorderableListView.builder(
            padding: EdgeInsets.only(bottom: bottomPad),
            header: header,
            itemCount: list.length,
            onReorder: (oldIndex, newIndex) {
              ref
                  .read(playlistRepositoryProvider)
                  .reorder(
                    playlistId: playlistId,
                    oldIndex: oldIndex,
                    newIndex: newIndex,
                  );
            },
            itemBuilder: (context, i) {
              final song = list[i];
              final active = nowPlayingId == song.id;
              void openMore() => SongActionsSheet.show(
                context,
                song,
                onRemoveFromPlaylist: () => ref
                    .read(playlistRepositoryProvider)
                    .removeSong(playlistId: playlistId, songId: song.id),
              );
              return SongTile(
                key: ValueKey(song.id),
                song: song,
                isPlaying: active,
                onTap: () {
                  // Only treat as "already playing → just expand" when the
                  // engine is actually mid-playback. After resuming the app
                  // the previous song is still in nowPlayingProvider but
                  // playback has stopped — falling through to _openSong
                  // restarts it instead of silently opening an empty player.
                  if (active && isPlaying) {
                    PlayerExpansionScope.maybeRead(context)?.expand();
                  } else {
                    _openSong(context, ref, list, i);
                  }
                },
                onLongPress: () => openMore(),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: Icon(
                        Icons.more_horiz,
                        color: LumenTokens.fgDimOf(context),
                      ),
                      onPressed: () => openMore(),
                      splashRadius: 20,
                    ),
                    ReorderableDragStartListener(
                      index: i,
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: Icon(Icons.drag_handle),
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _showAddSongs(BuildContext context, WidgetRef ref) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _AddSongsSheet(playlistId: playlistId),
    );
  }
}

class _PlaylistHeader extends StatelessWidget {
  const _PlaylistHeader({
    super.key,
    required this.playlistId,
    required this.name,
    required this.songs,
    required this.canEdit,
    this.onEdit,
    this.onPlay,
    this.onShuffle,
  });

  final String playlistId;
  final String name;
  final List<SongRow> songs;
  final bool canEdit;
  final VoidCallback? onEdit;
  final VoidCallback? onPlay;
  final VoidCallback? onShuffle;

  String _formatDuration(int totalMs) {
    if (totalMs <= 0) return '';
    final totalMin = totalMs ~/ 60000;
    final hours = totalMin ~/ 60;
    final minutes = totalMin % 60;
    if (hours == 0) return '$minutes min';
    return '$hours hr $minutes min';
  }

  @override
  Widget build(BuildContext context) {
    final totalMs = songs.fold<int>(0, (s, r) => s + (r.durationMs ?? 0));
    final subtitle = [
      '${songs.length} song${songs.length == 1 ? '' : 's'}',
      if (totalMs > 0) _formatDuration(totalMs),
    ].join(', ');

    return Padding(
      // The glass top bar (StageScaffold) already clears the status bar,
      // so the header just needs a little breathing room above the cover.
      padding: const EdgeInsets.fromLTRB(
        LumenTokens.pagePad,
        8,
        LumenTokens.pagePad,
        20,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          PlaylistCover(
            playlistId: playlistId,
            size: 220,
            radius: LumenTokens.rSm,
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  name,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.6,
                    height: 1.1,
                  ),
                ),
              ),
              if (canEdit) ...[
                const SizedBox(width: 6),
                InkResponse(
                  onTap: onEdit,
                  radius: 18,
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      Icons.edit_outlined,
                      size: 18,
                      color: LumenTokens.fgDimOf(context),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: LumenTokens.fgDimOf(context),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              GlassButton(
                icon: Icons.play_arrow_rounded,
                label: 'Play',
                primary: true,
                onPressed: onPlay,
              ),
              const SizedBox(width: 12),
              Opacity(
                opacity: onShuffle == null ? 0.4 : 1,
                child: GlassIconButton(
                  icon: Icons.shuffle_rounded,
                  size: 52,
                  iconSize: 22,
                  onTap: onShuffle,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AddSongsSheet extends ConsumerWidget {
  const _AddSongsSheet({required this.playlistId});

  final String playlistId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(allSongsProvider);
    final inPlaylist = ref.watch(playlistSongsProvider(playlistId));
    final inIds = inPlaylist.maybeWhen(
      data: (l) => l.map((s) => s.id).toSet(),
      orElse: () => <String>{},
    );

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      builder: (ctx, scroll) => Glass(
        strong: true,
        shape: const BorderRadius.vertical(top: Radius.circular(24)),
        child: Column(
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(top: 10, bottom: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Add songs',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                    color: LumenTokens.fg(context),
                  ),
                ),
              ),
            ),
            Expanded(
              child: ShaderMask(
                shaderCallback: (rect) => const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black,
                    Colors.black,
                    Colors.transparent,
                  ],
                  stops: [0.0, 0.045, 0.96, 1.0],
                ).createShader(rect),
                blendMode: BlendMode.dstIn,
                child: all.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Center(child: Text('Error: $e')),
                  data: (songs) => ListView.builder(
                    controller: scroll,
                    padding: const EdgeInsets.only(bottom: 12),
                    itemCount: songs.length,
                    itemBuilder: (context, i) {
                      final song = songs[i];
                      final already = inIds.contains(song.id);
                      return SongTile(
                        song: song,
                        trailing: Icon(
                          already ? Icons.check_rounded : Icons.add_rounded,
                          size: 20,
                          color: already
                              ? LumenTokens.accent
                              : LumenTokens.fgDimOf(context),
                        ),
                        onTap: already
                            ? null
                            : () async {
                                await ref
                                    .read(libraryActionsProvider)
                                    .addToPlaylist(
                                      playlistId: playlistId,
                                      songId: song.id,
                                    );
                              },
                      );
                    },
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

class _Empty extends ConsumerWidget {
  const _Empty({required this.playlistId});

  final String playlistId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.queue_music,
              size: 88,
              color: LumenTokens.fgDim2Of(context),
            ),
            const SizedBox(height: 16),
            Text(
              'No songs in this playlist yet',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: LumenTokens.fg(context),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Tap "Add songs" to pick from your library.',
              textAlign: TextAlign.center,
              style: TextStyle(color: LumenTokens.fgDimOf(context)),
            ),
          ],
        ),
      ),
    );
  }
}
