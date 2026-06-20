import 'context_enums.dart';
import 'session_event.dart';
import 'vectors.dart';

/// The durable listener model (spec: User Profile Model). Rebuilt from
/// persisted stats; the vectors update continuously as history grows.
class ListenerProfile {
  const ListenerProfile({
    required this.taste,
    required this.baselineMood,
    required this.energyPreference,
    required this.exploration,
    required this.preferredBpm,
    required this.preferredLoudnessLufs,
    required this.preferredTransitionStyle,
    required this.preferredSessionLength,
    required this.likedSongIds,
    required this.dislikedSongIds,
    required this.hiddenSongIds,
    required this.chronicallySkippedSongIds,
    required this.topGenres,
    required this.topArtists,
    required this.topAlbums,
  });

  final TasteVector taste;
  final MoodVector baselineMood;
  final EnergyPreferenceVector energyPreference;
  final ExplorationScore exploration;
  final PreferenceRange preferredBpm;
  final PreferenceRange preferredLoudnessLufs;
  final TransitionStyle preferredTransitionStyle;
  final Duration preferredSessionLength;

  final Set<String> likedSongIds;
  final Set<String> dislikedSongIds;
  final Set<String> hiddenSongIds;
  final Set<String> chronicallySkippedSongIds;

  final List<String> topGenres;
  final List<String> topArtists;
  final List<String> topAlbums;

  /// A song the listener never wants surfaced (hidden or disliked).
  bool isSuppressed(String songId) =>
      hiddenSongIds.contains(songId) || dislikedSongIds.contains(songId);

  Map<String, dynamic> toJson() => {
        'taste': taste.toJson(),
        'baselineMood': baselineMood.toJson(),
        'energyPreference': energyPreference.toJson(),
        'exploration': exploration.toJson(),
        'preferredBpm': preferredBpm.toJson(),
        'preferredLoudnessLufs': preferredLoudnessLufs.toJson(),
        'preferredTransitionStyle': preferredTransitionStyle.name,
        'preferredSessionLengthMin': preferredSessionLength.inMinutes,
        'topGenres': topGenres,
        'topArtists': topArtists,
        'topAlbums': topAlbums,
        'counts': {
          'liked': likedSongIds.length,
          'disliked': dislikedSongIds.length,
          'hidden': hiddenSongIds.length,
          'chronicallySkipped': chronicallySkippedSongIds.length,
        },
      };
}

/// Output of the session analyzer.
class SessionAnalysis {
  const SessionAnalysis({
    required this.state,
    required this.confidence,
    required this.sessionDuration,
    required this.skipRate,
    required this.interactionRate,
    required this.churnRate,
    required this.tracksThisSession,
  });

  final SessionState state;
  final double confidence; // 0..1 (×100 for the spec's 0–100)
  final Duration sessionDuration;
  final double skipRate; // skips / tracks started
  final double interactionRate; // interactions / minute
  final double churnRate; // churn events / minute
  final int tracksThisSession;

  int get confidence100 => (confidence * 100).round().clamp(0, 100);

  Map<String, dynamic> toJson() => {
        'state': state.name,
        'confidence': confidence100,
        'sessionDurationMin': sessionDuration.inMinutes,
        'skipRate': skipRate,
        'interactionRate': interactionRate,
        'churnRate': churnRate,
        'tracks': tracksThisSession,
      };
}

class MoodResult {
  const MoodResult({required this.vector});
  final MoodVector vector;

  Mood get mood => vector.dominant;
  double get confidence => vector.confidence;
  int get confidence100 => (confidence * 100).round().clamp(0, 100);

  Map<String, dynamic> toJson() => vector.toJson();
}

/// Output of the energy manager: where to take the next track and the curve
/// the session is tracing.
class EnergyPlan {
  const EnergyPlan({
    required this.currentEnergy,
    required this.targetEnergy,
    required this.curve,
    required this.intent,
  });

  final double currentEnergy; // 0..1
  final double targetEnergy; // 0..1 for the NEXT track
  final List<double> curve; // recent + projected energy, 0..1

  /// 'build' | 'sustain' | 'cooldown' — the shape of the move.
  final String intent;

  int get targetEnergy100 => (targetEnergy * 100).round().clamp(0, 100);

  Map<String, dynamic> toJson() => {
        'currentEnergy': (currentEnergy * 100).round(),
        'targetEnergy': targetEnergy100,
        'intent': intent,
        'curve': curve.map((e) => (e * 100).round()).toList(),
      };
}

