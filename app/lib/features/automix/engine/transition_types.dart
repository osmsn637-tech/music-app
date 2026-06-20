import 'dart:math' as math;

import '../model/automation.dart';
import '../model/automix_enums.dart';
import '../model/track_analysis.dart';
import '../model/transition_plan.dart';
import 'compatibility.dart';
import 'cue_selector.dart';

/// Everything a transition-type builder needs to lay down its curves.
class TransitionContext {
  TransitionContext({
    required this.out,
    required this.incoming,
    required this.cue,
    required this.tempo,
    required this.key,
    required this.durationSec,
    required this.durationBeats,
    required this.incomingTrimDb,
  });

  final TrackAnalysis out;
  final TrackAnalysis incoming;
  final CueSelection cue;
  final TempoMatch tempo;
  final KeyMatch key;
  final double durationSec;
  final int durationBeats;
  final double incomingTrimDb;

  bool get outHasStems => out.stems.available;
  bool get inHasStems => incoming.stems.available;
  bool get bothStems => outHasStems && inHasStems;

  double get outEnergy => out.energyAt(cue.outMixOutSec);
  double get inEnergy => incoming.energyAt(cue.inMixInSec);
  double get outVocal => out.vocalRatioAt(cue.outMixOutSec);
  double get inVocal => incoming.vocalRatioAt(cue.inMixInSec);
  bool get vocalConflict => outVocal >= 0.6 && inVocal >= 0.6;

  /// Net incoming pitch shift: harmonic-mix shift, plus the correction that
  /// cancels the resampling pitch side-effect of the tempo stretch (§3:
  /// "maintain pitch while changing tempo").
  double get incomingPitchSemitones =>
      key.harmonicSemitoneShift - tempo.semitoneSideEffect;
}

/// The output of one builder.
class BuiltTransition {
  BuiltTransition({
    required this.outgoing,
    required this.incoming,
    required this.notes,
    required this.masterLimiter,
  });
  final DeckPlan outgoing;
  final DeckPlan incoming;
  final List<String> notes;
  final bool masterLimiter;
}

typedef TransitionBuilder = BuiltTransition Function(TransitionContext);

/// Registry of concrete builders. `aiSelected` is intentionally absent — the
/// planner resolves it before building.
const Map<TransitionType, TransitionBuilder> transitionBuilders = {
  TransitionType.smoothBlend: _buildSmoothBlend,
  TransitionType.clubMix: _buildClubMix,
  TransitionType.harmonicMix: _buildHarmonicMix,
  TransitionType.instrumentalOverlay: _buildInstrumentalOverlay,
  TransitionType.drumSwap: _buildDrumSwap,
  TransitionType.bassSwap: _buildBassSwap,
  TransitionType.echoOut: _buildEchoOut,
  TransitionType.reverbTail: _buildReverbTail,
  TransitionType.breakdown: _buildBreakdown,
};

// ---------------------------------------------------------------------------
// shared deck scaffolding
// ---------------------------------------------------------------------------
DeckPlan _outgoingDeck(
  TransitionContext c, {
  required AutomationCurve volume,
  List<EqMove> eq = const [],
  Map<String, AutomationCurve>? stems,
  AutomationCurve? reverbWet,
  AutomationCurve? echoWet,
}) {
  return DeckPlan(
    role: 'outgoing',
    startAtSec: c.cue.outMixOutSec,
    baseGainDb: 0,
    playSpeedRatio: 1.0, // never re-pitch the track already playing
    pitchSemitones: 0,
    volume: volume,
    eq: eq,
    stems: stems,
    reverbWet: reverbWet ?? AutomationCurve.constant(0),
    echoWet: echoWet ?? AutomationCurve.constant(0),
  );
}

DeckPlan _incomingDeck(
  TransitionContext c, {
  required AutomationCurve volume,
  List<EqMove> eq = const [],
  Map<String, AutomationCurve>? stems,
  AutomationCurve? reverbWet,
  AutomationCurve? echoWet,
}) {
  return DeckPlan(
    role: 'incoming',
    startAtSec: c.cue.inMixInSec,
    baseGainDb: c.incomingTrimDb,
    playSpeedRatio: c.tempo.incomingSpeedRatio,
    pitchSemitones: c.incomingPitchSemitones,
    volume: volume,
    eq: eq,
    stems: stems,
    reverbWet: reverbWet ?? AutomationCurve.constant(0),
    echoWet: echoWet ?? AutomationCurve.constant(0),
  );
}

