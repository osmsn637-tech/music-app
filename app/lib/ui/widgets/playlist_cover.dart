import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/playlists/providers.dart';
import 'album_art.dart';

/// Playlist cover: 2×2 mosaic of the first four songs' artwork. Falls
/// back to a single cover when the playlist has one song, and to the
/// gradient generator when the playlist is still empty.
class PlaylistCover extends ConsumerWidget {
  const PlaylistCover({
    super.key,
    required this.playlistId,
    required this.size,
    this.radius = 12,
  });

  final String playlistId;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final songs =
        ref.watch(playlistSongsProvider(playlistId)).valueOrNull ?? const [];

    if (songs.isEmpty) {
      return AlbumArt(seed: 'pl_$playlistId', size: size, radius: radius);
    }
    if (songs.length < 4) {
      final s = songs.first;
      return AlbumArt(
        artworkPath: s.localArtworkPath,
        seed: s.id,
        size: size,
        radius: radius,
      );
    }

    final tile = size / 2;
    Widget art(int i) {
      final s = songs[i];
      return AlbumArt(
        artworkPath: s.localArtworkPath,
        seed: s.id,
        size: tile,
        radius: 0,
      );
    }

    return SizedBox(
      width: size,
      height: size,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(mainAxisSize: MainAxisSize.min, children: [art(0), art(1)]),
            Row(mainAxisSize: MainAxisSize.min, children: [art(2), art(3)]),
          ],
        ),
      ),
    );
  }
}
