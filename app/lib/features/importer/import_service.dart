import 'dart:io';

import 'package:drift/drift.dart' as drift;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../data/database/app_database.dart';
import '../../data/repositories/song_repository.dart';

/// Aggregate outcome of one import call. [added] is newly inserted rows;
/// [skipped] is files that already existed (same id) or weren't audio.
class ImportResult {
  const ImportResult({
    required this.added,
    required this.skipped,
    this.errors = const [],
  });

  final int added;
  final int skipped;
  final List<String> errors;

  bool get isEmpty => added == 0 && skipped == 0;
}

/// Copies audio files from arbitrary device locations into the app's
/// documents dir and registers them as `SongRow`s. Picker UI lives in the
/// Settings screen; this service is pure I/O + DB so it can be unit-tested
/// without a Flutter context.
class ImportService {
  ImportService(this._repo);

  final SongRepository _repo;

  static const Set<String> _audioExts = {
    '.mp3',
    '.m4a',
    '.aac',
    '.flac',
    '.wav',
    '.ogg',
    '.opus',
    '.wma',
  };

  static bool isAudioPath(String path) {
    return _audioExts.contains(p.extension(path).toLowerCase());
  }

  Future<Directory> _importsDir() async {
    final root = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(root.path, 'imports'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Stable id derived from basename + size — re-importing the same file
  /// from a different path lands on the same row, so the existing
  /// `insertOrIgnore` semantics keep the library deduplicated.
  String _idFor(File f) {
    final name = p.basename(f.path).toLowerCase();
    final size = f.lengthSync();
    return 'import:$name:$size';
  }

  /// "Artist - Title.mp3" → `(artist: 'Artist', title: 'Title')`. Falls
  /// back to the stem with no artist when no separator is present.
  ({String title, String? artist}) _splitTitle(String filename) {
    final stem = p.basenameWithoutExtension(filename).trim();
    final dash = stem.indexOf(' - ');
    if (dash > 0 && dash + 3 < stem.length) {
      final artist = stem.substring(0, dash).trim();
      final title = stem.substring(dash + 3).trim();
      if (artist.isNotEmpty && title.isNotEmpty) {
        return (artist: artist, title: title);
      }
    }
    return (artist: null, title: stem.isEmpty ? 'Untitled' : stem);
  }

  /// Imports [source]. Returns true if a new row was created, false if
  /// the file wasn't audio or an identical row already exists.
  Future<bool> importFile(File source) async {
    if (!await source.exists()) return false;
    if (!isAudioPath(source.path)) return false;

    final id = _idFor(source);
    final existing = await _repo.findById(id);
    if (existing != null) return false;

    final dir = await _importsDir();
    final safeId = id.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final dest = File(p.join(dir.path, '$safeId${p.extension(source.path)}'));

    if (!p.equals(source.path, dest.path)) {
      await source.copy(dest.path);
    }

    final parts = _splitTitle(p.basename(source.path));
    final now = DateTime.now().toIso8601String();
    final search = [parts.title, parts.artist]
        .whereType<String>()
        .where((s) => s.isNotEmpty)
        .join(' ')
        .toLowerCase();

    await _repo.insert(SongsCompanion.insert(
      id: id,
      title: parts.title,
      artist: drift.Value(parts.artist),
      localFilePath: dest.path,
      fileName: drift.Value(p.basename(source.path)),
      searchText: drift.Value(search),
      addedAt: drift.Value(now),
    ));

    return true;
  }

  /// Imports a list of files in order. [onProgress] fires before each
  /// file with (done, total, currentName) so the caller can drive a
  /// progress dialog.
  Future<ImportResult> importFiles(
    List<File> sources, {
    void Function(int done, int total, String currentName)? onProgress,
  }) async {
    var added = 0;
    var skipped = 0;
    final errors = <String>[];
    for (var i = 0; i < sources.length; i++) {
      final name = p.basename(sources[i].path);
      onProgress?.call(i, sources.length, name);
      try {
        final ok = await importFile(sources[i]);
        if (ok) {
          added++;
        } else {
          skipped++;
        }
      } catch (e) {
        errors.add('$name: $e');
      }
    }
    onProgress?.call(sources.length, sources.length, '');
    return ImportResult(added: added, skipped: skipped, errors: errors);
  }

  /// Recursively scans [folder] for audio files and imports each.
  Future<ImportResult> importFolder(
    Directory folder, {
    void Function(int done, int total, String currentName)? onProgress,
  }) async {
    final files = <File>[];
    try {
      await for (final entity in folder.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is File && isAudioPath(entity.path)) {
          files.add(entity);
        }
      }
    } catch (e) {
      return ImportResult(
        added: 0,
        skipped: 0,
        errors: ['Folder scan failed: $e'],
      );
    }
    if (files.isEmpty) {
      return const ImportResult(added: 0, skipped: 0);
    }
    return importFiles(files, onProgress: onProgress);
  }
}
