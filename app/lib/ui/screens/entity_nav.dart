import 'package:flutter/material.dart';

import '../motion/lumen_route.dart';
import 'album_detail_screen.dart';
import 'artist_detail_screen.dart';

/// Shared navigation helpers so every surface (song tiles, search, library,
/// the player, the context menu) links to artist/album pages the same way.

void openArtist(BuildContext context, String? name) {
  final n = name?.trim() ?? '';
  if (n.isEmpty) return;
  Navigator.of(context).pushLumen((_) => ArtistDetailScreen(artist: n));
}

void openAlbum(BuildContext context, String? name) {
  final n = name?.trim() ?? '';
  if (n.isEmpty) return;
  Navigator.of(context).pushLumen((_) => AlbumDetailScreen(album: n));
}
