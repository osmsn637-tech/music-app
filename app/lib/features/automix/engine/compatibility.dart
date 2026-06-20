import 'dart:math' as math;

import '../model/automix_enums.dart';
import '../model/track_analysis.dart';

/// The five scoring primitives behind the §12 transition score. Each is a
/// pure function of the two tracks' analysis (plus the chosen mix points),
/// returning a 0..1 sub-score and, where relevant, the concrete DSP
/// parameter the executor needs (speed ratio, pitch shift, gain trim).

// ---------------------------------------------------------------------------
// BPM / beat matching (§3, score term 0.25)
// ---------------------------------------------------------------------------
class TempoMatch {
  const TempoMatch({
    required this.score,
    required this.incomingSpeedRatio,
    required this.semitoneSideEffect,
    required this.usedHalfDouble,
    required this.matchedBpm,
  });

  /// 0..1 — how clean the tempo match is (1 = already aligned).
  final double score;

  /// Playback-speed multiplier to apply to the incoming track so its beats
  /// lock to the outgoing tempo (or a half/double of it).
  final double incomingSpeedRatio;

  /// Pitch shift (semitones) that [incomingSpeedRatio]'s resampling
  /// introduces; the executor must apply the negative of this to preserve
  /// pitch. = 12·log2(ratio).
  final double semitoneSideEffect;

  final bool usedHalfDouble;
  final double matchedBpm;
}

/// Match the incoming BPM to the outgoing tempo, picking the smallest speed
/// change among same / half / double time so we never stretch a track more
/// than necessary (half/double-time mixing is rhythmically valid).
TempoMatch matchTempo(double outBpm, double inBpm) {
  if (outBpm <= 0 || inBpm <= 0) {
    return const TempoMatch(
      score: 0.3,
      incomingSpeedRatio: 1.0,
      semitoneSideEffect: 0,
      usedHalfDouble: false,
      matchedBpm: 0,
    );
  }
  // candidate speed ratios that beat-align incoming to outgoing
  final candidates = <double>[
    outBpm / inBpm, // same time
    2 * outBpm / inBpm, // incoming at double time
    0.5 * outBpm / inBpm, // incoming at half time
  ];
  // pick the ratio closest to 1.0 (least stretch / fewest artifacts)
  var ratio = candidates.first;
  for (final c in candidates) {
    if ((c - 1).abs() < (ratio - 1).abs()) ratio = c;
  }
  final usedHalfDouble = (ratio != candidates.first);
  final stretch = (ratio - 1).abs();
  // DJs comfortably ride ±6%; past ~15% the time-stretch artifacts dominate.
  final score = (1 - stretch / 0.15).clamp(0.0, 1.0);
  final semis = 12 * (math.log(ratio) / math.ln2);
  return TempoMatch(
    score: score.toDouble(),
    incomingSpeedRatio: ratio,
    semitoneSideEffect: semis,
    usedHalfDouble: usedHalfDouble,
    matchedBpm: inBpm * ratio,
  );
}

// ---------------------------------------------------------------------------
// Harmonic / key matching (§4, score term 0.25)
// ---------------------------------------------------------------------------
class KeyMatch {
  const KeyMatch({
    required this.score,
    required this.harmonicSemitoneShift,
    required this.outCode,
    required this.inCode,
  });
  final double score;

  /// Pitch shift (−2..+2) to apply to the incoming track to *improve*
  /// harmonic compatibility, or 0 if none helps within range (§4).
  final int harmonicSemitoneShift;
  final String outCode;
  final String inCode;
}

KeyMatch matchKey(MusicalKey out, MusicalKey incoming) {
  final a = out.camelot;
  final b = incoming.camelot;
  if (a == null || b == null) {
    return const KeyMatch(
        score: 0.5, harmonicSemitoneShift: 0, outCode: '?', inCode: '?');
  }
  final raw = a.compatibility(b);
  // When low-confidence key detection, pull the score toward neutral so a
  // shaky reading can't veto an otherwise-great BPM/energy match.
  final conf = math.min(out.confidence, incoming.confidence);
  final score = raw * conf + 0.5 * (1 - conf);

  var shift = 0;
  if (raw < 0.85) {
    // try a small shift of the incoming key to sit better under the outgoing
    shift = b.bestSemitoneShiftTo(a);
  }
  return KeyMatch(
    score: score.clamp(0.0, 1.0),
    harmonicSemitoneShift: shift,
    outCode: a.code,
    inCode: b.code,
  );
}

