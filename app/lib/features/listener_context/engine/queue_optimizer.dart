import '../model/context_enums.dart';
import '../model/results.dart';
import '../model/track_features.dart';
import 'time_context.dart';

/// Queue Optimization (spec). Re-ranks candidate tracks by the weighted Final
/// Score:
///   35% Taste · 20% Mood · 15% Energy · 10% Time · 10% Discovery · 10% Continuity
/// Suppressed (hidden/disliked) tracks are dropped entirely.
class QueueOptimizer {
  const QueueOptimizer({this.time = const TimeContextEngine()});
  final TimeContextEngine time;

  List<RankedTrack> rank({
    required List<TrackFeatures> candidates,
    required ListenerProfile profile,
    required Mood mood,
    required double targetEnergy,
    required TimeOfDay tod,
    required double explorationTarget,
    required Set<String> familiarSongIds,
    TrackFeatures? currentTrack,
  }) {
    final out = <RankedTrack>[];
    for (final c in candidates) {
      if (profile.isSuppressed(c.songId)) continue;

      final isFamiliar = familiarSongIds.contains(c.songId);
      final taste = profile.taste.matchScore(c);
      final moodMatch = _moodMatch(c, mood);
      final energyMatch =
          (1 - (c.energy - targetEnergy).abs()).clamp(0.0, 1.0).toDouble();
      final timeMatch = time.matchScore(
        trackEnergy: c.energy,
        tod: tod,
        preferredCenter: profile.energyPreference.overall.center,
      );
      final discovery = isFamiliar
          ? (1 - explorationTarget)
          : explorationTarget;
      final continuity = _continuity(c, currentTrack);

      // Chronic skips: a soft penalty (implicit dislike) without hard removal.
      final skipPenalty =
          profile.chronicallySkippedSongIds.contains(c.songId) ? 0.85 : 1.0;

      final finalScore = (RankedTrack.wTaste * taste +
              RankedTrack.wMood * moodMatch +
              RankedTrack.wEnergy * energyMatch +
              RankedTrack.wTime * timeMatch +
              RankedTrack.wDiscovery * discovery +
              RankedTrack.wContinuity * continuity) *
          skipPenalty;

      out.add(RankedTrack(
        songId: c.songId,
        finalScore: finalScore.clamp(0.0, 1.0),
        tasteMatch: taste,
        moodMatch: moodMatch,
        energyMatch: energyMatch,
        timeMatch: timeMatch,
        discoveryValue: discovery,
        continuity: continuity,
        isFamiliar: isFamiliar,
      ));
    }
    out.sort((a, b) => b.finalScore.compareTo(a.finalScore));
    return out;
  }

  double _moodMatch(TrackFeatures t, Mood mood) {
    final de = (t.energy - mood.energyAffinity).abs();
    final dv = (t.valence - mood.valenceAffinity).abs();
    return (1 - (0.6 * de + 0.4 * dv)).clamp(0.0, 1.0);
  }

  /// Smooth-flow term: how close the candidate sits to the current track in
  /// tempo / energy / valence (so the queue doesn't lurch).
  double _continuity(TrackFeatures c, TrackFeatures? current) {
    if (current == null) return 0.6; // neutral when there's no anchor
    final bpmDiff = ((c.bpm - current.bpm).abs() / 60).clamp(0.0, 1.0);
    final eDiff = (c.energy - current.energy).abs();
    final vDiff = (c.valence - current.valence).abs();
    return (1 - (0.5 * bpmDiff + 0.3 * eDiff + 0.2 * vDiff))
        .clamp(0.0, 1.0)
        .toDouble();
  }
}
