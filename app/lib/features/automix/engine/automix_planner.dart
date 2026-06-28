import '../model/automix_enums.dart';
import '../model/track_analysis.dart';
import '../model/transition_plan.dart';
import 'compatibility.dart';
import 'cue_selector.dart';
import 'transition_types.dart';

/// The AutoMix brain. Given the outgoing track's analysis + current
/// playhead and the incoming track's analysis, it:
///   1. picks beat-aligned mix points (cue selector),
///   2. computes the §12 sub-scores (tempo / key / energy / structure / stem),
///   3. enumerates the *applicable* transition types, builds each, and
///   4. returns the highest-scoring [TransitionPlan].
///
/// Pure + deterministic — no audio engine, no I/O — so it's fully unit
/// testable and cheap to run on the UI isolate ahead of the mix.
class AutoMixPlanner {
  const AutoMixPlanner();

  /// Plan the best transition. [requestedType] forces a specific style
  /// (still scored); leave null / `aiSelected` to let the planner choose.
  TransitionPlan plan({
    required TrackAnalysis out,
    required TrackAnalysis incoming,
    required double playheadSec,
    TransitionType requestedType = TransitionType.aiSelected,
    double? requestedMixOutSec,
  }) {
    final candidates = _candidatesFor(out, incoming, requestedType);

    final scored = <_ScoredPlan>[];
    for (final type in candidates) {
      final built = _buildOne(
        type: type,
        out: out,
        incoming: incoming,
        playheadSec: playheadSec,
        requestedMixOutSec: requestedMixOutSec,
      );
      scored.add(built);
    }
    scored.sort((a, b) => b.plan.score.total.compareTo(a.plan.score.total));
    return scored.first.plan;
  }

  /// Score every candidate without committing — useful for a debug/preview
  /// UI that shows why a type won.
  List<TransitionPlan> rankAll({
    required TrackAnalysis out,
    required TrackAnalysis incoming,
    required double playheadSec,
    double? requestedMixOutSec,
  }) {
    final plans = _candidatesFor(out, incoming, TransitionType.aiSelected)
        .map((t) => _buildOne(
              type: t,
              out: out,
              incoming: incoming,
              playheadSec: playheadSec,
              requestedMixOutSec: requestedMixOutSec,
            ).plan)
        .toList()
      ..sort((a, b) => b.score.total.compareTo(a.score.total));
    return plans;
  }

  // --- internals ----------------------------------------------------------

  List<TransitionType> _candidatesFor(
    TrackAnalysis out,
    TrackAnalysis incoming,
    TransitionType requested,
  ) {
    if (requested != TransitionType.aiSelected) return [requested];
    final stems = out.stems.available && incoming.stems.available;
    return TransitionType.values
        .where((t) => t != TransitionType.aiSelected)
        .where((t) => !t.requiresStems || stems)
        .toList();
  }

