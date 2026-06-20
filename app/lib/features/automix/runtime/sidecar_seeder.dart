import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

/// Copies the bundled `*.automix.json` analysis sidecars from the asset bundle
/// into [destDir] (the on-device `automix_analysis` dir) so [AnalysisStore]
/// can read them on every platform — iOS/release has no other source. The
/// repo ships the sidecars under `assets/automix_analysis/`.
///
/// Idempotent and cheap on warm launches: a count match short-circuits, and
/// individual files are skipped if already present. Failures are swallowed —
/// without sidecars AutoMix simply falls back to a plain crossfade.
Future<void> seedAutoMixSidecars(String destDir) async {
  try {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final keys = manifest
        .listAssets()
        .where(
          (k) =>
              k.startsWith('assets/automix_analysis/') &&
              k.endsWith('.automix.json'),
        )
        .toList();
    if (keys.isEmpty) return;

    final dir = Directory(destDir);
    if (!await dir.exists()) await dir.create(recursive: true);

    // Fast path: already seeded (counts line up) → nothing to do.
    final existing = await dir
        .list()
        .where((e) => e is File && e.path.endsWith('.automix.json'))
        .length;
    if (existing >= keys.length) return;

    var copied = 0;
    for (final key in keys) {
      final dest = File(p.join(destDir, p.basename(key)));
      if (await dest.exists()) continue;
      final data = await rootBundle.load(key);
      await dest.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: false,
      );
      copied++;
    }
    if (kDebugMode && copied > 0) {
      debugPrint('[automix] seeded $copied analysis sidecars → $destDir');
    }
  } catch (e) {
    if (kDebugMode) debugPrint('[automix] sidecar seed failed (non-fatal): $e');
  }
}
