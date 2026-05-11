import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/album_colors.dart';

/// Cached per-artwork-path dominant-colour extraction. Keyed by the local
/// file path so two songs sharing the same artwork (e.g. an album's
/// tracks) only pay the decode cost once for the lifetime of the cache.
final albumColorsProvider =
    FutureProvider.family<List<Color>, String?>((ref, path) async {
  if (path == null || path.isEmpty) return AlbumColors.fallback;
  return AlbumColors.extract(path);
});
