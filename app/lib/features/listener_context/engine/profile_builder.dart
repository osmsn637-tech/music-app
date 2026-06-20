import 'dart:math' as math;

import '../../ai_dj/user_listening_profile.dart';
import '../model/context_enums.dart';
import '../model/results.dart';
import '../model/session_event.dart';
import '../model/track_features.dart';
import '../model/vectors.dart';
import 'time_context.dart';

/// Builds the durable [ListenerProfile] (spec: User Profile Model + Learning
/// System) from the persisted [UserListeningProfile] aggregates and the
/// analysed library. Everything here is derived from real history, so as the
/// stats grow the vectors update continuously (the "learning" is the rebuild).
class ProfileBuilder {
  const ProfileBuilder({this.time = const TimeContextEngine()});
  final TimeContextEngine time;

  ListenerProfile build({
    required UserListeningProfile history,
    required Map<String, TrackFeatures> featuresById,
    List<SessionEvent> recentEvents = const [],
    DateTime? now,
  }) {
    // Weight every signal by how much the listener *finished* the track —
    // completion is the strongest positive signal we persist.
    final completed = history.completeCountById;

    final taste = _taste(history, featuresById, completed);
    final bpmRange = _weightedRange(
      featuresById,
      completed,
      (f) => f.bpm,
      fallback: const PreferenceRange(90, 120, 150),
    );
    final energyRange = _weightedRange(
      featuresById,
      completed,
      (f) => f.energy,
      fallback: const PreferenceRange(0.3, 0.55, 0.8),
    );
    final loudRange = _weightedRange(
      featuresById,
      completed,
      (f) => f.loudnessLufs,
      fallback: const PreferenceRange(-16, -11, -7),
    );

    final exploration = _exploration(history);
    final energyPref = EnergyPreferenceVector(
      overall: energyRange,
      byTimeOfDay: {
        for (final tod in TimeOfDay.values)
          tod: (energyRange.center + time.adaptationFor(tod).energyBias)
              .clamp(0.0, 1.0),
      },
    );

    return ListenerProfile(
      taste: taste,
      baselineMood: _baselineMood(energyRange.center, taste.valenceCenter),
      energyPreference: energyPref,
      exploration: exploration,
      preferredBpm: bpmRange,
      preferredLoudnessLufs: loudRange,
      preferredTransitionStyle: _preferredStyle(energyRange.center),
      preferredSessionLength: _sessionLength(recentEvents),
      likedSongIds: history.favoriteSongIds,
      // Disliked/hidden need explicit UI signals the app doesn't persist yet;
      // surface them as empty rather than guessing. Chronic skips stand in for
      // implicit dislike in scoring.
      dislikedSongIds: const {},
      hiddenSongIds: const {},
      chronicallySkippedSongIds: _chronicSkips(history),
      topGenres: history.topGenres,
      topArtists: history.topArtists,
      topAlbums: _topAlbums(featuresById, completed),
    );
  }

  TasteVector _taste(
    UserListeningProfile history,
    Map<String, TrackFeatures> featuresById,
    Map<String, int> completed,
  ) {
    // Rank → weight for the catalog-derived top lists (linear decay).
    Map<String, double> ranked(List<String> items) {
      final m = <String, double>{};
      for (var i = 0; i < items.length; i++) {
        m[items[i].toLowerCase()] = 1 - i / (items.length + 1);
      }
      return m;
    }

    // Feature centroid weighted by completion count.
    var bpm = 0.0, energy = 0.0, valence = 0.0, loud = 0.0, w = 0.0;
    completed.forEach((id, c) {
      final f = featuresById[id];
      if (f == null || c <= 0) return;
      final ww = c.toDouble();
      bpm += (f.bpm.clamp(0, 200)) / 200.0 * ww;
      energy += f.energy * ww;
      valence += f.valence * ww;
      loud += ((f.loudnessLufs + 30) / 24).clamp(0.0, 1.0) * ww;
      w += ww;
    });
    // One consistent guard: if any completed track contributed, use the real
    // centroid for ALL axes; otherwise fall back to coherent defaults (not a
    // mix of one real axis and three placeholders).
    final hasData = w > 0;
    if (!hasData) w = 1;

    return TasteVector(
      genreWeights: ranked(history.topGenres),
      artistWeights: ranked(history.topArtists),
      bpmCenter: hasData ? bpm / w : 0.6,
      energyCenter: hasData ? energy / w : 0.55,
      valenceCenter: hasData ? valence / w : 0.5,
      loudnessCenter: hasData ? loud / w : 0.6,
    );
  }

