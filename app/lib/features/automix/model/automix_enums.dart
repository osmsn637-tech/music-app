/// Core enums + frequency-band definitions for the AutoMix engine.
///
/// Kept dependency-free (only dart:math) so every other AutoMix module
/// (model, engine, runtime) can import this without pulling in Flutter or
/// the audio engine.
library;

import 'dart:math' as math;

/// The ten transition styles the engine can plan. `aiSelected` is the
/// meta-type: the planner scores every concrete type and picks the best,
/// then rewrites `type` to the winner — so a finished [TransitionPlan]
/// never *executes* `aiSelected`, it only requests it.
enum TransitionType {
  smoothBlend, // A — long equal-power volume blend
  clubMix, // B — beat-matched, EQ-swapped DJ blend over a phrase
  harmonicMix, // C — key-aligned (pitch-shifted) blend
  instrumentalOverlay, // D — bring incoming in under outgoing's outro
  drumSwap, // E — swap outgoing drums out / incoming drums in first
  bassSwap, // F — hand off the low end on a downbeat (bass kill/raise)
  echoOut, // G — echo/delay throw on the outgoing tail, then cut
  reverbTail, // H — reverb wash the outgoing tail into the incoming
  breakdown, // I — drop outgoing to a breakdown, slam incoming drop
  aiSelected; // J — let the planner choose

  String get label => switch (this) {
        TransitionType.smoothBlend => 'Smooth Blend',
        TransitionType.clubMix => 'Club DJ Mix',
        TransitionType.harmonicMix => 'Harmonic Mix',
        TransitionType.instrumentalOverlay => 'Instrumental Overlay',
        TransitionType.drumSwap => 'Drum Swap',
        TransitionType.bassSwap => 'Bass Swap',
        TransitionType.echoOut => 'Echo Out',
        TransitionType.reverbTail => 'Reverb Tail',
        TransitionType.breakdown => 'Breakdown Transition',
        TransitionType.aiSelected => 'AI Selected',
      };

  /// Whether this type can only run when both tracks have separated stems.
  bool get requiresStems =>
      this == TransitionType.drumSwap || this == TransitionType.bassSwap;
}

/// Structural section labels emitted by the offline analyzer. `unknown`
/// covers anything the heuristic labeler couldn't place.
enum SectionLabel {
  intro,
  verse,
  chorus,
  bridge,
  outro,
  breakdown,
  drop,
  unknown;

  static SectionLabel parse(String? raw) {
    switch ((raw ?? '').toLowerCase()) {
      case 'intro':
        return SectionLabel.intro;
      case 'verse':
        return SectionLabel.verse;
      case 'chorus':
        return SectionLabel.chorus;
      case 'bridge':
        return SectionLabel.bridge;
      case 'outro':
        return SectionLabel.outro;
      case 'breakdown':
        return SectionLabel.breakdown;
      case 'drop':
        return SectionLabel.drop;
      default:
        return SectionLabel.unknown;
    }
  }

  /// Loosely, sections with little/no lead vocal — safe to mix *over*.
  bool get isLowVocalByNature =>
      this == SectionLabel.intro ||
      this == SectionLabel.outro ||
      this == SectionLabel.breakdown ||
      this == SectionLabel.drop;
}

/// Major/minor — the only two modes the Camelot wheel distinguishes.
enum KeyMode { major, minor }

/// The seven mix-console frequency bands from the spec (§7). Ranges are
/// inclusive-low / exclusive-high in Hz.
enum EqBand {
  subBass(20, 60),
  bass(60, 250),
  lowMid(250, 500),
  mid(500, 2000),
  highMid(2000, 4000),
  presence(4000, 6000),
  brilliance(6000, 20000);

  const EqBand(this.lowHz, this.highHz);
  final double lowHz;
  final double highHz;

  /// Geometric-mean centre frequency — what a single biquad peaking filter
  /// is tuned to when this band is being ducked.
  double get centerHz => math.sqrt(lowHz * highHz);

  String get label => switch (this) {
        EqBand.subBass => 'Sub Bass',
        EqBand.bass => 'Bass',
        EqBand.lowMid => 'Low Mid',
        EqBand.mid => 'Mid',
        EqBand.highMid => 'High Mid',
        EqBand.presence => 'Presence',
        EqBand.brilliance => 'Brilliance',
      };
}
