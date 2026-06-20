import '../model/context_enums.dart';
import '../model/results.dart';
import '../model/session_event.dart';

/// Real-Time Session Analysis (spec). Reads the live interaction window and
/// classifies what the listener is doing, with a 0–100 confidence. Uses a
/// per-state scoring pass (not an if-else cascade) so the confidence is the
/// real margin between the winner and the runner-up.
class SessionAnalyzer {
  const SessionAnalyzer();

  SessionAnalysis analyze({
    required SessionWindow window,
    required TimeOfDay tod,
    LocationContext location = LocationContext.unknown,
    double avgEnergy = 0.5,
  }) {
    final events = window.events;
    final minutes = (window.duration.inSeconds / 60).clamp(0.5, 100000);

    final plays = events.where((e) => e.type == SessionEventType.play).length;
    final skips = events.where((e) => e.type == SessionEventType.skip).length;
    final interactions = events.where((e) => e.type.isInteraction).length;
    final churn = events.where((e) => e.type.isChurn).length;

    final tracks = plays == 0 ? 1 : plays;
    final skipRate = skips / tracks;
    final interactionRate = interactions / minutes;
    final churnRate = churn / minutes;

    final scores = _scoreStates(
      tod: tod,
      location: location,
      avgEnergy: avgEnergy,
      skipRate: skipRate,
      interactionRate: interactionRate,
      churnRate: churnRate,
      minutes: minutes.toDouble(),
    );

    final ranked = scores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top = ranked.first;
    final runnerUp = ranked.length > 1 ? ranked[1].value : 0.0;
    final confidence = (top.value <= 0)
        ? 0.2
        : ((top.value - runnerUp) / top.value * 0.6 + top.value * 0.4)
            .clamp(0.15, 1.0);

    return SessionAnalysis(
      state: top.key,
      confidence: confidence.toDouble(),
      sessionDuration: window.duration,
      skipRate: skipRate,
      interactionRate: interactionRate,
      churnRate: churnRate,
      tracksThisSession: plays,
    );
  }

  Map<SessionState, double> _scoreStates({
    required TimeOfDay tod,
    required LocationContext location,
    required double avgEnergy,
    required double skipRate,
    required double interactionRate,
    required double churnRate,
    required double minutes,
  }) {
    final isNight = tod == TimeOfDay.night;
    final isLong = minutes >= 25;
    final lowInteraction = interactionRate < 0.4;
    final veryLowInteraction = interactionRate < 0.12;
    final highChurn = churnRate > 0.6 || skipRate > 0.4;

    final s = <SessionState, double>{};

    // Exploring — restless, searching, hand-picking.
    s[SessionState.exploring] = highChurn ? 0.9 : 0.2 + churnRate.clamp(0, 0.5);

    // Engaged — present, low skips, some positive interaction.
    s[SessionState.engaged] = (1 - skipRate).clamp(0.0, 1.0) *
        (0.4 + interactionRate.clamp(0.0, 0.6));

    // Passive — barely touching the app.
    s[SessionState.passive] = veryLowInteraction ? 0.7 : (0.4 - interactionRate).clamp(0.0, 0.4);

    // Focused — long, uninterrupted, mid energy.
    s[SessionState.focused] = (isLong ? 0.5 : 0.2) +
        (lowInteraction ? 0.3 : 0.0) +
        (avgEnergy > 0.35 && avgEnergy < 0.7 ? 0.2 : 0.0);

    // Relaxed — low energy, low interaction, not night.
    s[SessionState.relaxed] =
        (avgEnergy < 0.4 ? 0.5 : 0.1) + (lowInteraction ? 0.3 : 0.0) -
            (isNight ? 0.2 : 0.0);

    // Workout — high energy, steady, low skips.
    s[SessionState.workout] = (avgEnergy > 0.7 ? 0.6 : 0.0) +
        (skipRate < 0.2 ? 0.2 : 0.0) +
        (location == LocationContext.gym ? 0.4 : 0.0);

    // Studying — long, low interaction, low-mid energy, daytime/evening.
    s[SessionState.studying] = (isLong ? 0.3 : 0.0) +
        (veryLowInteraction ? 0.4 : 0.0) +
        (avgEnergy < 0.5 ? 0.2 : 0.0) -
        (isNight ? 0.15 : 0.0);

    // Driving — long, medium energy, few skips (or car location).
    s[SessionState.driving] = (isLong ? 0.3 : 0.0) +
        (avgEnergy >= 0.45 && avgEnergy <= 0.8 ? 0.25 : 0.0) +
        (skipRate < 0.25 ? 0.15 : 0.0) +
        (location == LocationContext.car ? 0.5 : 0.0);

    // Sleeping — night, near-zero interaction, low energy.
    s[SessionState.sleeping] = (isNight ? 0.4 : 0.0) +
        (veryLowInteraction ? 0.35 : 0.0) +
        (avgEnergy < 0.35 ? 0.3 : 0.0);

    return s;
  }
}