  MoodVector _baselineMood(double energyCenter, double valenceCenter) {
    // A soft prior over moods from the listener's typical energy/valence.
    final weights = <Mood, double>{};
    for (final m in Mood.values) {
      final de = (m.energyAffinity - energyCenter).abs();
      final dv = (m.valenceAffinity - valenceCenter).abs();
      weights[m] = math.max(0.0, 1 - (0.6 * de + 0.4 * dv));
    }
    return MoodVector(weights);
  }

  ExplorationScore _exploration(UserListeningProfile history) {
    // Observed: fraction of played songs heard only once (a proxy for how
    // much novelty the listener actually consumes).
    final played =
        history.playCountById.entries.where((e) => e.value > 0).toList();
    final onceOnly = played.where((e) => e.value == 1).length;
    final value = played.isEmpty ? 0.3 : onceOnly / played.length;

    // Tolerance: low skipping → comfortable with more exploration.
    final totalSkips =
        history.skipCountById.values.fold<int>(0, (a, b) => a + b);
    final totalPlays =
        history.playCountById.values.fold<int>(0, (a, b) => a + b);
    final skipRate = totalPlays == 0 ? 0.3 : totalSkips / totalPlays;
    final tolerance = (0.7 - skipRate).clamp(0.15, 0.8);

    return ExplorationScore(value.clamp(0.0, 1.0).toDouble(),
        tolerance: tolerance.toDouble());
  }

  TransitionStyle _preferredStyle(double energyCenter) {
    if (energyCenter >= 0.7) return TransitionStyle.club;
    if (energyCenter <= 0.35) return TransitionStyle.smooth;
    return TransitionStyle.intelligentAdaptive;
  }

  Duration _sessionLength(List<SessionEvent> events) {
    if (events.length < 2) return const Duration(minutes: 45);
    // Segment the event log into sessions on >30 min idle gaps, take the
    // median session span.
    final sorted = [...events]..sort((a, b) => a.at.compareTo(b.at));
    final spans = <int>[]; // minutes
    DateTime? start, last;
    for (final e in sorted) {
      if (start == null) {
        start = e.at;
        last = e.at;
        continue;
      }
      if (e.at.difference(last!).inMinutes > 30) {
        spans.add(last.difference(start).inMinutes);
        start = e.at;
      }
      last = e.at;
    }
    if (start != null && last != null) {
      spans.add(last.difference(start).inMinutes);
    }
    final valid = spans.where((m) => m > 0).toList()..sort();
    if (valid.isEmpty) return const Duration(minutes: 45);
    return Duration(minutes: valid[valid.length ~/ 2]);
  }

  Set<String> _chronicSkips(UserListeningProfile history) => history
      .skipCountById.entries
      .where((e) => e.value >= 2)
      .map((e) => e.key)
      .toSet();

  List<String> _topAlbums(
    Map<String, TrackFeatures> featuresById,
    Map<String, int> completed,
  ) {
    final counts = <String, int>{};
    completed.forEach((id, c) {
      final album = featuresById[id]?.album;
      if (album == null || album.isEmpty || c <= 0) return;
      counts[album] = (counts[album] ?? 0) + c;
    });
    final ranked = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return ranked.take(10).map((e) => e.key).toList();
  }

  /// Mean ± std window over a feature, weighted by completion count.
  PreferenceRange _weightedRange(
    Map<String, TrackFeatures> featuresById,
    Map<String, int> completed,
    double Function(TrackFeatures) pick, {
    required PreferenceRange fallback,
  }) {
    var sum = 0.0, w = 0.0;
    final vals = <double>[];
    final weights = <double>[];
    completed.forEach((id, c) {
      final f = featuresById[id];
      if (f == null || c <= 0) return;
      final v = pick(f);
      sum += v * c;
      w += c;
      vals.add(v);
      weights.add(c.toDouble());
    });
    if (w <= 0 || vals.length < 3) return fallback;
    final mean = sum / w;
    var varSum = 0.0;
    for (var i = 0; i < vals.length; i++) {
      varSum += weights[i] * math.pow(vals[i] - mean, 2);
    }
    final std = math.sqrt(varSum / w);
    return PreferenceRange(mean - std, mean, mean + std);
  }
}
