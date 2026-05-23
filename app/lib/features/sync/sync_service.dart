import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;

import '../../data/database/app_database.dart';
import '../../data/models/remote_song.dart';
import '../../data/repositories/song_repository.dart';
import '../../data/sources/file_downloader.dart';
import '../../data/sources/manifest_api.dart';
import 'sync_models.dart';

typedef SyncProgressListener = void Function(SyncProgress progress);

class SyncService {
  SyncService({
    required this.api,
    required this.downloader,
    required this.repo,
    required this.db,
  });

  final ManifestApi api;
  final FileDownloader downloader;
  final SongRepository repo;
  final AppDatabase db;

  Future<void> sync({
    required String baseUrl,
    required SyncProgressListener onProgress,
  }) async {
    var progress = const SyncProgress(
      running: true,
      message: 'Fetching manifest…',
    );
    onProgress(progress);

    final ManifestResult manifest;
    try {
      manifest = await api.fetch(baseUrl);
    } catch (e) {
      onProgress(
        progress.copyWith(running: false, error: 'Manifest fetch failed: $e'),
      );
      return;
    }

    final remoteIds = manifest.songs.map((s) => s.id).toSet();
    final existingIds = await repo.existingIds();
    final layout = await downloader.layout();

    final orphanIds = existingIds.difference(remoteIds);
    final toDownload = manifest.songs
        .where((s) => !existingIds.contains(s.id))
        .toList();
    final toSkip = manifest.songs
        .where((s) => existingIds.contains(s.id))
        .toList();

    var items = <SyncItem>[
      for (final s in toDownload)
        SyncItem(id: s.id, title: s.title, status: SyncItemStatus.pending),
      for (final s in toSkip)
        SyncItem(id: s.id, title: s.title, status: SyncItemStatus.skipped),
      for (final id in orphanIds)
        SyncItem(id: id, title: id, status: SyncItemStatus.pending),
    ];
    progress = progress.copyWith(
      items: items,
      message: '${toDownload.length} new, ${toSkip.length} already local, '
          '${orphanIds.length} to remove',
    );
    onProgress(progress);

    // 1. Auto-delete orphans (per user choice: remove from DB + disk).
    for (final id in orphanIds) {
      final row = await repo.findById(id);
      if (row != null) {
        await downloader.deleteIfExists(row.localFilePath);
        await downloader.deleteIfExists(row.localLyricsPath);
        await downloader.deleteIfExists(row.localArtworkPath);
        await repo.deleteById(id);
      }
      items = _updateItem(
        items,
        id,
        (it) => it.copyWith(status: SyncItemStatus.deleted),
      );
      progress = progress.copyWith(items: items);
      onProgress(progress);
    }

    // 2. Download new songs.
    for (final song in toDownload) {
      items = _updateItem(
        items,
        song.id,
        (it) => it.copyWith(status: SyncItemStatus.downloading),
      );
      progress = progress.copyWith(
        items: items,
        message: 'Downloading ${song.title}…',
      );
      onProgress(progress);

      try {
        final mp3Path = await _downloadAudio(song, layout, (received, total) {
          items = _updateItem(
            items,
            song.id,
            (it) => it.copyWith(
              bytesReceived: received,
              bytesTotal: total > 0 ? total : it.bytesTotal,
            ),
          );
          progress = progress.copyWith(items: items);
          onProgress(progress);
        });
        final lyricsPath = await _downloadOptional(
          url: song.lyricsUrl,
          dir: layout.lyrics,
          fileName: '${song.id}${p.extension(song.lyricsUrl ?? '.lrc')}',
        );
        final artworkPath = await _downloadOptional(
          url: song.artworkUrl,
          dir: layout.artwork,
          fileName: '${song.id}${p.extension(song.artworkUrl ?? '.jpg')}',
        );

        await repo.insert(
          _toCompanion(
            song,
            localFilePath: mp3Path,
            localLyricsPath: lyricsPath,
            localArtworkPath: artworkPath,
          ),
        );

        items = _updateItem(
          items,
          song.id,
          (it) => it.copyWith(status: SyncItemStatus.success),
        );
      } catch (e) {
        items = _updateItem(
          items,
          song.id,
          (it) => it.copyWith(
            status: SyncItemStatus.failed,
            error: e.toString(),
          ),
        );
      }
      progress = progress.copyWith(items: items);
      onProgress(progress);
    }

    // 3. Repair existing songs — re-fetch any artwork or synced lyrics the
    // server now has but that we don't have locally. Catches songs that
    // were synced before the server-side repair pass added their cover or
    // before LRCLib had synced lyrics for them.
    final repairCount =
        await _repairExistingSongs(manifest, layout, (item) {
      items = _replaceItem(items, item);
      progress = progress.copyWith(items: items);
      onProgress(progress);
    }, (msg) {
      progress = progress.copyWith(message: msg);
      onProgress(progress);
    });

    // 4. Download new artist profile pictures. Doesn't gate sync — failures
    // here just mean the gradient placeholder shows in the UI.
    if (manifest.artists.isNotEmpty) {
      progress = progress.copyWith(
        message: 'Downloading ${manifest.artists.length} artist photo(s)…',
      );
      onProgress(progress);
      await _syncArtistImages(manifest, layout);
    }

    onProgress(
      progress.copyWith(
        running: false,
        message: 'Sync complete: ${progress.done} new, '
            '$repairCount repaired, '
            '${progress.skipped - repairCount} already local, '
            '${progress.deleted} removed, '
            '${progress.failed} failed',
      ),
    );
  }

