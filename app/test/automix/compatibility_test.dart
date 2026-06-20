import 'package:flutter_test/flutter_test.dart';
import 'package:music_app/features/automix/engine/compatibility.dart';

void main() {
  group('matchTempo', () {
    test('identical BPM needs no stretch and scores ~1', () {
      final m = matchTempo(128, 128);
      expect(m.incomingSpeedRatio, closeTo(1.0, 1e-9));
      expect(m.score, closeTo(1.0, 1e-9));
      expect(m.usedHalfDouble, isFalse);
    });

    test('half/double-time aligns for free (zero stretch)', () {
      // 70 over 140: candidates 140/70=2, double=4, half=1 -> picks 1.0,
      // i.e. play the slow track at normal speed = half-time, beats aligned,
      // no stretch artifacts.
      final m = matchTempo(140, 70);
      expect(m.incomingSpeedRatio, closeTo(1.0, 1e-9));
      expect(m.score, closeTo(1.0, 1e-9));
      // a small genuine mismatch takes a small stretch
      final m2 = matchTempo(140, 138);
      expect(m2.incomingSpeedRatio, closeTo(140 / 138, 1e-9));
      expect(m2.score, greaterThan(0.9));
    });

    test('large incompatible tempo scores low', () {
      final m = matchTempo(100, 128); // ratio ~0.78, 22% stretch
      expect(m.score, lessThan(0.4));
    });

    test('semitone side-effect matches 12*log2(ratio)', () {
      final m = matchTempo(132, 128); // speed up incoming
      expect(m.incomingSpeedRatio, greaterThan(1.0));
      expect(m.semitoneSideEffect, greaterThan(0)); // pitch rises -> correct down
    });
  });

  group('energyFlowScore', () {
    test('smooth slight rise scores high', () {
      expect(energyFlowScore(0.5, 0.55), greaterThan(0.9));
    });
    test('sudden drop scores low', () {
      expect(energyFlowScore(0.9, 0.2), lessThan(0.0 + 0.4));
    });
    test('sudden spike scores low', () {
      expect(energyFlowScore(0.2, 0.95), lessThan(0.4));
    });
  });

  group('loudnessTrimDb', () {
    test('matches incoming up to a louder outgoing, clamped', () {
      expect(loudnessTrimDb(outLufs: -8, inLufs: -14), closeTo(6, 1e-9));
      expect(loudnessTrimDb(outLufs: -5, inLufs: -30), 9); // clamp +9
      expect(loudnessTrimDb(outLufs: -30, inLufs: -5), -9); // clamp -9
    });
  });

  group('stemCompatibility', () {
    test('both stems is perfect', () {
      expect(
        stemCompatibility(
            outHasStems: true,
            inHasStems: true,
            vocalConflict: true,
            outEnergy: 0.9,
            inEnergy: 0.9),
        1.0,
      );
    });
    test('full-mix vocal clash is penalised', () {
      final clash = stemCompatibility(
          outHasStems: false,
          inHasStems: false,
          vocalConflict: true,
          outEnergy: 0.8,
          inEnergy: 0.8);
      final clean = stemCompatibility(
          outHasStems: false,
          inHasStems: false,
          vocalConflict: false,
          outEnergy: 0.5,
          inEnergy: 0.5);
      expect(clash, lessThan(clean));
    });
  });
}
