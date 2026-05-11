import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database/app_database.dart';
import '../../features/library/library_actions.dart';
import '../../features/playlists/providers.dart';

/// Long-press action sheet for a single song. Includes favorite toggle and
/// "Add to playlist" with inline create.
class SongActionsSheet extends ConsumerWidget {
  const SongActionsSheet({super.key, required this.song});

  final SongRow song;

  static Future<void> show(BuildContext context, SongRow song) {
    return showModalBottomSheet<void>(
      context: context,
      builder: (_) => SongActionsSheet(song: song),
    );
  }

  Future<void> _addToPlaylist(BuildContext context, WidgetRef ref) async {
    Navigator.of(context).pop();
    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _PickPlaylistSheet(song: song),
    );
  }

  Future<void> _toggleFavorite(BuildContext context, WidgetRef ref) async {
    await ref.read(libraryActionsProvider).toggleFavorite(song);
    if (!context.mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isFav = song.isFavorite == 1;
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.music_note),
            title: Text(
              song.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              song.artist ?? 'Unknown artist',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: Icon(isFav ? Icons.favorite : Icons.favorite_border),
            title: Text(isFav ? 'Remove from favorites' : 'Add to favorites'),
            onTap: () => _toggleFavorite(context, ref),
          ),
          ListTile(
            leading: const Icon(Icons.playlist_add),
            title: const Text('Add to playlist'),
            onTap: () => _addToPlaylist(context, ref),
          ),
        ],
      ),
    );
  }
}

class _PickPlaylistSheet extends ConsumerWidget {
  const _PickPlaylistSheet({required this.song});

  final SongRow song;

  Future<void> _createAndAdd(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New playlist'),
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
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    await ref.read(libraryActionsProvider).createPlaylistWithSong(
          name: name,
          songId: song.id,
        );
    if (!context.mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Added to "$name"')),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlists = ref.watch(allPlaylistsProvider);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.5,
      maxChildSize: 0.85,
      builder: (ctx, scroll) => Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Add to playlist'),
          ),
          Expanded(
            child: playlists.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (list) => ListView(
                controller: scroll,
                children: [
                  ListTile(
                    leading: const Icon(Icons.add),
                    title: const Text('Create new playlist'),
                    onTap: () => _createAndAdd(context, ref),
                  ),
                  const Divider(height: 1),
                  ...list.map(
                    (pl) => ListTile(
                      leading: const Icon(Icons.queue_music),
                      title: Text(pl.name),
                      onTap: () async {
                        await ref.read(libraryActionsProvider).addToPlaylist(
                              playlistId: pl.id,
                              songId: song.id,
                            );
                        if (!context.mounted) return;
                        Navigator.of(context).pop();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Added to "${pl.name}"')),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
