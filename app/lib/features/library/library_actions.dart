import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database/app_database.dart';
import '../../data/database/providers.dart';
import '../../data/repositories/playlist_repository.dart';
import '../../data/repositories/song_repository.dart';
import '../player/listening_providers.dart';
import '../player/listening_tracker.dart';
import '../playlists/providers.dart';

/// Bundles common library write operations with their listening-tracker
/// emissions, so call sites can't accidentally do half the job.
class LibraryActions {
  LibraryActions({
    required SongRepository songs,
    required PlaylistRepository playlists,
    required ListeningTracker tracker,
  }) : _songs = songs,
       _playlists = playlists,
       _tracker = tracker;

  final SongRepository _songs;
  final PlaylistRepository _playlists;
  final ListeningTracker _tracker;

  Future<void> toggleFavorite(SongRow song) async {
    final nowFavorite = song.isFavorite != 1;
    await _songs.setFavorite(id: song.id, favorite: nowFavorite);
    await _tracker.onFavoriteToggled(songId: song.id, nowFavorite: nowFavorite);
  }

  Future<void> addToPlaylist({
    required String playlistId,
    required String songId,
  }) async {
    await _playlists.addSong(playlistId: playlistId, songId: songId);
    await _tracker.onAddedToPlaylist(songId);
  }

  Future<String> createPlaylistWithSong({
    required String name,
    required String songId,
  }) async {
    final id = await _playlists.create(name);
    await addToPlaylist(playlistId: id, songId: songId);
    return id;
  }

  /// Delete a song's downloaded files (audio + artwork + lyrics) and its
  /// library row. The track disappears until the next sync re-pulls it.
  Future<void> removeFromLibrary(SongRow song) async {
    for (final path in <String?>[
      song.localFilePath,
      song.localArtworkPath,
      song.localLyricsPath,
    ]) {
      if (path == null || path.isEmpty) continue;
      try {
        final f = File(path);
        if (await f.exists()) await f.delete();
      } catch (_) {
        // Best-effort — a missing/locked file shouldn't block the DB delete.
      }
    }
    await _songs.deleteById(song.id);
  }
}

final libraryActionsProvider = Provider<LibraryActions>((ref) {
  return LibraryActions(
    songs: ref.watch(songRepositoryProvider),
    playlists: ref.watch(playlistRepositoryProvider),
    tracker: ref.watch(listeningTrackerProvider),
  );
});
