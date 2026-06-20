import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../../data/database/app_database.dart';
import '../model/track_analysis.dart';

/// Loads `*.automix.json` sidecars produced by `tools/automix/analyze.py`
/// and resolves the right one for a given [SongRow]. Sidecars are indexed
/// by a normalised slug of the audio basename, so the join survives the
/// container-path churn the app already deals with (sidecars ship next to,
/// or are downloaded alongside, the audio).
class AnalysisStore {
  AnalysisStore(this.directoryPath);

  /// Directory containing the `*.automix.json` sidecars.
  final String directoryPath;

  final Map<String, TrackAnalysis> _bySlug = {};
  bool _indexed = false;

  /// Normalise an audio basename to the same slug the analyzer uses.
  static String slugify(String name) {
    var s = name.toLowerCase();
    final dot = s.lastIndexOf('.');
    if (dot > 0) s = s.substring(0, dot); // strip extension
    s = s.replaceAll(RegExp(r'\(mp3_320k\)'), '');
    s = s.replaceAll(RegExp(r'[^a-z0-9]+'), '_');
    s = s.replaceAll(RegExp(r'^_+|_+$'), '');
    return s.isEmpty ? 'track' : s;
  }

  Future<void> _ensureIndexed() async {
    if (_indexed) return;
    _indexed = true;
    final dir = Directory(directoryPath);
    if (!await dir.exists()) return;
    await for (final entity in dir.list()) {
      if (entity is! File || !entity.path.endsWith('.automix.json')) continue;
      try {
        final json =
            jsonDecode(await entity.readAsString()) as Map<String, dynamic>;
        final a = TrackAnalysis.fromJson(json);
        if (a.schema != TrackAnalysis.currentSchema) continue;
        _bySlug[slugify(a.file)] = a;
      } catch (e) {
        if (kDebugMode) debugPrint('[automix] bad sidecar ${entity.path}: $e');
      }
    }
  }

  /// Force a re-scan (e.g. after a batch analysis run added sidecars).
  void invalidate() {
    _indexed = false;
    _bySlug.clear();
  }

  /// The analysis for [song], or null if no sidecar has been generated yet.
  Future<TrackAnalysis?> forSong(SongRow song) async {
    await _ensureIndexed();
    for (final candidate in _candidateSlugs(song)) {
      final hit = _bySlug[candidate];
      if (hit != null) return hit;
    }
    return null;
  }

  bool get isEmpty => _bySlug.isEmpty;

  /// The library importer renames audio to `imp_<original-slug>_mp3_320k.mp3`
  /// and stores that in [SongRow.fileName] / the `<id>.mp3` on disk — but the
  /// analyzer keyed each sidecar on the ORIGINAL basename. Strip the importer's
  /// `imp_` prefix and `_mp3_320k` suffix so the renamed file rejoins its
  /// sidecar (verified: this lifts the match rate from 0/779 to 764/779).
  static String stripImporter(String slug) {
    var s = slug;
    if (s.startsWith('imp_')) s = s.substring(4);
    s = s.replaceAll(RegExp(r'_mp3_320k$'), '');
    return s;
  }

  Iterable<String> _candidateSlugs(SongRow song) sync* {
    final seen = <String>{};
    Iterable<String> expand(String slug) sync* {
      if (slug.isNotEmpty && seen.add(slug)) yield slug;
      final bridged = stripImporter(slug);
      if (bridged != slug && bridged.isNotEmpty && seen.add(bridged)) {
        yield bridged;
      }
    }

    final fileName = song.fileName;
    if (fileName != null && fileName.isNotEmpty) {
      yield* expand(slugify(fileName));
    }
    final base = song.localFilePath.split(Platform.pathSeparator).last;
    if (base.isNotEmpty) yield* expand(slugify(base));
  }
}
