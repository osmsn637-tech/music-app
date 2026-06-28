import 'package:flutter/material.dart';

import '../../features/nav/content_navigator_scope.dart';
import '../motion/lumen_route.dart';
import 'album_detail_screen.dart';
import 'artist_detail_screen.dart';

/// Shared navigation helpers so every surface (song tiles, search, library,
/// the player, the context menu) links to artist/album pages the same way.

/// Prefer the shell's inner content Navigator so detail pages open INSIDE the
/// content area (keeping the bottom player + chrome) even when the caller — the
/// desktop sidebar, the player bar, a root-overlay sheet — sits outside it.
/// Falls back to the nearest Navigator when no inner stack exists.
NavigatorState contentNavigator(BuildContext context) =>
    ContentNavigatorScope.maybeOf(context)?.currentState ??
    Navigator.of(context);

void openArtist(BuildContext context, String? name) {
  final n = name?.trim() ?? '';
  if (n.isEmpty) return;
  contentNavigator(context).pushLumen((_) => ArtistDetailScreen(artist: n));
}

void openAlbum(BuildContext context, String? name) {
  final n = name?.trim() ?? '';
  if (n.isEmpty) return;
  contentNavigator(context).pushLumen((_) => AlbumDetailScreen(album: n));
}
