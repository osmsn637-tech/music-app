import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show AssetManifest, rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../data/database/app_database.dart';

/// Inserts a single demo row — "a lot" by 21 Savage — so the simulator
/// has something to test on when the Wi-Fi sync server isn't reachable.
///
/// On each [run], any bundled files under `assets/sample_songs/` are
/// copied to `<app docs>/sample_songs/` and the seeded row is pointed
/// at them. Drop `a_lot.<ext>` in that directory for each of:
///   audio  — mp3 / m4a / opus / wav / aac / flac
///   cover  — jpg / jpeg / png / webp
///   lyrics — lrc
/// Anything missing keeps the placeholder: `/dev/null/dev_alot.mp3`
/// for audio, null for cover (procedural gradient), null for lyrics.
///
/// The row uses an `dev_` id prefix so [run] / [clear] only ever touch
/// their own inserts.
class DevSeed {
  DevSeed(this._db);

  final AppDatabase _db;

  static const String _docsSubdir = 'sample_songs';
  static const String _bundlePrefix = 'assets/sample_songs/';

  /// The one song we seed. Kept as a const so the asset slug, title,
  /// and id stay in sync.
  static const _SongSpec _aLot = _SongSpec(
    title: 'a lot',
    artist: '21 Savage',
    album: 'I Am > I Was',
    genre: 'Hip-Hop',
    mood: 'chill',
    bpm: 75,
    durationMs: 287000,
    assetBase: 'a_lot',
  );
  static const String _aLotId = 'dev_alot';

  Future<void> run() async {
    await clear();

    final sampleDir = await _ensureSamplesExtracted();
    final files = sampleDir != null && await sampleDir.exists()
        ? sampleDir.listSync().whereType<File>().toList()
        : <File>[];

    final audio = _findFile(files, _aLot.assetBase, _audioExts);
    final art = _findFile(files, _aLot.assetBase, _imageExts);
    final lrc = _findFile(files, _aLot.assetBase, const {'lrc'});
    final searchText = [
      _aLot.title,
      _aLot.artist,
      _aLot.album,
      _aLot.genre,
      _aLot.mood,
    ].join(' ').toLowerCase();

    final row = SongsCompanion.insert(
      id: _aLotId,
      title: _aLot.title,
      artist: Value(_aLot.artist),
      album: Value(_aLot.album),
      genre: Value(_aLot.genre),
      mood: Value(_aLot.mood),
      bpm: Value(_aLot.bpm),
      durationMs: Value(_aLot.durationMs),
      fileName: Value(audio != null ? p.basename(audio) : '$_aLotId.mp3'),
      localFilePath: audio ?? '/dev/null/$_aLotId.mp3',
      localLyricsPath: Value(lrc),
      localArtworkPath: Value(art),
      searchText: Value(searchText),
      addedAt: Value(DateTime.now().toIso8601String()),
    );

    await _db
        .into(_db.songs)
        .insert(row, mode: InsertMode.insertOrReplace);
  }

  Future<void> clear() async {
    await (_db.delete(_db.songs)
          ..where((s) => s.id.like('dev_%')))
        .go();
  }

  // ─── Asset extraction ─────────────────────────────────────────────

  /// Copies every bundled asset under [_bundlePrefix] to
  /// `<docs>/<_docsSubdir>/`. Each file is rewritten only if its on-
  /// disk size differs from the bundled one — keeps re-taps cheap.
  /// Returns the destination dir, or null when no bundled samples
  /// were found.
  Future<Directory?> _ensureSamplesExtracted() async {
    final List<String> bundled;
    try {
      final manifest =
          await AssetManifest.loadFromAssetBundle(rootBundle);
      bundled = manifest
          .listAssets()
          .where((path) => path.startsWith(_bundlePrefix))
          .where((path) => !path.endsWith('/README.txt'))
          .toList();
    } catch (e) {
      debugPrint('[dev-seed] manifest load failed: $e');
      return null;
    }
    if (bundled.isEmpty) return null;

    final docs = await getApplicationDocumentsDirectory();
    final target = Directory(p.join(docs.path, _docsSubdir));
    if (!await target.exists()) {
      await target.create(recursive: true);
    }

    var extracted = 0;
    for (final assetPath in bundled) {
      final relative = assetPath.substring(_bundlePrefix.length);
      if (relative.isEmpty) continue;
      final out = File(p.join(target.path, relative));
      if (!await out.parent.exists()) {
        await out.parent.create(recursive: true);
      }
      final bytes = await rootBundle.load(assetPath);
      final asUint8 = bytes.buffer.asUint8List(
        bytes.offsetInBytes,
        bytes.lengthInBytes,
      );
      if (await out.exists() && (await out.length()) == asUint8.length) {
        continue;
      }
      await out.writeAsBytes(asUint8, flush: true);
      extracted += 1;
    }
    if (extracted > 0) {
      debugPrint(
          '[dev-seed] extracted $extracted sample files to ${target.path}');
    }
    return target;
  }

  static const Set<String> _audioExts = {
    'mp3', 'm4a', 'opus', 'wav', 'aac', 'flac',
  };
  static const Set<String> _imageExts = {
    'jpg', 'jpeg', 'png', 'webp',
  };

  /// Returns the first file in [files] whose basename matches
  /// [assetBase] and whose extension is in [exts], case-insensitively.
  /// Returns null when nothing matches.
  String? _findFile(List<File> files, String assetBase, Set<String> exts) {
    final wantBase = assetBase.toLowerCase();
    for (final f in files) {
      final base = p.basenameWithoutExtension(f.path).toLowerCase();
      if (base != wantBase) continue;
      final ext = p.extension(f.path).toLowerCase().replaceFirst('.', '');
      if (exts.contains(ext)) return f.path;
    }
    return null;
  }
}

class _SongSpec {
  const _SongSpec({
    required this.title,
    required this.artist,
    required this.album,
    required this.genre,
    required this.mood,
    required this.bpm,
    required this.assetBase,
    this.durationMs = 200000,
  });
  final String title;
  final String artist;
  final String album;
  final String genre;
  final String mood;
  final int bpm;
  final int durationMs;

  /// Basename used to look up audio / cover / lyrics under
  /// `assets/sample_songs/` (or `<docs>/sample_songs/` post-extract).
  final String assetBase;
}