/// Output of the fatigue detector.
class FatigueResult {
  const FatigueResult({
    required this.score,
    required this.signals,
    required this.recommendations,
  });

  final double score; // 0..1
  final List<String> signals; // which signals fired
  final List<String> recommendations; // remedies (variety, discovery, …)

  int get score100 => (score * 100).round().clamp(0, 100);
  bool get isFatigued => score >= 0.5;

  Map<String, dynamic> toJson() => {
        'score': score100,
        'signals': signals,
        'recommendations': recommendations,
      };
}

/// Output of the discovery engine.
class DiscoveryResult {
  const DiscoveryResult({
    required this.score,
    required this.explorationTarget,
    required this.rationale,
  });

  /// How much discovery to inject right now, 0..1 (spec: Discovery Score).
  final double score;

  /// Fraction of the next picks that should be unfamiliar (≤ tolerance).
  final double explorationTarget;
  final String rationale;

  int get score100 => (score * 100).round().clamp(0, 100);

  Map<String, dynamic> toJson() => {
        'score': score100,
        'explorationTarget': explorationTarget,
        'rationale': rationale,
      };
}

/// A scored candidate with the spec's Queue Optimization breakdown.
class RankedTrack {
  const RankedTrack({
    required this.songId,
    required this.finalScore,
    required this.tasteMatch,
    required this.moodMatch,
    required this.energyMatch,
    required this.timeMatch,
    required this.discoveryValue,
    required this.continuity,
    required this.isFamiliar,
  });

  final String songId;
  final double finalScore; // 0..1
  final double tasteMatch;
  final double moodMatch;
  final double energyMatch;
  final double timeMatch;
  final double discoveryValue;
  final double continuity;
  final bool isFamiliar;

  // Spec weights.
  static const wTaste = 0.35;
  static const wMood = 0.20;
  static const wEnergy = 0.15;
  static const wTime = 0.10;
  static const wDiscovery = 0.10;
  static const wContinuity = 0.10;

  Map<String, dynamic> toJson() => {
        'songId': songId,
        'finalScore': double.parse(finalScore.toStringAsFixed(4)),
        'breakdown': {
          'taste': double.parse(tasteMatch.toStringAsFixed(3)),
          'mood': double.parse(moodMatch.toStringAsFixed(3)),
          'energy': double.parse(energyMatch.toStringAsFixed(3)),
          'time': double.parse(timeMatch.toStringAsFixed(3)),
          'discovery': double.parse(discoveryValue.toStringAsFixed(3)),
          'continuity': double.parse(continuity.toStringAsFixed(3)),
        },
      };
}

/// What the context layer hands the AutoMix engine (spec: AutoMix
/// Integration).
class AutoMixDirectives {
  const AutoMixDirectives({
    required this.targetEnergy,
    required this.transitionStyle,
    required this.transitionDuration,
    required this.mood,
    required this.fatigued,
    required this.sessionState,
    required this.location,
  });

  final double targetEnergy; // 0..1
  final TransitionStyle transitionStyle;
  final Duration transitionDuration;
  final Mood mood;
  final bool fatigued;
  final SessionState sessionState;
  final LocationContext location;

  Map<String, dynamic> toJson() => {
        'targetEnergy': (targetEnergy * 100).round(),
        'transitionStyle': transitionStyle.name,
        'automixType': transitionStyle.automixType.name,
        'transitionDurationSec': transitionDuration.inMilliseconds / 1000.0,
        'mood': mood.name,
        'fatigued': fatigued,
        'sessionState': sessionState.name,
        'location': location.name,
      };
}

/// Per-time-of-day adaptation knobs (spec: Time Context Engine).
class TimeAdaptation {
  const TimeAdaptation({
    required this.energyBias,
    required this.valenceBias,
    required this.transitionSmoothness,
    required this.note,
  });

  /// Added to the target energy (−.. +), e.g. +morning uplift, −night.
  final double energyBias;
  final double valenceBias;

  /// 0..1, higher → longer/smoother transitions (night).
  final double transitionSmoothness;
  final String note;
}

/// Bundle of recent session events + derived counts, passed between engines.
class SessionWindow {
  const SessionWindow({
    required this.events,
    required this.now,
    required this.start,
  });

  final List<SessionEvent> events;
  final DateTime now;
  final DateTime start;

  Duration get duration => now.difference(start);
}