  /// Walks every song that's already in the local DB and re-fetches any
  /// artwork or synced lyrics the server now has but we don't. Returns the
  /// number of songs that received at least one repaired asset.
  Future<int> _repairExistingSongs(
    ManifestResult manifest,
    StorageLayout layout,
    void Function(SyncItem) onItemUpdate,
    void Function(String) onMessage,
  ) async {
    final byId = {for (final s in manifest.songs) s.id: s};
    final existingIds = await repo.existingIds();
    final candidates = <RemoteSong>[];
    for (final id in existingIds) {
      final remote = byId[id];
      if (remote == null) continue;
      candidates.add(remote);
    }

    var repaired = 0;
    for (var i = 0; i < candidates.length; i++) {
      final remote = candidates[i];
      final row = await repo.findById(remote.id);
      if (row == null) continue;

      // Metadata drift: server-side repair (title / artist / album cleanup)
      // means the manifest may now disagree with the row in the local DB.
      // Refresh those fields without re-downloading the audio.
      final metadataChanged = _metadataDiffers(row, remote);

      // Lyrics drift: the local file may still exist with valid
      // timestamps but be a stale 1-line whisper transcription that the
      // server has since replaced with a 60-line vocal-isolated version.
      // The manifest's `lyricsSize` is the authoritative signal —
      // bytes-different means the server has a newer file at the same URL.
      final lyricsSizeDiffers =
          await _serverSizeDiffers(remote.lyricsSize, row.localLyricsPath);
      final lyricsMissing = remote.lyricsUrl != null &&
          (!await _localLyricsOk(row.localLyricsPath) || lyricsSizeDiffers);

      // Artwork drift signals, in order of cheapness to check:
      //   1. file missing,
      //   2. remote URL basename differs (extension changed .jpg→.png),
      //   3. metadata changed (album rename usually coincides with a swap),
      //   4. server file size differs from local size — catches the
      //      "manually swapped cover bytes, same filename" case that the
      //      first 3 signals miss entirely.
      final artworkBasenameDiffers = remote.artworkUrl != null &&
          row.localArtworkPath != null &&
          p.basename(remote.artworkUrl!) != p.basename(row.localArtworkPath!);
      final artworkSizeDiffers =
          await _serverSizeDiffers(remote.artworkSize, row.localArtworkPath);
      final artworkMissing = remote.artworkUrl != null &&
          (!await _localFileOk(row.localArtworkPath) ||
              artworkBasenameDiffers ||
              artworkSizeDiffers ||
              metadataChanged);
      if (!artworkMissing && !lyricsMissing && !metadataChanged) continue;

      onMessage('Repairing ${remote.title}…');

      String? newArtworkPath = row.localArtworkPath;
      String? newLyricsPath = row.localLyricsPath;
      var didRepair = false;

      if (artworkMissing) {
        final path = await _downloadOptional(
          url: remote.artworkUrl,
          dir: layout.artwork,
          fileName:
              '${remote.id}${p.extension(remote.artworkUrl ?? '.jpg')}',
        );
        if (path != null) {
          newArtworkPath = path;
          didRepair = true;
        }
      }

      if (lyricsMissing) {
        final path = await _downloadOptional(
          url: remote.lyricsUrl,
          dir: layout.lyrics,
          fileName:
              '${remote.id}${p.extension(remote.lyricsUrl ?? '.lrc')}',
        );
        if (path != null) {
          newLyricsPath = path;
          didRepair = true;
        }
      }

      if (metadataChanged) {
        await repo.updateMetadata(
          id: remote.id,
          title: remote.title,
          artist: remote.artist,
          album: remote.album,
          genre: remote.genre,
          mood: remote.mood,
          bpm: remote.bpm,
          durationMs: remote.durationMs,
          fileName: remote.fileName,
          searchText: remote.searchText,
        );
        didRepair = true;
      }

      if (didRepair) {
        if (artworkMissing || lyricsMissing) {
          await repo.updateLocalAssets(
            id: remote.id,
            localArtworkPath: newArtworkPath,
            localLyricsPath: newLyricsPath,
          );
        }
        repaired += 1;
        onItemUpdate(SyncItem(
          id: remote.id,
          title: remote.title,
          status: SyncItemStatus.repaired,
        ));
      }
    }
    return repaired;
  }

