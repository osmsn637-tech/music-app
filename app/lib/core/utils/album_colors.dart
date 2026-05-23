import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../ui/theme/app_theme.dart';

/// Extracts a small palette of dominant colours from an album-artwork
/// image file. Used by the player's `BloomBackground` to drive moving
/// colour blobs that match the current song's cover, and (via the
/// `tryExtractAccent` helper) by the transport-button tint.
///
/// Greyscale-robust pipeline (decode at 32x32):
///   1. For every opaque pixel, compute *chroma* as `max(r,g,b) − min(r,g,b)`.
///      Chroma is a more reliable "is this pixel grey?" signal than HSV
///      saturation, which behaves badly near pure black and pure white.
///   2. Drop pixels that are near-grey, near-black, or near-white. The
///      remaining "chromatic" pixels are the ones with real hue.
///   3. If less than ~5 % of the cover's pixels survived step 2, the
///      cover is effectively greyscale — return a *neutral* palette
///      derived from the cover's mean luminance (black covers → soft
///      silver, white covers → bright white). Callers can detect this
///      branch via [isNeutral] and skip any HSL saturation clamp that
///      would otherwise resurface hue=0 (red) on a pure grey input.
///   4. Otherwise bin the chromatic pixels into 12 hue buckets weighted
///      by `saturation × value²` (vivid + bright pixels carry more
///      votes than dim or barely-coloured ones). Buckets that didn't
///      collect at least 3 % of the total weight are discarded so a
///      handful of compression-noise pixels can't pick a hue.
///   5. The top three surviving buckets are averaged and returned.
class AlbumColors {
  /// Last-resort palette returned only for IO errors / decode failure /
  /// missing file. Greyscale covers no longer route here — they get a
  /// luminance-derived neutral palette instead.
  static const fallback = <Color>[
    LumenTokens.orbViolet,
    LumenTokens.orbPink,
    LumenTokens.blobPurple,
  ];

  /// Pixel is "near-grey" if `max − min` of its RGB channels is below
  /// this. ~16 % of the 0-255 range — tight enough to catch
  /// compression-noise tints in greyscale covers.
  static const _minChroma = 40;
  /// Drop very dark pixels (shadow noise) and very light pixels
  /// (highlight noise) — both groups carry unreliable hue.
  static const _minMaxChannel = 50;
  static const _maxMinChannel = 220;
  /// A cover with fewer than this fraction of chromatic pixels is
  /// considered greyscale. Tight enough to reject compression noise
  /// (≪1 % at JPEG-90), loose enough to honour a small logo on an
  /// otherwise black / white cover. The [_minBucketRatio] filter
  /// below catches the residual "scattered noise" case where chromatic
  /// pixels exist but don't agree on a hue.
  static const _minChromaticRatio = 0.02;
  /// A hue bucket must hold at least this fraction of the total
  /// surviving weight to be considered. Without this, a single rogue
  /// chromatic pixel in a greyscale cover could pick the dominant hue.
  static const _minBucketRatio = 0.03;
  /// HSL saturation under this value is treated as "neutral" by
  /// downstream colour-clamping logic. Matches the headroom the
  /// extractor leaves on `_minChroma` (40/255 ≈ 0.16) once converted
  /// through HSL.
  static const neutralSaturationThreshold = 0.10;

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

  /// True when [colors] is the static IO-error fallback.
  static bool isFallback(List<Color> colors) =>
      identical(colors, AlbumColors.fallback);

  /// True when every colour in [colors] is effectively greyscale
  /// (saturation under [neutralSaturationThreshold]). Use this in any
  /// consumer that runs an HSL saturation clamp — clamping a pure grey
  /// up to 0.5 saturation resurfaces hue=0 (red), which is the original
  /// "grey covers paint orange" bug.
  static bool isNeutral(List<Color> colors) {
    if (colors.isEmpty) return false;
    for (final c in colors) {
      if (HSLColor.fromColor(c).saturation >= neutralSaturationThreshold) {
        return false;
      }
    }
    return true;
  }

  /// Single readable accent colour — for the player's transport tint.
  /// - IO error / missing file → [fallback] (caller's choice).
  /// - Greyscale cover → a soft silvery white that stays legible on the
  ///   dark bloom, derived from the cover's own luminance so a pure
  ///   black cover doesn't paint a stark white button.
  /// - Otherwise → first dominant hue with saturation + lightness
  ///   clamped into a readable range.
  static Future<Color> tryExtractAccent(
    String? filePath, {
    required Color fallback,
  }) async {
    if (filePath == null) return fallback;
    final colors = await extract(filePath);
    if (isFallback(colors) || colors.isEmpty) return fallback;
    return accentFromPalette(colors, fallback: fallback);
  }

