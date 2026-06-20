import 'dart:math' as math;

import '../model/context_enums.dart';
import '../model/results.dart';
import '../model/track_features.dart';
import '../model/vectors.dart';

/// Mood Detection Engine (spec). Infers mood from the energy/valence of what's
/// actually playing, the listener's baseline mood prior, the session state and
/// the time of day, returning a confidence-scored mood distribution.
class MoodDetector {
  const MoodDetector();

  MoodResult detect({
    required List<TrackFeatures> recentlyPlayed,
    required MoodVector baseline,
    required SessionState sessionState,
    required TimeOfDay tod,
  }) {
    final obs = _observed(recentlyPlayed);
    final weights = <Mood, double>{};

    for (final m in Mood.values) {
      // 1) fit to what's playing (energy + valence proximity)
      final de = (m.energyAffinity - obs.energy).abs();
      final dv = (m.valenceAffinity - obs.valence).abs();
      var w = math.max(0.0, 1 - (0.6 * de + 0.4 * dv));

      // 2) blend the durable baseline prior
      w = 0.65 * w + 0.35 * (baseline.weights[m] ?? 0);

      // 3) time-of-day nudge
      w *= _todMultiplier(m, tod);

      // 4) session-state nudge
      w *= _stateMultiplier(m, sessionState);

      weights[m] = w;
    }

    return MoodResult(vector: MoodVector(weights));
  }

  ({double energy, double valence}) _observed(List<TrackFeatures> tracks) {
    if (tracks.isEmpty) return (energy: 0.5, valence: 0.5);
    // Recent tracks weigh more (recency-weighted mean).
    var e = 0.0, v = 0.0, w = 0.0;
    for (var i = 0; i < tracks.length; i++) {
      final ww = 1 + i; // later in the list = more recent = heavier
      e += tracks[i].energy * ww;
      v += tracks[i].valence * ww;
      w += ww;
    }
    return (energy: e / w, valence: v / w);
  }

  double _todMultiplier(Mood m, TimeOfDay tod) => switch (tod) {
        TimeOfDay.morning => switch (m) {
            Mood.happy || Mood.energetic || Mood.motivated => 1.2,
            Mood.melancholic || Mood.sleepy => 0.8,
            _ => 1.0,
          },
        TimeOfDay.afternoon => 1.0,
        TimeOfDay.evening => switch (m) {
            Mood.calm || Mood.romantic || Mood.reflective => 1.15,
            _ => 1.0,
          },
        TimeOfDay.night => switch (m) {
            Mood.calm || Mood.sleepy || Mood.reflective || Mood.melancholic =>
              1.25,
            Mood.energetic || Mood.aggressive => 0.7,
            _ => 1.0,
          },
      };

  double _stateMultiplier(Mood m, SessionState st) => switch (st) {
        SessionState.workout => switch (m) {
            Mood.energetic || Mood.motivated || Mood.aggressive => 1.3,
            _ => 0.9,
          },
        SessionState.studying || SessionState.focused => switch (m) {
            Mood.focused || Mood.calm => 1.25,
            _ => 0.95,
          },
        SessionState.sleeping => switch (m) {
            Mood.sleepy || Mood.calm => 1.4,
            _ => 0.7,
          },
        SessionState.relaxed => switch (m) {
            Mood.calm || Mood.reflective || Mood.romantic => 1.2,
            _ => 0.95,
          },
        _ => 1.0,
      };
}
