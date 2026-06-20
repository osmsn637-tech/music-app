import 'dart:math' as math;

import '../model/context_enums.dart';
import '../model/results.dart';
import '../model/track_features.dart';
import 'time_context.dart';

/// Energy Management Engine (spec). Builds the session energy curve and picks
/// the target energy for the *next* track — moving smoothly toward where the
/// mood/time/state want to be, while forbidding sudden crashes or spikes.
class EnergyManager {
  const EnergyManager({this.time = const TimeContextEngine()});
  final TimeContextEngine time;

  /// The most a single transition may move the energy (no spikes/crashes).
  static const maxStep = 0.18;

  EnergyPlan plan({
    required List<TrackFeatures> sessionTracks,
    required Mood mood,
    required SessionState state,
    required TimeOfDay tod,
    required double preferredCenter,
  }) {
    final recent =
        sessionTracks.map((t) => t.energy).toList(growable: false);
    final current = recent.isEmpty ? preferredCenter : recent.last;

    // Where the context wants the energy to sit.
    var desired = 0.5 * mood.energyAffinity +
        0.3 * preferredCenter +
        0.2 * (current); // anchor partly on the now, for continuity
    desired = (desired + time.adaptationFor(tod).energyBias)
        .clamp(0.0, 1.0);
    desired = _stateBias(desired, state);

    // Move toward desired but cap the step so the curve stays smooth.
    final delta = (desired - current).clamp(-maxStep, maxStep);
    final target = (current + delta).clamp(0.0, 1.0);

    final intent = delta > 0.03
        ? 'build'
        : delta < -0.03
            ? 'cooldown'
            : 'sustain';

    // Curve: the recent trail + the projected next point.
    final curve = <double>[
      ...recent.length > 8 ? recent.sublist(recent.length - 8) : recent,
      target,
    ];

    return EnergyPlan(
      currentEnergy: current,
      targetEnergy: target,
      curve: curve,
      intent: intent,
    );
  }

  double _stateBias(double e, SessionState state) => switch (state) {
        SessionState.workout => math.max(e, 0.72),
        SessionState.sleeping => math.min(e, 0.25),
        SessionState.studying => e.clamp(0.25, 0.55),
        SessionState.relaxed => math.min(e, 0.45),
        _ => e,
      };

  /// Energy-match term (spec Queue Optimization): how close a candidate's
  /// energy is to the target, 0..1.
  double matchScore(double trackEnergy, double targetEnergy) =>
      (1 - (trackEnergy - targetEnergy).abs()).clamp(0.0, 1.0);
}