/// Standard §6 stem entrance order for the *incoming* deck over [dur]:
/// drums first, then bass, then harmony (other), then lead vocals last.
Map<String, AutomationCurve> _incomingStemOrder(double dur,
    {bool delayVocals = true}) {
  return {
    'drums': AutomationCurve.ramp(0, 1, dur * 0.25),
    'bass': AutomationCurve([
      Keyframe(0, 0),
      Keyframe(dur * 0.2, 0),
      Keyframe(dur * 0.5, 1),
    ]),
    'other': AutomationCurve([
      Keyframe(0, 0),
      Keyframe(dur * 0.45, 0),
      Keyframe(dur * 0.7, 1),
    ]),
    'vocals': AutomationCurve([
      Keyframe(0, 0),
      Keyframe(dur * (delayVocals ? 0.8 : 0.5), 0),
      Keyframe(dur, 1),
    ]),
  };
}

/// Mirror for the *outgoing* deck: shed lead vocals first, then harmony,
/// then bass, keep drums longest (§6: "fade vocals before other elements").
Map<String, AutomationCurve> _outgoingStemExit(double dur) {
  return {
    'vocals': AutomationCurve.ramp(1, 0, dur * 0.3),
    'other': AutomationCurve([
      Keyframe(0, 1),
      Keyframe(dur * 0.4, 1),
      Keyframe(dur * 0.6, 0),
    ]),
    'bass': AutomationCurve([
      Keyframe(0, 1),
      Keyframe(dur * 0.45, 1),
      Keyframe(dur * 0.55, 0), // bass swap point
    ]),
    'drums': AutomationCurve([
      Keyframe(0, 1),
      Keyframe(dur * 0.7, 1),
      Keyframe(dur, 0),
    ]),
  };
}

/// A bass duck on the incoming deck so two low ends don't stack (§7 rule 1:
/// both tracks have bass → cut incoming bass 3–6 dB until the swap).
EqMove _incomingBassDuck(double dur, {double db = -6}) => EqMove(
      band: EqBand.bass,
      gainDb: AutomationCurve([
        Keyframe(0, db),
        Keyframe(dur * 0.5, db),
        Keyframe(dur * 0.7, 0),
      ]),
    );

/// Duck a vocal-clashing band (1–4 kHz) on the *outgoing* deck when both
/// tracks carry vocals (§7 rule 2).
EqMove _outgoingVocalDuck(double dur, {double db = -5}) => EqMove(
      band: EqBand.highMid, // 2–4 kHz, the presence range of a lead vocal
      gainDb: AutomationCurve([
        Keyframe(0, 0),
        Keyframe(dur * 0.2, db),
        Keyframe(dur * 0.8, db),
        Keyframe(dur, 0),
      ]),
    );

// ---------------------------------------------------------------------------
// A. Smooth Blend — equal-power volume crossfade, light bass de-clash
// ---------------------------------------------------------------------------
BuiltTransition _buildSmoothBlend(TransitionContext c) {
  final d = c.durationSec;
  final out = _outgoingDeck(c, volume: AutomationCurve.equalPowerOut(d));
  final inc = _incomingDeck(
    c,
    volume: AutomationCurve.equalPowerIn(d),
    eq: [_incomingBassDuck(d, db: -4)],
  );
  return BuiltTransition(
    outgoing: out,
    incoming: inc,
    masterLimiter: true,
    notes: [
      '0.0s  equal-power blend begins (${d.toStringAsFixed(1)}s)',
      'incoming bass −4 dB until 50% to keep the low end clean',
      '${d.toStringAsFixed(1)}s  outgoing out',
    ],
  );
}

