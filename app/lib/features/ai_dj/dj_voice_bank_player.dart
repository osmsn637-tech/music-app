import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle, AssetManifest;
import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'dj_voice_bank.dart';

class DjVoiceBank {
  const DjVoiceBank({required this.directory, required this.manifest});

  factory DjVoiceBank.empty(Directory directory) {
    return DjVoiceBank(
      directory: directory,
      manifest: DjVoiceBankManifest.empty(),
    );
  }

  final Directory directory;
  final DjVoiceBankManifest manifest;

  bool get isEmpty => manifest.isEmpty;
  DjVoiceBankSelector get selector => DjVoiceBankSelector(manifest);

  String resolvePath(DjVoiceClip clip) {
    if (p.isAbsolute(clip.path)) return p.normalize(clip.path);
    return p.normalize(p.join(directory.path, clip.path));
  }
}

class DjVoiceBankStore {
  DjVoiceBankStore({
    Future<Directory> Function()? documentsDirectory,
    Future<Directory?> Function()? externalDirectory,
  })  : _documentsDirectory =
            documentsDirectory ?? getApplicationDocumentsDirectory,
        _externalDirectory =
            externalDirectory ?? getExternalStorageDirectory;

  final Future<Directory> Function() _documentsDirectory;
  final Future<Directory?> Function() _externalDirectory;

  /// Resolution order for the bank, highest priority first:
  ///   1. External storage (`/sdcard/Android/data/<pkg>/files/dj_voice_bank/`).
  ///      Lets you `adb push` a freshly-rendered bank for dev testing
  ///      without rebuilding the APK.
  ///   2. App documents dir (extracted from bundled assets on first run).
  ///   3. If neither has a manifest yet, extract the bundled assets to
  ///      the app docs dir and load from there.
  Future<DjVoiceBank> load() async {
    try {
      final ext = await _externalDirectory();
      if (ext != null) {
        final extBank = Directory(p.join(ext.path, 'dj_voice_bank'));
        final extManifest = File(p.join(extBank.path, 'manifest.json'));
        if (await extManifest.exists()) {
          debugPrint('[dj-bank] loading from external: ${extBank.path}');
          return loadFromDirectory(extBank);
        }
      }
    } catch (e) {
      debugPrint('[dj-bank] external storage check failed: $e');
    }

    final docs = await _documentsDirectory();
    final docsBank = Directory(p.join(docs.path, 'dj_voice_bank'));
    final docsManifest = File(p.join(docsBank.path, 'manifest.json'));

    // Re-extract whenever the bundled manifest differs from the on-disk
    // one. This way every app update with a new bank gets picked up
    // without requiring the user to clear app data — the bundled manifest
    // is the source of truth.
    try {
      await _extractIfBundleChanged(docsBank, docsManifest);
    } catch (e, st) {
      debugPrint('[dj-bank] asset extraction failed: $e\n$st');
    }

    debugPrint('[dj-bank] loading from internal: ${docsBank.path}');
    return loadFromDirectory(docsBank);
  }

  static Future<void> _extractIfBundleChanged(
    Directory target,
    File onDiskManifest,
  ) async {
    String? bundledManifest;
    try {
      bundledManifest =
          await rootBundle.loadString('assets/dj_voice_bank/manifest.json');
    } catch (_) {
      // No bundled manifest -> nothing to extract.
      return;
    }

    if (await onDiskManifest.exists()) {
      final onDisk = await onDiskManifest.readAsString();
      if (onDisk == bundledManifest) {
        return; // Already in sync.
      }
      debugPrint('[dj-bank] bundled manifest changed, re-extracting');
    } else {
      debugPrint('[dj-bank] no on-disk manifest, extracting bundle');
    }
    await _extractBundledAssetsTo(target);
  }

  static Future<void> _extractBundledAssetsTo(Directory target) async {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final assetPaths = manifest
        .listAssets()
        .where((path) => path.startsWith('assets/dj_voice_bank/'))
        .toList();
    if (assetPaths.isEmpty) {
      debugPrint('[dj-bank] no bundled assets found under assets/dj_voice_bank/');
      return;
    }

    if (!await target.exists()) {
      await target.create(recursive: true);
    }

    var copied = 0;
    for (final assetPath in assetPaths) {
      final relative = assetPath.substring('assets/dj_voice_bank/'.length);
      final out = File(p.join(target.path, relative));
      if (!await out.parent.exists()) {
        await out.parent.create(recursive: true);
      }
      final bytes = await rootBundle.load(assetPath);
      await out.writeAsBytes(bytes.buffer.asUint8List(
        bytes.offsetInBytes,
        bytes.lengthInBytes,
      ));
      copied += 1;
    }
    debugPrint('[dj-bank] extracted $copied bundled assets to ${target.path}');
  }

  static Future<DjVoiceBank> loadFromDirectory(Directory directory) async {
    final manifestFile = File(p.join(directory.path, 'manifest.json'));
    if (!await manifestFile.exists()) {
      return DjVoiceBank.empty(directory);
    }

    try {
      final decoded = jsonDecode(await manifestFile.readAsString());
      if (decoded is! Map) return DjVoiceBank.empty(directory);
      return DjVoiceBank(
        directory: directory,
        manifest: DjVoiceBankManifest.fromJson(decoded.cast<String, Object?>()),
      );
    } catch (e) {
      debugPrint('[dj-bank] failed to load manifest: $e');
      return DjVoiceBank.empty(directory);
    }
  }
}

class DjVoiceBankPlayer {
  DjVoiceBankPlayer({AudioPlayer? player}) : _player = player ?? AudioPlayer();

  final AudioPlayer _player;
  final _speakingCtrl = StreamController<bool>.broadcast();

  /// Playback rate for pre-rendered F5-TTS voice clips. The model bakes
  /// at a deliberately slow cadence; 1.15x trims the drag without making
  /// the host sound chipmunky. Bump to ~1.25 if you want it punchier.
  static const double _playbackSpeed = 1.15;

  Stream<bool> get isSpeakingStream => _speakingCtrl.stream;

  Future<bool> play(DjVoiceBank bank, DjVoiceClip clip) async {
    final path = bank.resolvePath(clip);
    final file = File(path);
    if (!await file.exists()) {
      debugPrint('[dj-bank] missing clip ${clip.id}: $path');
      return false;
    }
    if (await file.length() == 0) {
      debugPrint('[dj-bank] empty clip ${clip.id}: $path');
      return false;
    }

    try {
      _speakingCtrl.add(true);
      await _player.stop();
      await _player.setFilePath(path);
      await _player.setSpeed(_playbackSpeed);
      await _player.play();
      await _player.processingStateStream.firstWhere(
        (state) => state == ProcessingState.completed,
      );
      return true;
    } catch (e, st) {
      debugPrint('[dj-bank] failed to play ${clip.id}: $e\n$st');
      return false;
    } finally {
      _speakingCtrl.add(false);
    }
  }

  Future<void> dispose() async {
    await _player.dispose();
    await _speakingCtrl.close();
  }
}
