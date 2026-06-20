import 'dart:math' as math;

import 'context_enums.dart';
import 'track_features.dart';

/// A closed numeric range with a centre — used for preferred BPM / energy /
/// loudness windows.
class PreferenceRange {
  const PreferenceRange(this.min, this.center, this.max);
  final double min;
  final double center;
  final double max;

  bool contains(double v) => v >= min && v <= max;

  /// 1.0 at the centre, decaying to ~0 at (and beyond) the edges. Soft so a
  /// track just outside the window isn't hard-rejected.
  double affinity(double v) {
    if (max <= min) return v == center ? 1.0 : 0.5;
    final halfWidth = (max - min) / 2;
    if (halfWidth <= 0) return 1.0;
    final d = (v - center).abs() / halfWidth;
    return (1 - d * 0.6).clamp(0.0, 1.0);
  }

  Map<String, dynamic> toJson() => {'min': min, 'center': center, 'max': max};
}

/// The listener's taste as weighted genre/artist preferences plus a numeric
/// centroid over audio features. [matchScore] is the spec's "Taste Match".
class TasteVector {
  const TasteVector({
    required this.genreWeights,
    required this.artistWeights,
    required this.bpmCenter,
    required this.energyCenter,
    required this.valenceCenter,
    required this.loudnessCenter,
  });

  /// genre → weight (0..1, normalised to the top genre).
  final Map<String, double> genreWeights;

  /// artist → weight (0..1).
  final Map<String, double> artistWeights;

  /// Normalised feature centroid (each 0..1; loudness mapped −30..−6 → 0..1).
  final double bpmCenter;
  final double energyCenter;
  final double valenceCenter;
  final double loudnessCenter;

  /// Taste affinity of [t] in 0..1: blends genre, artist and feature-centroid
  /// proximity. Artist match dominates (people follow artists hardest), then
  /// genre, then the audio-feature fit.
  double matchScore(TrackFeatures t) {
    final g = _weightFor(genreWeights, t.genre);
    final a = _artistWeight(t.artist);
    final feat = _featureProximity(t);
    return (0.45 * a + 0.3 * g + 0.25 * feat).clamp(0.0, 1.0);
  }

  double _featureProximity(TrackFeatures t) {
    final bpmN = (t.bpm.clamp(0, 200)) / 200.0;
    final loudN = ((t.loudnessLufs + 30) / 24).clamp(0.0, 1.0);
    final d = [
      (bpmN - bpmCenter).abs(),
      (t.energy - energyCenter).abs(),
      (t.valence - valenceCenter).abs(),
      (loudN - loudnessCenter).abs(),
    ].reduce((x, y) => x + y) /
        4;
    return (1 - d).clamp(0.0, 1.0);
  }

  double _artistWeight(String? artist) {
    if (artist == null) return 0;
    var best = 0.0;
    // Split on real connectors only. Word boundaries keep the connector
    // tokens from matching *inside* names ("Daft Punk", "Within Temptation").
    for (final name in artist.split(RegExp(
        r'\s*(?:,|&|\b(?:feat|ft|featuring|with)\b\.?)\s*',
        caseSensitive: false))) {
      final w = _weightFor(artistWeights, name.trim());
      if (w > best) best = w;
    }
    return best;
  }

  static double _weightFor(Map<String, double> weights, String? key) {
    if (key == null || key.isEmpty) return 0;
    return weights[key.toLowerCase()] ?? 0;
  }

  Map<String, dynamic> toJson() => {
        'topGenres': (genreWeights.entries.toList()
              ..sort((a, b) => b.value.compareTo(a.value)))
            .take(5)
            .map((e) => {'genre': e.key, 'weight': e.value})
            .toList(),
        'topArtists': (artistWeights.entries.toList()
              ..sort((a, b) => b.value.compareTo(a.value)))
            .take(5)
            .map((e) => {'artist': e.key, 'weight': e.value})
            .toList(),
        'bpmCenter': bpmCenter,
        'energyCenter': energyCenter,
        'valenceCenter': valenceCenter,
        'loudnessCenter': loudnessCenter,
      };
}

/// A soft distribution over moods (weights sum to ~1). The dominant entry is
/// the "current mood"; the spread feeds the mood-confidence score.
class MoodVector {
  MoodVector(Map<Mood, double> weights)
      : weights = _normalise(weights);

  final Map<Mood, double> weights;

  Mood get dominant {
    var best = Mood.calm;
    var bestW = -1.0;
    weights.forEach((m, w) {
      if (w > bestW) {
        bestW = w;
        best = m;
      }
    });
    return best;
  }

  double get dominantWeight => weights[dominant] ?? 0;

  /// Confidence 0..1: how peaked the distribution is (dominant vs runner-up).
  double get confidence {
    if (weights.length < 2) return dominantWeight;
    final sorted = weights.values.toList()..sort((a, b) => b.compareTo(a));
    final margin = sorted[0] - sorted[1];
    return (sorted[0] * 0.5 + margin * 2).clamp(0.0, 1.0);
  }

  static Map<Mood, double> _normalise(Map<Mood, double> w) {
    final total = w.values.fold(0.0, (a, b) => a + math.max(0.0, b));
    if (total <= 0) {
      return {for (final m in Mood.values) m: 1 / Mood.values.length};
    }
    return {for (final e in w.entries) e.key: math.max(0.0, e.value) / total};
  }

  Map<String, dynamic> toJson() => {
        'dominant': dominant.name,
        'confidence': confidence,
        'distribution': {
          for (final e in (weights.entries.toList()
                ..sort((a, b) => b.value.compareTo(a.value))))
            e.key.name: double.parse(e.value.toStringAsFixed(3)),
        },
      };
}

/// Preferred energy window overall and per time-of-day (spec: Energy
/// Preference Vector).
class EnergyPreferenceVector {
  const EnergyPreferenceVector({
    required this.overall,
    required this.byTimeOfDay,
  });

  final PreferenceRange overall; // 0..1 energy
  final Map<TimeOfDay, double> byTimeOfDay; // tod → preferred centre 0..1

  double centerFor(TimeOfDay tod) => byTimeOfDay[tod] ?? overall.center;

  Map<String, dynamic> toJson() => {
        'overall': overall.toJson(),
        'byTimeOfDay': {
          for (final e in byTimeOfDay.entries) e.key.name: e.value,
        },
      };
}

/// How far the listener strays from the familiar, 0..1. Drives the discovery
/// engine's ceiling (spec: Exploration Score / tolerance).
class ExplorationScore {
  const ExplorationScore(this.value, {required this.tolerance});

  /// Observed exploration (fraction of plays that were new/unfamiliar).
  final double value;

  /// The *ceiling* — how much exploration the listener tolerates before
  /// disengaging. The discovery engine must never exceed this.
  final double tolerance;

  Map<String, dynamic> toJson() => {'value': value, 'tolerance': tolerance};
}
