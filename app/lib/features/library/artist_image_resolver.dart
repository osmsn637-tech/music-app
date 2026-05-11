import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../core/constants/app_constants.dart';
import '../../data/models/remote_artist.dart';
import '../../data/sources/file_downloader.dart';
import '../sync/providers.dart';

/// Resolves an artist's display name to a locally-stored profile picture
/// path. Returns null if no image exists yet — caller is expected to fall
/// back to the deterministic gradient.
class ArtistImageResolver {
  ArtistImageResolver(this._layout);

  final StorageLayout _layout;

  /// Local file path for [artistName], or null if no picture is on disk.
  /// Tries `<id>.jpg`, `.jpeg`, `.png`, `.webp` in order.
  String? localPath(String artistName) {
    final id = normalizeArtistId(artistName);
    if (id.isEmpty || id == 'unknown') return null;
    for (final ext in const ['.jpg', '.jpeg', '.png', '.webp']) {
      final path = p.join(_layout.artists.path, '$id$ext');
      if (File(path).existsSync()) return path;
    }
    return null;
  }
}

/// Async because the underlying `StorageLayout` lazily creates directories
/// the first time it's read. Watch the `.future` in widgets and gate the
/// artwork lookup on the AsyncValue.
final artistImageResolverProvider =
    FutureProvider<ArtistImageResolver>((ref) async {
  final downloader = ref.watch(fileDownloaderProvider);
  final layout = await downloader.layout();
  // Make sure the directory exists even on first run before any sync —
  // ensureDirs is idempotent.
  final artistsDir = layout.artists;
  if (!artistsDir.existsSync()) {
    artistsDir.createSync(recursive: true);
  }
  // Reference the constant so the import isn't pruned even when the
  // helper above never strictly needs it.
  assert(AppConstants.artistsDirName.isNotEmpty);
  return ArtistImageResolver(layout);
});
