import '../model/results.dart';
import '../model/session_event.dart';

/// Fatigue Detection (spec). Listener fatigue shows up as rising skips,
/// frequent searching, rapid queue churn and shrinking listen times. Produces
/// a 0..1 score plus the concrete remedies to apply when it climbs.
class FatigueDetector {
  const FatigueDetector();

  FatigueResult detect({
    required SessionWindow window,
    Duration recentSpan = const Duration(minutes: 10),
  }) {
    final events = window.events;
    final minutes = (window.duration.inSeconds / 60).clamp(0.5, 100000);

    final plays =
        events.where((e) => e.type == SessionEventType.play).length;
    final skips =
        events.where((e) => e.type == SessionEventType.skip).length;
    final searches =
        events.where((e) => e.type == SessionEventType.search).length;
    final queueChurn = events
        .where((e) =>
            e.type == SessionEventType.queueRemove ||
            e.type == SessionEventType.queueReorder)
        .length;

    final tracks = plays == 0 ? 1 : plays;
    final skipRate = skips / tracks;
    final searchRate = searches / minutes;
    final queueRate = queueChurn / minutes;

    // Skip-rate acceleration: skips in the recent window vs the session.
    final cutoff = window.now.subtract(recentSpan);
    final recentEvents = events.where((e) => e.at.isAfter(cutoff)).toList();
    final recentPlays =
        recentEvents.where((e) => e.type == SessionEventType.play).length;
    final recentSkips =
        recentEvents.where((e) => e.type == SessionEventType.skip).length;
    final recentSkipRate =
        recentPlays == 0 ? skipRate : recentSkips / recentPlays;
    final accelerating = recentSkipRate > skipRate + 0.15;

    // Reduced listening duration: short skips dominate.
    final shortSkips = events
        .where((e) =>
            e.type == SessionEventType.skip &&
            (e.value ?? 1.0) < 0.25) // listened <25% before skipping
        .length;
    final shortSkipRate = tracks == 0 ? 0.0 : shortSkips / tracks;

    final signals = <String>[];
    var score = 0.0;
    if (skipRate > 0.35) {
      score += 0.30;
      signals.add('elevated skip rate');
    }
    if (accelerating) {
      score += 0.20;
      signals.add('skips accelerating');
    }
    if (searchRate > 0.5) {
      score += 0.20;
      signals.add('frequent searching');
    }
    if (queueRate > 0.4) {
      score += 0.15;
      signals.add('rapid queue changes');
    }
    if (shortSkipRate > 0.25) {
      score += 0.15;
      signals.add('reduced listening duration');
    }
    score = score.clamp(0.0, 1.0);

    final recs = <String>[];
    if (score >= 0.5) {
      recs.addAll([
        'introduce variety',
        'reduce repetition',
        'increase discovery',
        'change transition style',
      ]);
    } else if (score >= 0.3) {
      recs.addAll(['introduce variety', 'change transition style']);
    }

    return FatigueResult(score: score, signals: signals, recommendations: recs);
  }
}
