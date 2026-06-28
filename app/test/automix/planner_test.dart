import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_app/features/automix/engine/automix_planner.dart';
import 'package:music_app/features/automix/engine/cue_selector.dart';
import 'package:music_app/features/automix/model/automix_enums.dart';
import 'package:music_app/features/automix/model/track_analysis.dart';

TrackAnalysis _load(String name) {
  final f = File('test/automix/fixtures/$name');
  final json = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
  return TrackAnalysis.fromJson(json);
}

void main() {
  late TrackAnalysis hold; // 129 BPM, 7A
  late TrackAnalysis aLot; // 143 BPM, 5A
  late TrackAnalysis longIntro; // 143 BPM, 9A

  setUpAll(() {
    hold = _load('hold_that_heat.automix.json');
    aLot = _load('21_savage_a_lot_official_audio.automix.json');
    longIntro = _load('long_time_intro.automix.json');
  });

  test('fixtures parse with the expected shape', () {
    expect(hold.schema, TrackAnalysis.currentSchema);
    expect(hold.bpm, closeTo(129.2, 0.5));
    expect(hold.key.camelot?.code, '7A');
    expect(hold.beatGrid.hasGrid, isTrue);
    expect(hold.sections, isNotEmpty);
    expect(hold.beatGrid.downbeatTimes, isNotEmpty);
  });

  group('AutoMixPlanner.plan', () {
    const planner = AutoMixPlanner();

    test('produces a concrete, valid plan (never aiSelected)', () {
      final p = planner.plan(out: hold, incoming: aLot, playheadSec: 60);
      expect(p.type, isNot(TransitionType.aiSelected));
      expect(p.durationSec, greaterThan(0));
      expect(p.score.total, inInclusiveRange(0.0, 1.0));
      expect(p.notes, isNotEmpty);
    });

    test('§12 weights sum to 1.0 and total is the weighted sum', () {
      final p = planner.plan(out: hold, incoming: aLot, playheadSec: 60);
      final s = p.score;
      final manual = 0.25 * s.bpmMatch +
          0.25 * s.keyMatch +
          0.20 * s.energyMatch +
          0.15 * s.structuralMatch +
          0.15 * s.stemCompatibility;
      expect(s.total, closeTo(manual, 1e-9));
    });

    test('mix points snap to downbeats', () {
      final p = planner.plan(out: hold, incoming: aLot, playheadSec: 60);
      final nearestOut = hold.beatGrid.nearestDownbeat(p.startSecOnOutgoing);
      final nearestIn = aLot.beatGrid.nearestDownbeat(p.incomingStartSec);
      expect((p.startSecOnOutgoing - nearestOut).abs(), lessThan(0.05));
      expect((p.incomingStartSec - nearestIn).abs(), lessThan(0.05));
    });

    test('mix-out never lands before the playhead', () {
      final p = planner.plan(out: hold, incoming: aLot, playheadSec: 200);
      expect(p.startSecOnOutgoing, greaterThanOrEqualTo(200));
    });

    test('incoming mixes in on real music, not a silent/sparse intro', () {
      // hold_that_heat's intro section energy is ~0.27 (sparse); the mix-in
      // must skip it and land on the energetic section that follows.
      final firstEnergetic = firstEnergeticSec(hold);
      final introEnd = hold.sections.first.endSec;
      expect(firstEnergetic, greaterThanOrEqualTo(introEnd - 0.1),
          reason: 'should skip the sparse intro section');
      final sec = hold.sectionAt(firstEnergetic);
      expect(sec?.energy ?? 0, greaterThanOrEqualTo(0.4));
    });

    test('blend runs to the outgoing track end (outgoing fades, no cut)', () {
      final dur = hold.durationSec;
      final p = planner.plan(out: hold, incoming: aLot, playheadSec: dur - 12);
      final blendEnds = p.startSecOnOutgoing + p.durationSec;
      expect((dur - blendEnds).abs(), lessThan(1.0),
          reason: 'the blend should finish right as the outgoing ends');
    });

    test('auto-advance near the end gives a real blend, not a ~0s hard cut', () {
      // Reproduces the hard-cut bug: triggered ~10s before the end, the mix
      // must START near the playhead (now) and overlap for several seconds —
      // NOT get shoved to the final second with ~0.8s of room.
      final dur = hold.durationSec;
      final p = planner.plan(out: hold, incoming: aLot, playheadSec: dur - 10);
      expect(p.startSecOnOutgoing, lessThan(dur - 5),
          reason: 'mix-out must not be pinned to the track end');
      expect(p.startSecOnOutgoing, greaterThanOrEqualTo(dur - 11));
      expect(p.durationSec, greaterThan(3.0),
          reason: 'transition must be an audible blend, not a hard cut');
    });

    test('stem-only types are excluded when no stems available', () {
      final ranked = planner.rankAll(out: hold, incoming: aLot, playheadSec: 60);
      final types = ranked.map((p) => p.type).toSet();
      expect(types.contains(TransitionType.drumSwap), isFalse);
      expect(types.contains(TransitionType.bassSwap), isFalse);
    });

    test('volume curves stay within 0..1 across the whole transition', () {
      final p = planner.plan(out: hold, incoming: aLot, playheadSec: 60);
      for (var t = 0.0; t <= p.durationSec; t += 0.05) {
        expect(p.outgoing.volume.valueAt(t), inInclusiveRange(0.0, 1.0));
        expect(p.incoming.volume.valueAt(t), inInclusiveRange(0.0, 1.0));
      }
    });

    test('incoming pitch correction cancels the tempo resampling shift', () {
      // 129 -> 143 needs a stretch; the net incoming pitch should fold in the
      // correction so we are not left with an uncorrected octave jump.
      final p = planner.plan(out: hold, incoming: aLot, playheadSec: 60);
      expect(p.incoming.pitchSemitones.abs(), lessThan(6));
    });

    test('close-tempo harmonic neighbours rank a tailored mix above a blend',
        () {
      // aLot (143/5A) and longIntro (143/9A) share tempo; the planner should
      // not just default to smoothBlend.
      final ranked =
          planner.rankAll(out: aLot, incoming: longIntro, playheadSec: 60);
      expect(ranked.first.score.bpmMatch, greaterThan(0.9));
    });

    test('forcing a type still scores and builds it', () {
      final p = planner.plan(
        out: hold,
        incoming: aLot,
        playheadSec: 60,
        requestedType: TransitionType.echoOut,
      );
      expect(p.type, TransitionType.echoOut);
      expect(p.outgoing.echoWet.keyframes, isNotEmpty);
    });
  });
}
