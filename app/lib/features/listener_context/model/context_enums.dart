import '../../automix/model/automix_enums.dart';

/// What the listener is *doing* this session (spec: Real-Time Session
/// Analysis). Inferred from interaction patterns, not declared.
enum SessionState {
  engaged, // attentive, low skips, lets tracks play
  passive, // playing in the background, little interaction
  exploring, // searching, jumping around, manual picks
  focused, // long uninterrupted stretches, low-energy stable
  relaxed, // calm, low energy, low interaction
  workout, // high energy, high BPM, steady
  driving, // long session, medium energy, few skips
  studying, // long, instrumental/low-vocal, very low interaction
  sleeping; // late night, falling energy, near-zero interaction

  String get label => name[0].toUpperCase() + name.substring(1);
}

/// Inferred emotional tone (spec: Mood Detection Engine).
enum Mood {
  happy,
  energetic,
  calm,
  focused,
  melancholic,
  motivated,
  reflective,
  romantic,
  aggressive,
  sleepy;

  String get label => name[0].toUpperCase() + name.substring(1);

  /// Rough target energy (0..1) a mood pulls toward — used by the energy
  /// manager and as a mood prior from track energy.
  double get energyAffinity => switch (this) {
        Mood.energetic => 0.9,
        Mood.aggressive => 0.95,
        Mood.motivated => 0.8,
        Mood.happy => 0.7,
        Mood.romantic => 0.45,
        Mood.focused => 0.5,
        Mood.reflective => 0.35,
        Mood.calm => 0.3,
        Mood.melancholic => 0.3,
        Mood.sleepy => 0.12,
      };

  /// Rough target valence (0..1, musical positivity) a mood pulls toward.
  double get valenceAffinity => switch (this) {
        Mood.happy => 0.85,
        Mood.energetic => 0.75,
        Mood.motivated => 0.7,
        Mood.romantic => 0.6,
        Mood.calm => 0.55,
        Mood.focused => 0.5,
        Mood.sleepy => 0.45,
        Mood.reflective => 0.35,
        Mood.melancholic => 0.2,
        Mood.aggressive => 0.3,
      };
}

/// Spec time buckets. Morning 05–11, Afternoon 11–17, Evening 17–22,
/// Night 22–05.
enum TimeOfDay {
  morning,
  afternoon,
  evening,
  night;

  String get label => name[0].toUpperCase() + name.substring(1);

  static TimeOfDay from(DateTime t) {
    final h = t.hour;
    if (h >= 5 && h < 11) return TimeOfDay.morning;
    if (h >= 11 && h < 17) return TimeOfDay.afternoon;
    if (h >= 17 && h < 22) return TimeOfDay.evening;
    return TimeOfDay.night;
  }
}

/// Optional location/activity signal. The app has no GPS today, so this is a
/// pluggable hint that defaults to [unknown]; the engine degrades gracefully.
enum LocationContext {
  home,
  work,
  gym,
  car,
  walking,
  traveling,
  unknown;

  String get label => name[0].toUpperCase() + name.substring(1);
}

/// Listener-facing transition styles (spec: AutoMix Integration). Each maps
/// onto one of the AutoMix engine's concrete [TransitionType]s.
enum TransitionStyle {
  smooth,
  harmonic,
  club,
  cinematic,
  minimal,
  intelligentAdaptive;

  String get label => switch (this) {
        TransitionStyle.smooth => 'Smooth',
        TransitionStyle.harmonic => 'Harmonic',
        TransitionStyle.club => 'Club',
        TransitionStyle.cinematic => 'Cinematic',
        TransitionStyle.minimal => 'Minimal',
        TransitionStyle.intelligentAdaptive => 'Intelligent Adaptive',
      };

  /// The AutoMix [TransitionType] this style requests.
  TransitionType get automixType => switch (this) {
        TransitionStyle.smooth => TransitionType.smoothBlend,
        TransitionStyle.harmonic => TransitionType.harmonicMix,
        TransitionStyle.club => TransitionType.clubMix,
        TransitionStyle.cinematic => TransitionType.reverbTail,
        TransitionStyle.minimal => TransitionType.instrumentalOverlay,
        TransitionStyle.intelligentAdaptive => TransitionType.aiSelected,
      };

  static TransitionStyle fromAutomix(TransitionType t) => switch (t) {
        TransitionType.smoothBlend => TransitionStyle.smooth,
        TransitionType.harmonicMix => TransitionStyle.harmonic,
        TransitionType.clubMix => TransitionStyle.club,
        TransitionType.reverbTail ||
        TransitionType.echoOut ||
        TransitionType.breakdown =>
          TransitionStyle.cinematic,
        TransitionType.instrumentalOverlay ||
        TransitionType.drumSwap ||
        TransitionType.bassSwap =>
          TransitionStyle.minimal,
        TransitionType.aiSelected => TransitionStyle.intelligentAdaptive,
      };
}
