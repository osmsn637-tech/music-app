import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database/app_database.dart';
import '../../features/library/library_actions.dart';
import '../../features/library/providers.dart';
import '../../features/player/now_playing_controller.dart';
import '../../features/player/providers.dart';
import '../../features/playlists/providers.dart';
import '../../features/player/player_expansion_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/playlist_cover.dart';
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

  Future<void> _rename(BuildContext context, WidgetRef ref, PlaylistRow pl) async {
    final controller = TextEditingController(text: pl.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename playlist'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (newName != null && newName.isNotEmpty && newName != pl.name) {
      await ref.read(playlistRepositoryProvider).rename(pl.id, newName);
    }
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    PlaylistRow pl,
  ) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete playlist?'),
        content: Text(
          'Removes "${pl.name}". The songs themselves are not deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await ref.read(playlistRepositoryProvider).delete(pl.id);
    if (!context.mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pl = ref.watch(allPlaylistsProvider).maybeWhen(
          data: (list) => list.where((p) => p.id == playlistId).firstOrNull,
          orElse: () => null,
        );
    final songs = ref.watch(playlistSongsProvider(playlistId));
    final nowPlayingId = ref.watch(nowPlayingProvider)?.id;
    final isPlaying =
        ref.watch(playerStateStreamProvider).valueOrNull?.playing ?? false;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          if (pl != null)
            PopupMenuButton<String>(
              onSelected: (action) async {
                if (action == 'rename') await _rename(context, ref, pl);
                if (action == 'delete') {
                  if (!context.mounted) return;
                  await _delete(context, ref, pl);
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'rename', child: Text('Rename')),
                PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            ),
        ],
      ),
      extendBodyBehindAppBar: true,
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
              children: [header, _Empty(playlistId: playlistId)],
            );
          }
          return ReorderableListView.builder(
            header: header,
            itemCount: list.length,
            onReorder: (oldIndex, newIndex) {
              ref.read(playlistRepositoryProvider).reorder(
                    playlistId: playlistId,
                    oldIndex: oldIndex,
                    newIndex: newIndex,
                  );
            },
            itemBuilder: (context, i) {
              final song = list[i];
              final active = nowPlayingId == song.id;
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
                    PlayerExpansionScope.read(context).expand();
                  } else {
                    _openSong(context, ref, list, i);
                  }
                },
                trailing: ReorderableDragStartListener(
                  index: i,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Icon(Icons.drag_handle),
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('Add songs'),
        onPressed: () => _showAddSongs(context, ref),
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

    final topInset = MediaQuery.of(context).padding.top + kToolbarHeight;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        LumenTokens.pagePad,
        topInset + 8,
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
              _PlayPillButton(
                icon: Icons.play_arrow_rounded,
                label: 'Play',
                onTap: onPlay,
              ),
              const SizedBox(width: 12),
              _IconCircleButton(
                icon: Icons.shuffle_rounded,
                onTap: onShuffle,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PlayPillButton extends StatelessWidget {
  const _PlayPillButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: Material(
        color: LumenTokens.accent,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 24, color: Colors.white),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _IconCircleButton extends StatelessWidget {
  const _IconCircleButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: Material(
        color: Colors.white.withValues(alpha: 0.08),
        shape: const CircleBorder(),
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: 48,
            height: 48,
            child: Icon(icon, size: 22, color: LumenTokens.fg(context)),
          ),
        ),
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
      builder: (ctx, scroll) => Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Add songs'),
          ),
          Expanded(
            child: all.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (songs) => ListView.builder(
                controller: scroll,
                itemCount: songs.length,
                itemBuilder: (context, i) {
                  final song = songs[i];
                  final already = inIds.contains(song.id);
                  return SongTile(
                    song: song,
                    trailing: already
                        ? const Icon(Icons.check, size: 20)
                        : const Icon(Icons.add),
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
        ],
      ),
    );
  }
}

class _Empty extends ConsumerWidget {
  const _Empty({required this.playlistId});

  final String playlistId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.queue_music, size: 96, color: scheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(
              'No songs in this playlist yet',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Tap "Add songs" to pick from your library.',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