// ---------------------------------------------------------------------------
// Energy flow (§9, score term 0.20)
// ---------------------------------------------------------------------------
/// Reward a smooth, slightly-rising energy hand-off; penalise sudden drops
/// or spikes. [outEnergy]/[inEnergy] are the section energies at the mix
/// points (0..1).
double energyFlowScore(double outEnergy, double inEnergy) {
  final delta = inEnergy - outEnergy;
  // ideal: incoming a touch hotter than outgoing keeps momentum building
  const ideal = 0.05;
  final dist = (delta - ideal).abs();
  return (1 - dist / 0.5).clamp(0.0, 1.0).toDouble();
}

// ---------------------------------------------------------------------------
// Structural match (§2, score term 0.15)
// ---------------------------------------------------------------------------
class StructureMatch {
  const StructureMatch({
    required this.score,
    required this.vocalConflict,
  });
  final double score;
  final bool vocalConflict;
}

/// Score the pairing of the outgoing section (at mix-out) with the incoming
/// section (at mix-in). Preferred (§2): outro→intro, breakdown→build/drop,
/// instrumental→vocal. Penalise vocal-over-vocal.
StructureMatch matchStructure(Section? outSec, Section? inSec) {
  if (outSec == null || inSec == null) {
    return const StructureMatch(score: 0.5, vocalConflict: false);
  }
  var score = 0.5;

  // preferred structural hand-offs
  const pref = {
    (SectionLabel.outro, SectionLabel.intro): 1.0,
    (SectionLabel.breakdown, SectionLabel.intro): 0.9,
    (SectionLabel.breakdown, SectionLabel.drop): 0.95,
    (SectionLabel.outro, SectionLabel.drop): 0.85,
    (SectionLabel.outro, SectionLabel.verse): 0.8,
    (SectionLabel.bridge, SectionLabel.intro): 0.8,
    (SectionLabel.chorus, SectionLabel.intro): 0.7,
  };
  score = pref[(outSec.label, inSec.label)] ?? score;

  // instrumental → vocal entry is clean; reward it
  if (outSec.isInstrumental && inSec.isVocalHeavy) {
    score = math.max(score, 0.85);
  }

  // vocal-over-vocal is the cardinal sin — flag + penalise
  final vocalConflict = outSec.isVocalHeavy && inSec.isVocalHeavy;
  if (vocalConflict) score = math.min(score, 0.35);

  return StructureMatch(score: score.clamp(0.0, 1.0), vocalConflict: vocalConflict);
}

// ---------------------------------------------------------------------------
// Stem compatibility (§5/§6, score term 0.15)
// ---------------------------------------------------------------------------
/// With stems on both decks we have full element-level control, so the
/// hand-off is maximally clean. Without stems, compatibility is bounded by
/// how well we can avoid a vocal/bass clash at the mix point.
double stemCompatibility({
  required bool outHasStems,
  required bool inHasStems,
  required bool vocalConflict,
  required double outEnergy,
  required double inEnergy,
}) {
  if (outHasStems && inHasStems) return 1.0;
  if (outHasStems || inHasStems) {
    // one side controllable — can duck the conflicting element on that deck
    return vocalConflict ? 0.7 : 0.85;
  }
  // full-mix on both decks: a vocal clash can't be surgically removed, only
  // EQ-ducked, so cap accordingly
  var s = vocalConflict ? 0.45 : 0.75;
  // two loud full mixes stacking risks a muddy low-end clash
  if (outEnergy > 0.7 && inEnergy > 0.7) s -= 0.1;
  return s.clamp(0.0, 1.0);
}

// ---------------------------------------------------------------------------
// Loudness matching (§8)
// ---------------------------------------------------------------------------
/// Gain trim (dB) to apply to the incoming deck so its perceived loudness
/// meets the outgoing track's current level — prevents the volume jump a
/// naive crossfade causes. Clamped so we never wildly over-boost a quiet
/// master. [streamingTarget] (−14 LUFS) is the reference both tracks are
/// nominally mastered toward.
double loudnessTrimDb({
  required double outLufs,
  required double inLufs,
  double streamingTarget = -14.0,
}) {
  final trim = outLufs - inLufs; // match incoming up/down to outgoing
  return trim.clamp(-9.0, 9.0);
}
