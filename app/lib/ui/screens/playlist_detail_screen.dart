import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database/app_database.dart';
import '../../features/library/library_actions.dart';
import '../../features/library/providers.dart';
import '../../features/player/now_playing_controller.dart';
import '../../features/playlists/providers.dart';
import '../widgets/mini_player.dart' show openPlayerRoute;
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
    Navigator.of(context).push(openPlayerRoute());
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

    return Scaffold(
      appBar: AppBar(
        title: Text(pl?.name ?? 'Playlist'),
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
      body: songs.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (list) {
          if (list.isEmpty) {
            return _Empty(playlistId: playlistId);
          }
          return ReorderableListView.builder(
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
              return Dismissible(
                key: ValueKey(song.id),
                direction: DismissDirection.endToStart,
                background: Container(
                  color: Theme.of(context).colorScheme.errorContainer,
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 16),
                  child: Icon(
                    Icons.delete,
                    color: Theme.of(context).colorScheme.onErrorContainer,
                  ),
                ),
                onDismissed: (_) {
                  ref.read(playlistRepositoryProvider).removeSong(
                        playlistId: playlistId,
                        songId: song.id,
                      );
                },
                child: SongTile(
                  song: song,
                  onTap: () => _openSong(context, ref, list, i),
                  trailing: ReorderableDragStartListener(
                    index: i,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Icon(Icons.drag_handle),
                    ),
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
