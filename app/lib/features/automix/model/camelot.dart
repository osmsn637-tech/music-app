import 'automix_enums.dart';

/// Camelot Wheel harmonic-mixing logic (spec §4).
///
/// A Camelot code is a number 1–12 (position on the wheel) plus a ring
/// letter: `A` = minor, `B` = major. Harmonic compatibility follows the
/// DJ rules:
///   - same code                       → perfect
///   - ±1 same ring (adjacent hour)     → smooth (energy up/down)
///   - same number, other ring (relative major/minor) → smooth
///   - +7 / −7 ("energy boost", a perfect 5th) → usable, lifts energy
///   - two steps (±2)                   → only with a pitch nudge
/// Everything else is a clash.
class CamelotKey {
  const CamelotKey(this.number, this.isMinor);

  /// 1–12 hour on the wheel.
  final int number;

  /// true = minor (`A` ring), false = major (`B` ring).
  final bool isMinor;

  String get code => '$number${isMinor ? 'A' : 'B'}';

  static CamelotKey? parse(String? raw) {
    if (raw == null) return null;
    final m = RegExp(r'^\s*(\d{1,2})\s*([ABab])\s*$').firstMatch(raw);
    if (m == null) return null;
    final n = int.parse(m.group(1)!);
    if (n < 1 || n > 12) return null;
    return CamelotKey(n, m.group(2)!.toUpperCase() == 'A');
  }

  /// Shortest distance around the 12-hour wheel (0..6).
  int _hourDistance(CamelotKey other) {
    final d = (number - other.number).abs() % 12;
    return d > 6 ? 12 - d : d;
  }

  /// Harmonic compatibility in 0..1 with [other]. Used directly as the
  /// "Key Match" term in the transition score (§12).
  double compatibility(CamelotKey other) {
    if (number == other.number && isMinor == other.isMinor) return 1.0;

    final hour = _hourDistance(other);
    final sameRing = isMinor == other.isMinor;

    // relative major/minor: same hour number, opposite ring
    if (number == other.number && !sameRing) return 0.9;

    // ±1 hour on the wheel *is* the perfect fifth (the Camelot wheel is the
    // circle of fifths) — the classic energy-up/down neighbour.
    if (sameRing && hour == 1) return 0.85;
    if (!sameRing && hour == 1) return 0.55; // diagonal — workable
    if (sameRing && hour == 2) return 0.5; // two steps — needs a pitch nudge
    if (!sameRing && hour == 2) return 0.35;
    return 0.15; // clash
  }

  /// Whether a blend is harmonically safe without pitch correction.
  bool isCompatibleWith(CamelotKey other) => compatibility(other) >= 0.6;

  /// Best pitch shift in semitones (−2..+2) to *improve* compatibility with
  /// [target], or 0 if already compatible / no helpful shift inside range.
  /// One Camelot hour ≈ a perfect-5th move; one chromatic semitone advances
  /// 7 hours around the wheel (circle of fifths), so we search small
  /// semitone offsets and keep the one that lands closest.
  int bestSemitoneShiftTo(CamelotKey target) {
    if (compatibility(target) >= 0.85) return 0;
    var best = 0;
    var bestScore = compatibility(target);
    for (final s in const [-2, -1, 1, 2]) {
      final shifted = transposedBySemitones(s);
      final score = shifted.compatibility(target);
      if (score > bestScore + 0.05) {
        bestScore = score;
        best = s;
      }
    }
    return best;
  }

  /// This key transposed by [semitones] (wheel moves 7 hours per semitone).
  CamelotKey transposedBySemitones(int semitones) {
    var n = ((number - 1 + 7 * semitones) % 12);
    if (n < 0) n += 12;
    return CamelotKey(n + 1, isMinor);
  }

  @override
  String toString() => code;
}

/// Convenience: derive a [CamelotKey] from tonic + mode (e.g. when only the
/// musical key, not the Camelot code, is available).
CamelotKey? camelotFromKey(String tonic, KeyMode mode) {
  const order = {
    'C': 0, 'C#': 1, 'DB': 1, 'D': 2, 'D#': 3, 'EB': 3, 'E': 4,
    'F': 5, 'F#': 6, 'GB': 6, 'G': 7, 'G#': 8, 'AB': 8, 'A': 9,
    'A#': 10, 'BB': 10, 'B': 11,
  };
  final pc = order[tonic.toUpperCase()];
  if (pc == null) return null;
  // map pitch-class+mode to wheel number using the canonical assignment
  const majorWheel = {
    0: 8, 7: 9, 2: 10, 9: 11, 4: 12, 11: 1, 6: 2, 1: 3, 8: 4, 3: 5, 10: 6, 5: 7,
  };
  const minorWheel = {
    9: 8, 4: 9, 11: 10, 6: 11, 1: 12, 8: 1, 3: 2, 10: 3, 5: 4, 0: 5, 7: 6, 2: 7,
  };
  final n = mode == KeyMode.major ? majorWheel[pc] : minorWheel[pc];
  if (n == null) return null;
  return CamelotKey(n, mode == KeyMode.minor);
}