// ---------------------------------------------------------------------------
// B. Club DJ Mix — beat-matched, bass-swap EQ blend over a phrase
// ---------------------------------------------------------------------------
BuiltTransition _buildClubMix(TransitionContext c) {
  final d = c.durationSec;
  // incoming rises to full in the first third and holds; outgoing holds then
  // leaves in the last third — the overlap is a full-energy beat-matched bed
  final inVol = AutomationCurve([
    Keyframe(0, 0),
    Keyframe(d * 0.33, 1.0),
    Keyframe(d, 1.0),
  ]);
  final outVol = AutomationCurve([
    Keyframe(0, 1.0),
    Keyframe(d * 0.66, 1.0),
    Keyframe(d, 0),
  ]);
  // bass swap on the centre downbeat: outgoing bass killed, incoming raised
  final outBass = EqMove(
    band: EqBand.bass,
    gainDb: AutomationCurve([
      Keyframe(0, 0),
      Keyframe(d * 0.45, 0),
      Keyframe(d * 0.55, -24),
    ]),
  );
  final out = _outgoingDeck(
    c,
    volume: outVol,
    eq: [outBass, if (c.vocalConflict) _outgoingVocalDuck(d)],
  );
  final inc = _incomingDeck(
    c,
    volume: inVol,
    eq: [_incomingBassDuck(d, db: -24)], // hard bass kill until the swap
  );
  return BuiltTransition(
    outgoing: out,
    incoming: inc,
    masterLimiter: true,
    notes: [
      'beat-match: incoming ×${c.tempo.incomingSpeedRatio.toStringAsFixed(3)} '
          '→ ${c.tempo.matchedBpm.toStringAsFixed(1)} BPM',
      'incoming up over first ${(d * 0.33).toStringAsFixed(1)}s, full bed',
      '${(d * 0.5).toStringAsFixed(1)}s  bass swap on downbeat',
      if (c.vocalConflict) 'outgoing 2–4 kHz ducked (vocal clash)',
      '${d.toStringAsFixed(1)}s  outgoing out',
    ],
  );
}

// ---------------------------------------------------------------------------
// C. Harmonic Mix — key-aligned gentle blend
// ---------------------------------------------------------------------------
BuiltTransition _buildHarmonicMix(TransitionContext c) {
  final d = c.durationSec;
  final out = _outgoingDeck(c, volume: AutomationCurve.equalPowerOut(d));
  final inc = _incomingDeck(
    c,
    volume: AutomationCurve.equalPowerIn(d),
    eq: [_incomingBassDuck(d, db: -5)],
  );
  final shift = c.key.harmonicSemitoneShift;
  return BuiltTransition(
    outgoing: out,
    incoming: inc,
    masterLimiter: true,
    notes: [
      'harmonic: ${c.key.outCode} ↔ ${c.key.inCode}'
          '${shift == 0 ? ' (compatible, no shift)' : ', incoming ${shift > 0 ? '+' : ''}$shift st'}',
      'equal-power blend ${d.toStringAsFixed(1)}s, low-end de-clash',
    ],
  );
}

// ---------------------------------------------------------------------------
// D. Instrumental Overlay — bring incoming in under the outgoing outro
// ---------------------------------------------------------------------------
BuiltTransition _buildInstrumentalOverlay(TransitionContext c) {
  final d = c.durationSec;
  // outgoing holds nearly full and only leaves at the very end; incoming
  // swells underneath, vocals last
  final outVol = AutomationCurve([
    Keyframe(0, 1.0),
    Keyframe(d * 0.7, 0.9),
    Keyframe(d, 0),
  ]);
  final inVol = AutomationCurve([
    Keyframe(0, 0),
    Keyframe(d * 0.6, 0.7),
    Keyframe(d, 1.0),
  ]);
  final inc = _incomingDeck(
    c,
    volume: inVol,
    eq: [_incomingBassDuck(d, db: -6)],
    stems: c.inHasStems
        ? _incomingStemOrder(d, delayVocals: true)
        : null,
  );
  final out = _outgoingDeck(c, volume: outVol);
  return BuiltTransition(
    outgoing: out,
    incoming: inc,
    masterLimiter: true,
    notes: [
      'incoming swells under the outgoing ${c.out.outroSection?.label.name ?? 'outro'}',
      if (c.inHasStems) 'incoming vocals held until 80% (§6 order)',
      '${d.toStringAsFixed(1)}s  outgoing out',
    ],
  );
}

