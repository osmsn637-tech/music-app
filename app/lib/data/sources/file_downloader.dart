import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/constants/app_constants.dart';

class StorageLayout {
  StorageLayout(this.root);

  final Directory root;

  Directory get music => Directory(p.join(root.path, AppConstants.musicDirName));
  Directory get lyrics =>
      Directory(p.join(root.path, AppConstants.lyricsDirName));
  Directory get artwork =>
      Directory(p.join(root.path, AppConstants.artworkDirName));
  Directory get artists =>
      Directory(p.join(root.path, AppConstants.artistsDirName));

  Future<void> ensureDirs() async {
    for (final d in [music, lyrics, artwork, artists]) {
      if (!await d.exists()) {
        await d.create(recursive: true);
      }
    }
  }
}

class FileDownloader {
  FileDownloader(this._dio);

  final Dio _dio;
  StorageLayout? _layout;

  Future<StorageLayout> layout() async {
    if (_layout != null) return _layout!;
    final root = await getApplicationDocumentsDirectory();
    final layout = StorageLayout(root);
    await layout.ensureDirs();
    _layout = layout;
    return layout;
  }

  /// Downloads [url] into [destination]. Writes to `${destination}.part` and
  /// renames on success so a killed download can't leave a corrupt file the
  /// DB later thinks is valid. Returns the final path.
  Future<String> download({
    required String url,
    required File destination,
    void Function(int received, int total)? onProgress,
  }) async {
    final part = File('${destination.path}.part');
    if (await part.exists()) {
      await part.delete();
    }
    try {
      await _dio.download(
        url,
        part.path,
        onReceiveProgress: onProgress,
        options: Options(receiveTimeout: const Duration(minutes: 5)),
      );
      if (await destination.exists()) {
        await destination.delete();
      }
      await part.rename(destination.path);
      return destination.path;
    } catch (_) {
      if (await part.exists()) {
        try {
          await part.delete();
        } catch (_) {}
      }
      rethrow;
    }
  }

  /// Tries to delete a file silently. Used during the auto-delete pass.
  Future<void> deleteIfExists(String? path) async {
    if (path == null) return;
    final f = File(path);
    if (await f.exists()) {
      try {
        await f.delete();
      } catch (_) {}
    }
  }
}
