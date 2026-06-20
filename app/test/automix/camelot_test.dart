import 'package:flutter_test/flutter_test.dart';
import 'package:music_app/features/automix/model/camelot.dart';

void main() {
  group('CamelotKey.parse', () {
    test('parses valid codes', () {
      expect(CamelotKey.parse('8A')?.code, '8A');
      expect(CamelotKey.parse('12B')?.code, '12B');
      expect(CamelotKey.parse(' 1a ')?.code, '1A');
    });
    test('rejects junk', () {
      expect(CamelotKey.parse('13A'), isNull);
      expect(CamelotKey.parse('0B'), isNull);
      expect(CamelotKey.parse('AA'), isNull);
      expect(CamelotKey.parse(null), isNull);
    });
  });

  group('compatibility', () {
    final k8a = CamelotKey.parse('8A')!;
    test('same key is perfect', () {
      expect(k8a.compatibility(CamelotKey.parse('8A')!), 1.0);
    });
    test('relative major (8A<->8B) is high', () {
      expect(k8a.compatibility(CamelotKey.parse('8B')!), greaterThan(0.85));
    });
    test('adjacent same ring (8A<->9A / 7A) is high', () {
      expect(k8a.compatibility(CamelotKey.parse('9A')!), greaterThanOrEqualTo(0.8));
      expect(k8a.compatibility(CamelotKey.parse('7A')!), greaterThanOrEqualTo(0.8));
    });
    test('two-step jump (8A<->10A) is moderate, needs a nudge', () {
      expect(k8a.compatibility(CamelotKey.parse('10A')!), inInclusiveRange(0.4, 0.6));
    });
    test('distant key (8A<->3A, 5 hours) is a clash', () {
      expect(k8a.compatibility(CamelotKey.parse('3A')!), lessThan(0.4));
    });
    test('clashing key (8A<->2B) is low', () {
      expect(k8a.compatibility(CamelotKey.parse('2B')!), lessThan(0.4));
    });
    test('compatibility is symmetric', () {
      for (final code in ['1A', '5B', '11A', '7B']) {
        final other = CamelotKey.parse(code)!;
        expect(k8a.compatibility(other),
            closeTo(other.compatibility(k8a), 1e-9));
      }
    });
  });

  group('semitone transpose around the wheel', () {
    test('+1 semitone advances 7 hours (circle of fifths)', () {
      final k = CamelotKey.parse('1A')!; // hour 1
      expect(k.transposedBySemitones(1).number, 8); // 1 + 7 = 8
      expect(k.transposedBySemitones(1).isMinor, isTrue);
    });
    test('bestSemitoneShift stays within +-2 and only helps', () {
      final from = CamelotKey.parse('5A')!;
      final to = CamelotKey.parse('2B')!; // a clash
      final shift = from.bestSemitoneShiftTo(to);
      expect(shift, inInclusiveRange(-2, 2));
      if (shift != 0) {
        expect(from.transposedBySemitones(shift).compatibility(to),
            greaterThan(from.compatibility(to)));
      }
    });
  });
}
