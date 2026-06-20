import '../model/context_enums.dart';
import '../model/results.dart';

/// AutoMix Integration (spec). Translates the listener context into the
/// directives the AutoMix engine consumes: target energy, transition style +
/// duration, and the mood/fatigue/session/location state. Style and duration
/// adapt to *who's listening right now*, not just static preference.
class AutoMixBridge {
  const AutoMixBridge();

  AutoMixDirectives toDirectives({
    required EnergyPlan energy,
    required Mood mood,
    required FatigueResult fatigue,
    required SessionAnalysis session,
    required TimeOfDay tod,
    required LocationContext location,
    required TransitionStyle preferred,
  }) {
    final style = _style(
      preferred: preferred,
      mood: mood,
      session: session,
      tod: tod,
      location: location,
      fatigued: fatigue.isFatigued,
    );
    final duration = _duration(
      tod: tod,
      session: session,
      style: style,
      location: location,
    );

    return AutoMixDirectives(
      targetEnergy: energy.targetEnergy,
      transitionStyle: style,
      transitionDuration: duration,
      mood: mood,
      fatigued: fatigue.isFatigued,
      sessionState: session.state,
      location: location,
    );
  }

  TransitionStyle _style({
    required TransitionStyle preferred,
    required Mood mood,
    required SessionAnalysis session,
    required TimeOfDay tod,
    required LocationContext location,
    required bool fatigued,
  }) {
    // Fatigue → break the pattern; hand the choice to the adaptive picker.
    if (fatigued) return TransitionStyle.intelligentAdaptive;

    // Strong contextual overrides.
    switch (session.state) {
      case SessionState.workout:
        return TransitionStyle.club;
      case SessionState.sleeping:
        return TransitionStyle.smooth;
      case SessionState.studying:
      case SessionState.focused:
        return TransitionStyle.minimal;
      case SessionState.driving:
        return TransitionStyle.smooth;
      default:
        break;
    }

    if (tod == TimeOfDay.night) return TransitionStyle.cinematic;
    if (mood == Mood.aggressive || mood == Mood.energetic) {
      return TransitionStyle.club;
    }
    if (mood == Mood.romantic || mood == Mood.reflective) {
      return TransitionStyle.cinematic;
    }
    // Otherwise honour the learned preference.
    return preferred;
  }

  Duration _duration({
    required TimeOfDay tod,
    required SessionAnalysis session,
    required TransitionStyle style,
    required LocationContext location,
  }) {
    // Base on the time-of-day smoothness, then adjust for energy/context.
    var seconds = switch (tod) {
      TimeOfDay.night => 12.0,
      TimeOfDay.evening => 9.0,
      TimeOfDay.afternoon => 7.0,
      TimeOfDay.morning => 6.0,
    };
    switch (session.state) {
      case SessionState.workout:
        seconds = 4.0; // tight, punchy
      case SessionState.sleeping:
        seconds = 16.0; // long, imperceptible
      case SessionState.studying:
      case SessionState.focused:
        seconds = 10.0;
      default:
        break;
    }
    if (style == TransitionStyle.club) seconds = seconds.clamp(4.0, 8.0);
    if (style == TransitionStyle.cinematic) seconds = seconds.clamp(8.0, 18.0);
    return Duration(milliseconds: (seconds * 1000).round());
  }
}
