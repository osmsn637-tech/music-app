import '../../data/models/lyric_line.dart';

/// Parses LRC-format synced lyrics.
///
/// Supports:
/// - `[mm:ss.xx]` and `[mm:ss.xxx]` timestamps
/// - Multiple timestamps on one line (e.g. repeated chorus)
/// - `[offset:NNN]` metadata to globally shift times (positive = lyrics
///   appear later)
/// - UTF-8 BOM stripping
/// - Comments starting with `;`
/// - Empty / metadata-only lines (skipped, except `offset`)
class LrcParser {
  /// Returns a synced lyric list, sorted by time. Returns an empty list if
  /// no timestamped lines were found.
  static List<LyricLine> parse(String input) {
    if (input.isEmpty) return const [];
    // Strip UTF-8 BOM if present.
    final cleaned = input.startsWith('﻿') ? input.substring(1) : input;
    final lines = cleaned.split(RegExp(r'\r\n|\r|\n'));

    var offset = Duration.zero;
    final result = <LyricLine>[];
    final stampPattern =
        RegExp(r'\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]');

    for (final raw in lines) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      if (line.startsWith(';')) continue;

      // Pull out [offset:NNN] metadata before treating brackets as timestamps.
      final offsetMatch = RegExp(r'^\[offset:\s*(-?\d+)\]$',
              caseSensitive: false)
          .firstMatch(line);
      if (offsetMatch != null) {
        offset = Duration(milliseconds: int.parse(offsetMatch.group(1)!));
        continue;
      }

      // Skip pure metadata tags: [ar:...], [ti:...], [al:...], [by:...],
      // [length:...], [re:...], [ve:...]. These have alpha keys, not digits.
      if (RegExp(r'^\[[a-zA-Z]{2,}:').hasMatch(line)) {
        continue;
      }

      final stamps = stampPattern.allMatches(line).toList();
      if (stamps.isEmpty) continue;

      final lastEnd = stamps.last.end;
      final text = line.substring(lastEnd).trim();

      for (final m in stamps) {
        final mm = int.parse(m.group(1)!);
        final ss = int.parse(m.group(2)!);
        final fracStr = m.group(3);
        var ms = 0;
        if (fracStr != null) {
          // [mm:ss.xx]   → xx * 10
          // [mm:ss.xxx]  → xxx
          // [mm:ss.x]    → x * 100
          final padded = fracStr.padRight(3, '0').substring(0, 3);
          ms = int.parse(padded);
        }
        final time = Duration(minutes: mm, seconds: ss, milliseconds: ms) +
            offset;
        result.add(
          LyricLine(
            time: time.isNegative ? Duration.zero : time,
            text: text,
          ),
        );
      }
    }

    result.sort((a, b) => a.time.compareTo(b.time));
    return result;
  }

  /// Returns the index of the latest line whose `time <= position`, or -1 if
  /// the position is before the first line. Binary search, O(log n).
  static int activeIndex(List<LyricLine> lines, Duration position) {
    if (lines.isEmpty) return -1;
    var lo = 0;
    var hi = lines.length - 1;
    var answer = -1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (lines[mid].time <= position) {
        answer = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return answer;
  }
}

