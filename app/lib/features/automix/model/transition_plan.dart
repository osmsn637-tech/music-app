import 'automation.dart';
import 'automix_enums.dart';

/// The complete, self-contained instruction set the runtime executor needs
/// to perform one transition (spec §14 "Output"). Everything here is plain
/// data — no audio engine types — so a plan can be unit-tested, logged,
/// serialised, or previewed without touching SoLoud.
///
/// Time convention: [startSecOnOutgoing] is the absolute position on the
/// *outgoing* track where the mix begins. Every [AutomationCurve] inside is
/// expressed relative to that point (t=0 at mix start), running to
/// [durationSec].
class TransitionPlan {
  TransitionPlan({
    required this.type,
    required this.startSecOnOutgoing,
    required this.incomingStartSec,
    required this.durationSec,
    required this.durationBeats,
    required this.outgoing,
    required this.incoming,
    required this.score,
    required this.notes,
    required this.masterLimiter,
  });

  /// The concrete transition type chosen (never `aiSelected` in a finished
  /// plan — the planner resolves that to a winner).
  final TransitionType type;

  final double startSecOnOutgoing;
  final double incomingStartSec;
  final double durationSec;
  final int durationBeats;

  final DeckPlan outgoing;
  final DeckPlan incoming;

  final TransitionScore score;

  /// Human-readable timeline lines ("0.0s drums in", "2.1s bass swap on
  /// downbeat", …) for the UI / debugging.
  final List<String> notes;

  /// Whether to engage the master bus limiter for the duration (true when
  /// two full mixes briefly stack and could clip).
  final bool masterLimiter;

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'startSecOnOutgoing': startSecOnOutgoing,
        'incomingStartSec': incomingStartSec,
        'durationSec': durationSec,
        'durationBeats': durationBeats,
        'masterLimiter': masterLimiter,
        'score': score.toJson(),
        'outgoing': outgoing.toJson(),
        'incoming': incoming.toJson(),
        'notes': notes,
      };
}

/// Per-deck automation. The outgoing deck is already playing; the incoming
/// deck is preloaded and started silent at [DeckPlan.startAtSec].
class DeckPlan {
  DeckPlan({
    required this.role,
    required this.startAtSec,
    required this.baseGainDb,
    required this.playSpeedRatio,
    required this.pitchSemitones,
    required this.volume,
    required this.eq,
    required this.stems,
    required this.reverbWet,
    required this.echoWet,
  });

  /// 'outgoing' | 'incoming' — purely descriptive.
  final String role;

  /// Where this deck's playhead sits at mix start (mixOut for outgoing,
  /// mixIn for incoming).
  final double startAtSec;

  /// Constant loudness-match trim in dB applied under everything else
  /// (from the LUFS delta toward the −14 LUFS target, §8).
  final double baseGainDb;

  /// Tempo scale for beat-matching (1.0 = untouched). Combined with
  /// [pitchSemitones] the executor can change tempo while preserving pitch.
  final double playSpeedRatio;

  /// Net pitch shift in semitones: the harmonic-mix shift (§4) *plus* the
  /// correction that cancels [playSpeedRatio]'s resampling side-effect, so
  /// the heard pitch lands where the plan intends.
  final double pitchSemitones;

  /// Master volume curve for this deck (0..1).
  final AutomationCurve volume;

  /// Dynamic-EQ moves (band ducks over time).
  final List<EqMove> eq;

  /// Per-stem volume curves when stems are available (keys: vocals, drums,
  /// bass, other). Null → play the full mixed file on this deck.
  final Map<String, AutomationCurve>? stems;

  /// Reverb / echo send levels (0..1) for tail transitions (§10 G/H).
  final AutomationCurve reverbWet;
  final AutomationCurve echoWet;

  bool get usesStems => stems != null && stems!.isNotEmpty;

  Map<String, dynamic> toJson() => {
        'role': role,
        'startAtSec': startAtSec,
        'baseGainDb': baseGainDb,
        'playSpeedRatio': playSpeedRatio,
        'pitchSemitones': pitchSemitones,
        'volume': volume.toJson(),
        'eq': eq.map((e) => e.toJson()).toList(),
        if (stems != null)
          'stems': stems!.map((k, v) => MapEntry(k, v.toJson())),
        'reverbWet': reverbWet.toJson(),
        'echoWet': echoWet.toJson(),
      };
}

/// The §12 scoring breakdown. Weights are fixed by the spec:
///   0.25·BPM + 0.25·Key + 0.20·Energy + 0.15·Structure + 0.15·Stem
class TransitionScore {
  const TransitionScore({
    required this.bpmMatch,
    required this.keyMatch,
    required this.energyMatch,
    required this.structuralMatch,
    required this.stemCompatibility,
  });

  final double bpmMatch; // 0..1
  final double keyMatch; // 0..1
  final double energyMatch; // 0..1
  final double structuralMatch; // 0..1
  final double stemCompatibility; // 0..1

  static const wBpm = 0.25;
  static const wKey = 0.25;
  static const wEnergy = 0.20;
  static const wStructure = 0.15;
  static const wStem = 0.15;

  double get total =>
      wBpm * bpmMatch +
      wKey * keyMatch +
      wEnergy * energyMatch +
      wStructure * structuralMatch +
      wStem * stemCompatibility;

  Map<String, dynamic> toJson() => {
        'bpmMatch': bpmMatch,
        'keyMatch': keyMatch,
        'energyMatch': energyMatch,
        'structuralMatch': structuralMatch,
        'stemCompatibility': stemCompatibility,
        'total': total,
      };
}