// ---------------------------------------------------------------------------
// E. Drum Swap — incoming drums first, outgoing drums out (needs stems)
// ---------------------------------------------------------------------------
BuiltTransition _buildDrumSwap(TransitionContext c) {
  final d = c.durationSec;
  final out = _outgoingDeck(
    c,
    volume: AutomationCurve([Keyframe(0, 1), Keyframe(d * 0.85, 1), Keyframe(d, 0)]),
    stems: _outgoingStemExit(d),
  );
  final inStems = _incomingStemOrder(d, delayVocals: true)
    ..['drums'] = AutomationCurve.ramp(0, 1, d * 0.15); // drums in fast
  final inc = _incomingDeck(
    c,
    volume: AutomationCurve([Keyframe(0, 1), Keyframe(d, 1)]),
    stems: inStems,
  );
  return BuiltTransition(
    outgoing: out,
    incoming: inc,
    masterLimiter: true,
    notes: [
      '0.0s  incoming drums in',
      '${(d * 0.5).toStringAsFixed(1)}s  bass handoff',
      '${(d * 0.7).toStringAsFixed(1)}s  harmony in, vocals last',
      'outgoing sheds vocals→harmony→bass→drums',
    ],
  );
}

// ---------------------------------------------------------------------------
// F. Bass Swap — hand off the low end on a downbeat (needs stems)
// ---------------------------------------------------------------------------
BuiltTransition _buildBassSwap(TransitionContext c) {
  final d = c.durationSec;
  final swap = d * 0.5;
  final out = _outgoingDeck(
    c,
    volume: AutomationCurve([Keyframe(0, 1), Keyframe(d * 0.8, 1), Keyframe(d, 0)]),
    stems: {
      'bass': AutomationCurve([Keyframe(0, 1), Keyframe(swap, 1), Keyframe(swap + 0.05, 0)]),
      'drums': AutomationCurve([Keyframe(0, 1), Keyframe(d * 0.75, 1), Keyframe(d, 0)]),
      'other': AutomationCurve([Keyframe(0, 1), Keyframe(d * 0.6, 1), Keyframe(d * 0.8, 0)]),
      'vocals': AutomationCurve.ramp(1, 0, d * 0.3),
    },
  );
  final inc = _incomingDeck(
    c,
    volume: AutomationCurve([Keyframe(0, 1), Keyframe(d, 1)]),
    stems: {
      'bass': AutomationCurve([Keyframe(0, 0), Keyframe(swap, 0), Keyframe(swap + 0.05, 1)]),
      'drums': AutomationCurve.ramp(0, 1, d * 0.2),
      'other': AutomationCurve([Keyframe(0, 0), Keyframe(d * 0.5, 0), Keyframe(d * 0.7, 1)]),
      'vocals': AutomationCurve([Keyframe(0, 0), Keyframe(d * 0.8, 0), Keyframe(d, 1)]),
    },
  );
  return BuiltTransition(
    outgoing: out,
    incoming: inc,
    masterLimiter: true,
    notes: [
      '${swap.toStringAsFixed(1)}s  bass swap on the downbeat — clean low-end handoff',
      'drums cross under, vocals last',
    ],
  );
}

// ---------------------------------------------------------------------------
// G. Echo Out — delay throw on the outgoing tail, then cut
// ---------------------------------------------------------------------------
BuiltTransition _buildEchoOut(TransitionContext c) {
  final d = c.durationSec;
  final out = _outgoingDeck(
    c,
    // outgoing rides full, then the echo catches it as the dry signal cuts
    volume: AutomationCurve([
      Keyframe(0, 1),
      Keyframe(d * 0.55, 1),
      Keyframe(d * 0.65, 0), // dry cut — only the echo tail remains
    ]),
    echoWet: AutomationCurve([
      Keyframe(0, 0),
      Keyframe(d * 0.5, 0),
      Keyframe(d * 0.6, 0.8),
      Keyframe(d, 0.0),
    ]),
  );
  final inc = _incomingDeck(
    c,
    volume: AutomationCurve([
      Keyframe(0, 0),
      Keyframe(d * 0.55, 0),
      Keyframe(d * 0.8, 1),
    ]),
    eq: [_incomingBassDuck(d, db: -3)],
  );
  return BuiltTransition(
    outgoing: out,
    incoming: inc,
    masterLimiter: true,
    notes: [
      '${(d * 0.6).toStringAsFixed(1)}s  echo throw on outgoing, dry cut',
      'incoming rises out of the echo tail',
    ],
  );
}