  _ScoredPlan _buildOne({
    required TransitionType type,
    required TrackAnalysis out,
    required TrackAnalysis incoming,
    required double playheadSec,
    double? requestedMixOutSec,
  }) {
    // 1. cue points (downbeat-aligned)
    final cue = selectCues(
      out: out,
      incoming: incoming,
      playheadSec: playheadSec,
      requestedMixOutSec: requestedMixOutSec,
    );

    // 2. size the transition for this type, phrase-aligned
    final beats = clampBeats(defaultBeatsFor(type));
    final durationSec = beatsToDurationSec(
      beats: beats,
      beatPeriod: cue.outBeatPeriod,
      mixOutSec: cue.outMixOutSec,
      trackDurationSec: out.durationSec,
    );

    // 3. sub-scores (§12)
    final tempo = matchTempo(out.bpm, incoming.bpm);
    final key = matchKey(out.key, incoming.key);
    final outSec = out.sectionAt(cue.outMixOutSec);
    final inSec = incoming.sectionAt(cue.inMixInSec);
    final energy = energyFlowScore(
      outSec?.energy ?? 0.5,
      inSec?.energy ?? 0.5,
    );
    final structure = matchStructure(outSec, inSec);
    final stemCompat = stemCompatibility(
      outHasStems: out.stems.available,
      inHasStems: incoming.stems.available,
      vocalConflict: structure.vocalConflict,
      outEnergy: outSec?.energy ?? 0.5,
      inEnergy: inSec?.energy ?? 0.5,
    );

    var score = TransitionScore(
      bpmMatch: tempo.score,
      keyMatch: key.score,
      energyMatch: energy,
      structuralMatch: structure.score,
      stemCompatibility: stemCompat,
    );

    // 4. type-fitness shaping: nudge the structural term by how well this
    //    *specific* style suits the moment, so the AI pick isn't decided by
    //    the generic sub-scores alone (a breakdown transition into an intro
    //    should beat a plain blend even at equal raw scores).
    score = _shapeForType(type, score, out, incoming, outSec, inSec, tempo);

    // 5. build the curves
    final ctx = TransitionContext(
      out: out,
      incoming: incoming,
      cue: cue,
      tempo: tempo,
      key: key,
      durationSec: durationSec,
      durationBeats: beats,
      incomingTrimDb: loudnessTrimDb(outLufs: out.lufs, inLufs: incoming.lufs),
    );
    final built = transitionBuilders[type]!(ctx);

    final plan = TransitionPlan(
      type: type,
      startSecOnOutgoing: cue.outMixOutSec,
      // Clamp the incoming cue into the track so a bad analysis mix-in can't
      // start the incoming deck past its end (→ silent / failed mix).
      incomingStartSec: cue.inMixInSec.clamp(
        0.0,
        incoming.durationSec > 1 ? incoming.durationSec - 1 : 0.0,
      ),
      durationSec: durationSec,
      durationBeats: beats,
      outgoing: built.outgoing,
      incoming: built.incoming,
      score: score,
      notes: [
        '${type.label}  ·  score ${(score.total * 100).round()}%',
        'mix out @ ${cue.outMixOutSec.toStringAsFixed(1)}s  →  '
            'mix in @ ${cue.inMixInSec.toStringAsFixed(1)}s',
        ...built.notes,
      ],
      masterLimiter: built.masterLimiter,
    );
    return _ScoredPlan(plan);
  }

  /// Bias the structural sub-score by type-appropriateness so the §12
  /// total reflects "is THIS style right here", not just raw compatibility.
  TransitionScore _shapeForType(
    TransitionType type,
    TransitionScore base,
    TrackAnalysis out,
    TrackAnalysis incoming,
    Section? outSec,
    Section? inSec,
    TempoMatch tempo,
  ) {
    var struct = base.structuralMatch;
    final outLabel = outSec?.label;
    final inLabel = inSec?.label;
    final inIsInstrumentalEntry =
        inLabel == SectionLabel.intro || (inSec?.isInstrumental ?? false);

    switch (type) {
      case TransitionType.clubMix:
        // shines on a tight tempo match
        struct *= 0.7 + 0.3 * tempo.score;
        if (tempo.score < 0.4) struct *= 0.7;
      case TransitionType.harmonicMix:
        struct *= 0.6 + 0.4 * base.keyMatch;
      case TransitionType.instrumentalOverlay:
        if (out.outroSection?.isInstrumental ?? false) struct *= 1.15;
        if (inIsInstrumentalEntry) struct *= 1.05;
      case TransitionType.breakdown:
        // A breakdown strips the outgoing and SLAMS the next track in — that
        // reads as an abrupt cut on a casual auto-mix. Only let it compete
        // when the incoming genuinely has a drop to land on, and never favour
        // it outright.
        struct *= incoming.cuePoints.firstDropSec != null ? 1.0 : 0.55;
        if (outLabel == SectionLabel.outro) struct *= 0.85;
      case TransitionType.drumSwap:
      case TransitionType.bassSwap:
        struct *= 0.85 + 0.15 * tempo.score; // need beats locked
      case TransitionType.echoOut:
        // Dry-cuts the outgoing into an echo tail — usable on a mismatch, but
        // gentler styles are preferred, so a smaller boost than reverbTail.
        if (tempo.score < 0.5 || base.keyMatch < 0.5) struct *= 1.05;
      case TransitionType.reverbTail:
        // A graceful wash — great when key/tempo *don't* match well.
        if (tempo.score < 0.5 || base.keyMatch < 0.5) struct *= 1.2;
      case TransitionType.smoothBlend:
        struct *= 1.0; // the seamless default — competes fairly
      case TransitionType.aiSelected:
        break;
    }
    return TransitionScore(
      bpmMatch: base.bpmMatch,
      keyMatch: base.keyMatch,
      energyMatch: base.energyMatch,
      structuralMatch: struct.clamp(0.0, 1.0),
      stemCompatibility: base.stemCompatibility,
    );
  }
}

class _ScoredPlan {
  _ScoredPlan(this.plan);
  final TransitionPlan plan;
}