  /// Same readability clamps as [tryExtractAccent] but operates on an
  /// already-extracted palette (e.g. one cached by `albumColorsProvider`).
  /// Skips the saturation clamp on neutral palettes so grey covers stay
  /// grey instead of being pushed to red.
  static Color accentFromPalette(
    List<Color> colors, {
    required Color fallback,
  }) {
    if (isFallback(colors) || colors.isEmpty) return fallback;
    final first = colors.first;
    final hsl = HSLColor.fromColor(first);
    if (hsl.saturation < neutralSaturationThreshold) {
      // Map cover luminance to a button lightness that always pops on
      // the dark bloom — pure black covers get a soft silver, white
      // covers get a bright white. Keep hue/saturation at zero so the
      // tint stays truly neutral.
      final lum = hsl.lightness;
      final l = (0.70 + lum * 0.22).clamp(0.70, 0.92);
      return HSLColor.fromAHSL(1.0, 0, 0, l).toColor();
    }
    return hsl
        .withSaturation(hsl.saturation.clamp(0.50, 0.88))
        .withLightness(hsl.lightness.clamp(0.58, 0.74))
        .toColor();
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
    // 12 hue buckets of 30°. Stored as doubles because pixels are
    // weighted by sat × value² rather than counted 1-for-1.
    final sums = List.generate(12, (_) => <double>[0, 0, 0, 0]);

    var totalPixels = 0;
    var chromaticPixels = 0;
    // Mean perceived-luminance accumulator over *all* opaque pixels —
    // drives the neutral palette returned on greyscale covers. Uses
    // Rec.709 coefficients so a "white" cover reads brighter than a
    // "grey" one even when both have zero chroma.
    var lumSum = 0.0;

    for (var i = 0; i + 3 < pixels.length; i += 4) {
      final r = pixels[i];
      final g = pixels[i + 1];
      final b = pixels[i + 2];
      final a = pixels[i + 3];
      if (a < 128) continue;
      totalPixels += 1;
      lumSum += (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255.0;

      final mx = math.max(r, math.max(g, b));
      final mn = math.min(r, math.min(g, b));
      final chroma = mx - mn;

      // Grey, near-black, or near-white pixels carry hue noise from
      // JPEG/PNG compression — a slightly warm "black" reads as red, a
      // slightly cool "grey" reads as blue. Throw them all out before
      // bucketing.
      if (chroma < _minChroma) continue;
      if (mx < _minMaxChannel) continue;
      if (mn > _maxMinChannel) continue;

      chromaticPixels += 1;

      final hsv = HSVColor.fromColor(Color.fromARGB(255, r, g, b));
      // Vivid + bright pixels dominate; dim or barely-coloured ones
      // contribute almost nothing. value² makes the brightness term
      // strongly outweigh dim mid-greys that snuck past _minChroma.
      final w = hsv.saturation * hsv.value * hsv.value;
      final bucket = (hsv.hue / 30).floor() % 12;
      sums[bucket][0] += r * w;
      sums[bucket][1] += g * w;
      sums[bucket][2] += b * w;
      sums[bucket][3] += w;
    }

    // Truly greyscale cover — return a luminance-derived neutral
    // palette instead of the purple IO-error fallback. Three slightly
    // different greys give the bloom a touch of variety without
    // resurrecting any hue.
    if (totalPixels == 0 ||
        chromaticPixels < totalPixels * _minChromaticRatio) {
      final meanLum = totalPixels == 0 ? 0.5 : lumSum / totalPixels;
      return _neutralPalette(meanLum);
    }

    final totalWeight = sums.fold<double>(0, (s, b) => s + b[3]);
    if (totalWeight <= 0) {
      final meanLum = totalPixels == 0 ? 0.5 : lumSum / totalPixels;
      return _neutralPalette(meanLum);
    }
    final minBucket = totalWeight * _minBucketRatio;

    final populated = sums.where((s) => s[3] >= minBucket).toList()
      ..sort((a, b) => b[3].compareTo(a[3]));

    if (populated.isEmpty) {
      final meanLum = totalPixels == 0 ? 0.5 : lumSum / totalPixels;
      return _neutralPalette(meanLum);
    }

    final picked = <Color>[];
    for (final s in populated.take(3)) {
      final w = s[3];
      picked.add(Color.fromARGB(
        255,
        (s[0] / w).round().clamp(0, 255),
        (s[1] / w).round().clamp(0, 255),
        (s[2] / w).round().clamp(0, 255),
      ));
    }
    while (picked.length < 3) {
      picked.add(picked.last);
    }
    return picked;
  }

  /// Three neutral greys derived from the cover's mean luminance.
  /// The transform-based bg uses srcOver (not additive), so we don't
  /// need to lift dark covers above ~0.25 to keep them visible. Pure
  /// black covers therefore stay near-black; pure white covers stay
  /// near-white but capped under 0.75 so they don't paint a blinding
  /// wash; mid-grey covers map proportionally. The three shades are
  /// slightly offset so the bg still has subtle internal variation.
  static List<Color> _neutralPalette(double luminance) {
    final base = (0.10 + luminance * 0.60).clamp(0.10, 0.72);
    Color grey(double l) =>
        HSLColor.fromAHSL(1.0, 0, 0, l.clamp(0.0, 1.0)).toColor();
    return <Color>[
      grey(base),
      grey(base + 0.08),
      grey(base - 0.05),
    ];
  }
}
