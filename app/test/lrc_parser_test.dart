import 'package:flutter_test/flutter_test.dart';
import 'package:music_app/data/models/lyric_line.dart';
import 'package:music_app/features/lyrics/lrc_parser.dart';

void main() {
  group('LrcParser.parse', () {
    test('parses simple [mm:ss.xx] timestamps', () {
      const input = '''
[00:01.00]First line
[00:03.50]Second line
[00:10.20]Third line
''';
      final lines = LrcParser.parse(input);
      expect(lines, hasLength(3));
      expect(lines[0].time, const Duration(seconds: 1));
      expect(lines[0].text, 'First line');
      expect(lines[1].time,
          const Duration(seconds: 3, milliseconds: 500));
      expect(lines[2].time,
          const Duration(seconds: 10, milliseconds: 200));
    });

    test('handles three-digit milliseconds', () {
      const input = '[00:00.123]Hi';
      final lines = LrcParser.parse(input);
      expect(lines.single.time, const Duration(milliseconds: 123));
    });

    test('handles single-digit fractional', () {
      // [mm:ss.x] should be parsed as x*100 ms.
      const input = '[00:00.5]Hi';
      final lines = LrcParser.parse(input);
      expect(lines.single.time, const Duration(milliseconds: 500));
    });

    test('emits one line per timestamp on multi-stamp rows', () {
      const input = '[00:10.00][00:20.00][00:30.00]Repeated chorus';
      final lines = LrcParser.parse(input);
      expect(lines, hasLength(3));
      expect(
        lines.map((l) => l.time.inSeconds).toList(),
        [10, 20, 30],
      );
      expect(lines.every((l) => l.text == 'Repeated chorus'), isTrue);
    });

    test('strips UTF-8 BOM', () {
      const input = '﻿[00:01.00]Hi';
      final lines = LrcParser.parse(input);
      expect(lines.single.text, 'Hi');
    });

    test('skips metadata tags but applies offset', () {
      const input = '''
[ar:Some Artist]
[ti:Some Title]
[al:Some Album]
[offset:500]
[00:01.000]Shifted
''';
      final lines = LrcParser.parse(input);
      expect(lines, hasLength(1));
      expect(lines.single.time,
          const Duration(seconds: 1, milliseconds: 500));
    });

    test('negative offset clamps at zero', () {
      const input = '''
[offset:-5000]
[00:01.000]Way before
''';
      final lines = LrcParser.parse(input);
      expect(lines.single.time, Duration.zero);
    });

    test('skips comment lines and empty lines', () {
      const input = '''
; this is a comment
[00:01.00]Real line


''';
      final lines = LrcParser.parse(input);
      expect(lines, hasLength(1));
    });

    test('returns empty list for non-LRC content', () {
      const input = '''
Just a regular text file
with no timestamps at all
''';
      expect(LrcParser.parse(input), isEmpty);
    });

    test('sorts lines by time even when input is shuffled', () {
      const input = '''
[00:30.00]Three
[00:10.00]One
[00:20.00]Two
''';
      final lines = LrcParser.parse(input);
      expect(
        lines.map((l) => l.text).toList(),
        ['One', 'Two', 'Three'],
      );
    });

    test('preserves empty text lines (instrumental markers)', () {
      const input = '[00:01.00]\n[00:05.00]Lyrics start';
      final lines = LrcParser.parse(input);
      expect(lines, hasLength(2));
      expect(lines[0].text, '');
      expect(lines[1].text, 'Lyrics start');
    });

    test('handles minutes > 59 (long tracks)', () {
      const input = '[100:30.00]Very late';
      final lines = LrcParser.parse(input);
      expect(lines.single.time,
          const Duration(minutes: 100, seconds: 30));
    });

    test('returns empty list on empty input', () {
      expect(LrcParser.parse(''), isEmpty);
      expect(LrcParser.parse('   \n  \n'), isEmpty);
    });
  });

  group('LrcParser.activeIndex', () {
    final lines = <LyricLine>[
      const LyricLine(time: Duration(seconds: 1), text: 'A'),
      const LyricLine(time: Duration(seconds: 5), text: 'B'),
      const LyricLine(time: Duration(seconds: 10), text: 'C'),
    ];

    test('returns -1 before the first line', () {
      expect(LrcParser.activeIndex(lines, Duration.zero), -1);
    });

    test('returns the index of the latest line whose time <= position', () {
      expect(LrcParser.activeIndex(lines, const Duration(seconds: 1)), 0);
      expect(LrcParser.activeIndex(lines, const Duration(seconds: 4)), 0);
      expect(LrcParser.activeIndex(lines, const Duration(seconds: 5)), 1);
      expect(LrcParser.activeIndex(lines, const Duration(seconds: 9)), 1);
      expect(LrcParser.activeIndex(lines, const Duration(seconds: 10)), 2);
      expect(LrcParser.activeIndex(lines, const Duration(seconds: 999)), 2);
    });

    test('returns -1 on empty list', () {
      expect(LrcParser.activeIndex(const [], Duration.zero), -1);
    });
  });
}