// ---------------------------------------------------------------------------
// H. Reverb Tail — wash the outgoing tail into the incoming
// ---------------------------------------------------------------------------
BuiltTransition _buildReverbTail(TransitionContext c) {
  final d = c.durationSec;
  final out = _outgoingDeck(
    c,
    volume: AutomationCurve([
      Keyframe(0, 1),
      Keyframe(d * 0.5, 1),
      Keyframe(d * 0.75, 0),
    ]),
    reverbWet: AutomationCurve([
      Keyframe(0, 0),
      Keyframe(d * 0.4, 0.1),
      Keyframe(d * 0.7, 0.9),
      Keyframe(d, 0.4),
    ]),
  );
  final inc = _incomingDeck(
    c,
    volume: AutomationCurve([Keyframe(0, 0), Keyframe(d * 0.5, 0.2), Keyframe(d, 1)]),
    eq: [_incomingBassDuck(d, db: -4)],
  );
  return BuiltTransition(
    outgoing: out,
    incoming: inc,
    masterLimiter: true,
    notes: [
      'outgoing dissolves into a reverb wash by ${(d * 0.7).toStringAsFixed(1)}s',
      'incoming emerges from the tail',
    ],
  );
}

// ---------------------------------------------------------------------------
// I. Breakdown Transition — strip outgoing to a breakdown, slam incoming drop
// ---------------------------------------------------------------------------
BuiltTransition _buildBreakdown(TransitionContext c) {
  final d = c.durationSec;
  // outgoing: kill drums+bass (energy dip), keep harmony as a pad, then out
  final out = _outgoingDeck(
    c,
    volume: AutomationCurve([Keyframe(0, 1), Keyframe(d * 0.5, 0.8), Keyframe(d * 0.7, 0)]),
    eq: [
      EqMove(
        band: EqBand.bass,
        gainDb: AutomationCurve([Keyframe(0, 0), Keyframe(d * 0.25, -24)]),
      ),
      EqMove(
        band: EqBand.subBass,
        gainDb: AutomationCurve([Keyframe(0, 0), Keyframe(d * 0.25, -24)]),
      ),
    ],
    stems: c.outHasStems
        ? {
            'drums': AutomationCurve.ramp(1, 0, d * 0.3),
            'bass': AutomationCurve.ramp(1, 0, d * 0.3),
            'other': AutomationCurve([Keyframe(0, 1), Keyframe(d * 0.6, 1), Keyframe(d * 0.7, 0)]),
            'vocals': AutomationCurve.ramp(1, 0, d * 0.2),
          }
        : null,
  );
  // incoming: hold silent through the breakdown, then slam in at the drop
  final inc = _incomingDeck(
    c,
    volume: AutomationCurve([
      Keyframe(0, 0),
      Keyframe(d * 0.65, 0),
      Keyframe(d * 0.7, 1.0), // the drop hits
    ]),
  );
  return BuiltTransition(
    outgoing: out,
    incoming: inc,
    masterLimiter: true,
    notes: [
      'outgoing stripped to a breakdown (bass/drums killed) by ${(d * 0.3).toStringAsFixed(1)}s',
      '${(d * 0.7).toStringAsFixed(1)}s  incoming slams in'
          '${c.incoming.cuePoints.firstDropSec != null ? ' on its drop' : ''}',
    ],
  );
}

/// Convenience: the default phrase length (in beats) a type wants. Longer,
/// blended types use a full 16-beat phrase; punchy ones are shorter.
int defaultBeatsFor(TransitionType t) {
  switch (t) {
    case TransitionType.smoothBlend:
    case TransitionType.harmonicMix:
    case TransitionType.instrumentalOverlay:
    case TransitionType.reverbTail:
      return 32; // long, gentle (8 bars)
    case TransitionType.clubMix:
    case TransitionType.drumSwap:
    case TransitionType.bassSwap:
      return 16; // 4 bars
    case TransitionType.echoOut:
    case TransitionType.breakdown:
      return 16;
    case TransitionType.aiSelected:
      return 16;
  }
}

/// Clamp helper used by the planner when sizing a transition.
int clampBeats(int beats) => math.max(4, math.min(64, beats));
