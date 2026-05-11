import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../ui/theme/app_theme.dart';

/// Extracts a small palette of dominant colours from an album-artwork
/// image file. Used by the player's [BloomBackground] to drive moving
/// colour blobs that match the current song's cover.
///
/// Implementation: decode the JPEG/PNG into a 32x32 raster (cheap), bin
/// each opaque pixel by its hue (12 buckets), throw out near-black and
/// near-greyscale samples that would otherwise dominate dark covers, then
/// take the three largest buckets and average each. Returns the fallback
/// palette if no image is available or no colourful pixels survive.
class AlbumColors {
  static const fallback = <Color>[
    LumenTokens.orbViolet,
    LumenTokens.orbPink,
    LumenTokens.blobPurple,
  ];

  static Future<List<Color>> extract(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return fallback;
      final bytes = await file.readAsBytes();
      return _extractFromBytes(bytes);
    } catch (_) {
      return fallback;
    }
  }

  static Future<List<Color>> _extractFromBytes(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: 32,
      targetHeight: 32,
    );
    final frame = await codec.getNextFrame();
    final byteData =
        await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba);
    frame.image.dispose();
    if (byteData == null) return fallback;

    final pixels = byteData.buffer.asUint8List();
    // 12 hue buckets, each ~30°. Holds (totalR, totalG, totalB, count).
    final sums = List.generate(12, (_) => <int>[0, 0, 0, 0]);

    for (var i = 0; i + 3 < pixels.length; i += 4) {
      final r = pixels[i];
      final g = pixels[i + 1];
      final b = pixels[i + 2];
      final a = pixels[i + 3];
      if (a < 128) continue;

      final color = Color.fromARGB(255, r, g, b);
      final hsv = HSVColor.fromColor(color);
      // Black/greyscale pixels would otherwise win every dark cover —
      // dropping them is what makes the picked colours actually pop.
      if (hsv.value < 0.18) continue;
      if (hsv.saturation < 0.22) continue;

      final bucket = (hsv.hue / 30).floor() % 12;
      sums[bucket][0] += r;
      sums[bucket][1] += g;
      sums[bucket][2] += b;
      sums[bucket][3] += 1;
    }

    final populated = sums.where((s) => s[3] > 0).toList()
      ..sort((a, b) => b[3].compareTo(a[3]));

    if (populated.isEmpty) return fallback;

    final picked = <Color>[];
    for (final s in populated.take(3)) {
      final c = s[3];
      picked.add(Color.fromARGB(
        255,
        (s[0] / c).round().clamp(0, 255),
        (s[1] / c).round().clamp(0, 255),
        (s[2] / c).round().clamp(0, 255),
      ));
    }
    while (picked.length < 3) {
      picked.add(picked.last);
    }
    return picked;
  }
}