  /// True if any of the metadata fields the server can change differ from
  /// what's stored locally. Excludes file paths (those are local concerns)
  /// and listening history (favorite / play counts / lastPlayedAt).
  bool _metadataDiffers(SongRow row, RemoteSong remote) {
    return row.title != remote.title ||
        row.artist != remote.artist ||
        row.album != remote.album ||
        row.genre != remote.genre ||
        row.mood != remote.mood ||
        row.bpm != remote.bpm ||
        row.durationMs != remote.durationMs ||
        row.fileName != remote.fileName ||
        row.searchText != remote.searchText;
  }

  /// True if the manifest's [serverSize] is known and disagrees with the
  /// local file's actual size — the bytes-changed-but-same-URL signal.
  /// Returns false when the server omitted the size (older manifests) or
  /// when the local file simply doesn't exist (the missing-file check
  /// already covers that case elsewhere).
  Future<bool> _serverSizeDiffers(int? serverSize, String? localPath) async {
    if (serverSize == null) return false;
    if (localPath == null || localPath.isEmpty) return false;
    final f = File(localPath);
    if (!await f.exists()) return false;
    try {
      return (await f.length()) != serverSize;
    } catch (_) {
      return false;
    }
  }

  /// True if [path] points to a non-empty file that exists. Null / missing
  /// counts as "needs repair".
  Future<bool> _localFileOk(String? path) async {
    if (path == null || path.isEmpty) return false;
    final f = File(path);
    if (!await f.exists()) return false;
    try {
      return (await f.length()) > 0;
    } catch (_) {
      return false;
    }
  }

  /// Like [_localFileOk] but also requires that an `.lrc` file actually
  /// has time-synced lines. Plain-text LRCs are treated as needing repair
  /// so we can pull the upgraded server-side version.
  Future<bool> _localLyricsOk(String? path) async {
    if (!await _localFileOk(path)) return false;
    try {
      final content = await File(path!).readAsString();
      // At least two `[mm:ss.xx]` timestamps means it's really synced.
      final pattern = RegExp(
        r'^\s*\[\d{1,3}:\d{1,2}(?:[.:]\d{1,3})?\]',
        multiLine: true,
      );
      return pattern.allMatches(content).length >= 2;
    } catch (_) {
      return false;
    }
  }

  List<SyncItem> _replaceItem(List<SyncItem> items, SyncItem updated) {
    final idx = items.indexWhere((it) => it.id == updated.id);
    if (idx < 0) return [...items, updated];
    final copy = [...items];
    copy[idx] = updated;
    return copy;
  }

  Future<void> _syncArtistImages(
    ManifestResult manifest,
    StorageLayout layout,
  ) async {
    for (final artist in manifest.artists) {
      // Reuse the file's extension from the URL so the local filename
      // matches what the server has (helps keep the lookup deterministic).
      final ext = p.extension(artist.imageUrl);
      final fileName =
          ext.isEmpty ? '${artist.id}.jpg' : '${artist.id}$ext';
      final dest = File(p.join(layout.artists.path, fileName));
      if (await dest.exists()) continue;
      try {
        await downloader.download(url: artist.imageUrl, destination: dest);
      } catch (_) {
        // Best-effort — skip and let the gradient render in the UI.
      }
    }
  }

  Future<String> _downloadAudio(
    RemoteSong song,
    StorageLayout layout,
    void Function(int, int) onProgress,
  ) async {
    final ext = p.extension(song.fileName).isNotEmpty
        ? p.extension(song.fileName)
        : '.mp3';
    final dest = File(p.join(layout.music.path, '${song.id}$ext'));
    return downloader.download(
      url: song.audioUrl,
      destination: dest,
      onProgress: onProgress,
    );
  }

  Future<String?> _downloadOptional({
    required String? url,
    required Directory dir,
    required String fileName,
  }) async {
    if (url == null || url.isEmpty) return null;
    try {
      final dest = File(p.join(dir.path, fileName));
      return await downloader.download(url: url, destination: dest);
    } catch (_) {
      // Optional asset — sync should still succeed without it.
      return null;
    }
  }

  SongsCompanion _toCompanion(
    RemoteSong song, {
    required String localFilePath,
    String? localLyricsPath,
    String? localArtworkPath,
  }) {
    return SongsCompanion.insert(
      id: song.id,
      title: song.title,
      artist: Value(song.artist),
      album: Value(song.album),
      genre: Value(song.genre),
      mood: Value(song.mood),
      bpm: Value(song.bpm),
      durationMs: Value(song.durationMs),
      fileName: Value(song.fileName),
      localFilePath: localFilePath,
      localLyricsPath: Value(localLyricsPath),
      localArtworkPath: Value(localArtworkPath),
      searchText: Value(song.searchText),
      addedAt: Value(DateTime.now().toIso8601String()),
    );
  }

  List<SyncItem> _updateItem(
    List<SyncItem> items,
    String id,
    SyncItem Function(SyncItem) updater,
  ) {
    return [
      for (final item in items)
        if (item.id == id) updater(item) else item,
    ];
  }
}
