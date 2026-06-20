import '../model/context_enums.dart';
import '../model/results.dart';
import '../model/vectors.dart';

/// Discovery Engine (spec). Balances familiarity against exploration. High
/// engagement raises exploration; high skipping lowers it; fatigue nudges it
/// up to break monotony — but it is always capped by the listener's measured
/// tolerance.
class DiscoveryEngine {
  const DiscoveryEngine();

  DiscoveryResult compute({
    required SessionAnalysis session,
    required FatigueResult fatigue,
    required ExplorationScore exploration,
  }) {
    // Start from the listener's habitual exploration level.
    var target = exploration.value;
    final reasons = <String>[];

    // Engagement → explore more (they're receptive).
    if ((session.state == SessionState.engaged ||
            session.state == SessionState.focused) &&
        session.skipRate < 0.2) {
      target += 0.2;
      reasons.add('high engagement');
    }

    // Exploring state → they're actively seeking the new.
    if (session.state == SessionState.exploring) {
      target += 0.25;
      reasons.add('actively exploring');
    }

    // High skip rate → pull back to safe, familiar ground.
    if (session.skipRate > 0.4) {
      target -= 0.25;
      reasons.add('high skip rate — reducing exploration');
    }

    // Fatigue → inject variety (but still within tolerance).
    if (fatigue.score >= 0.5) {
      target += 0.15;
      reasons.add('fatigue — adding variety');
    }

    // Passive/sleeping → keep it familiar and unobtrusive.
    if (session.state == SessionState.passive ||
        session.state == SessionState.sleeping) {
      target -= 0.15;
      reasons.add('low-attention session — staying familiar');
    }

    // NEVER exceed tolerance (spec: never exceed user tolerance).
    final clamped = target.clamp(0.0, exploration.tolerance);

    return DiscoveryResult(
      score: clamped,
      explorationTarget: clamped,
      rationale: reasons.isEmpty ? 'baseline exploration' : reasons.join('; '),
    );
  }

  /// Discovery-value term (spec Queue Optimization): an unfamiliar track is
  /// worth more when we want exploration; a familiar one when we don't.
  double trackValue({
    required bool isFamiliar,
    required double explorationTarget,
  }) {
    return isFamiliar ? (1 - explorationTarget) : explorationTarget;
  }
}
