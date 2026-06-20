import '../../data/models/lyric_line.dart';

/// Parses LRC-format synced lyrics, including this app's "enhanced LRC v2"
/// extensions emitted by `server/repair --only=align`:
///
/// * Word-level timestamps: `<mm:ss.xx>word`
/// * Per-line attribute block right after the line stamp: `{adlib}`,
///   `{spk=N}`, or `{adlib,spk=N}`. Speakers are inherited line-to-line
///   until overridden.
/// * Speaker-name map via the LRC standard `[ar:Name1,Name2]` tag —
///   `spk=0` → "Name1", `spk=1` → "Name2", etc.
///
/// Standard LRC features still supported:
/// * `[mm:ss.xx]` / `[mm:ss.xxx]` timestamps
/// * Multiple timestamps on one line (repeated choruses)
/// * `[offset:NNN]` global shift
/// * UTF-8 BOM stripping
/// * `;`-prefixed comments
class LrcParser {
  /// Returns a synced lyric list, sorted by time. Empty if no timestamped
  /// lines were found.
  static List<LyricLine> parse(String input) {
    if (input.isEmpty) return const [];
    final cleaned = input.startsWith('﻿') ? input.substring(1) : input;
    final rawLines = cleaned.split(RegExp(r'\r\n|\r|\n'));

    var offset = Duration.zero;
    final speakerNames = <String>[];
    final flatLines = <_RawLine>[];

    final stampPattern =
        RegExp(r'\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]');
    final wordTagPattern =
        RegExp(r'<(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?>');
    final attrBlockPattern = RegExp(r'^\{([^}]*)\}');

    int? lastSpeakerIdx;

    for (final raw in rawLines) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      if (line.startsWith(';')) continue;

      final offsetMatch = RegExp(r'^\[offset:\s*(-?\d+)\]$',
              caseSensitive: false)
          .firstMatch(line);
      if (offsetMatch != null) {
        offset = Duration(milliseconds: int.parse(offsetMatch.group(1)!));
        continue;
      }

      // [ar:Name1,Name2,...] → speaker name map. Standard "artist" tag
      // reused so the enhanced LRC stays single-file and vanilla parsers
      // see it as metadata to ignore.
      final arMatch = RegExp(r'^\[ar:\s*(.+?)\s*\]$', caseSensitive: false)
          .firstMatch(line);
      if (arMatch != null) {
        speakerNames
          ..clear()
          ..addAll(arMatch.group(1)!
              .split(',')
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty));
        continue;
      }

      // Other [alpha:...] metadata tags — skip.
      if (RegExp(r'^\[[a-zA-Z]{2,}:').hasMatch(line)) {
        continue;
      }

      final stamps = stampPattern.allMatches(line).toList();
      if (stamps.isEmpty) continue;

      var rest = line.substring(stamps.last.end);

      // Optional {attr,attr} block immediately after the last stamp.
      var isAdlib = false;
      int? speakerIdx;
      final attrMatch = attrBlockPattern.firstMatch(rest);
      if (attrMatch != null) {
        for (final tok
            in attrMatch.group(1)!.split(',').map((s) => s.trim())) {
          if (tok.isEmpty) continue;
          if (tok == 'adlib') {
            isAdlib = true;
          } else if (tok.startsWith('spk=')) {
            speakerIdx = int.tryParse(tok.substring(4));
          }
        }
        rest = rest.substring(attrMatch.end);
      }

      speakerIdx ??= lastSpeakerIdx;
      if (speakerIdx != null) lastSpeakerIdx = speakerIdx;

      // Word tags chunk `rest` into (time, word) pairs. The final tag with
      // no following word is the trailing end-of-line marker.
      final wordTags = wordTagPattern.allMatches(rest).toList();
      String plainText;
      var words = const <WordTiming>[];
      Duration? endTime;

      if (wordTags.isEmpty) {
        plainText = rest.trim();
      } else {
        final wt = <WordTiming>[];
        for (var i = 0; i < wordTags.length; i++) {
          final tag = wordTags[i];
          final tagEnd = tag.end;
          final nextStart =
              i + 1 < wordTags.length ? wordTags[i + 1].start : rest.length;
          final between = rest.substring(tagEnd, nextStart).trim();
          final t = _parseTime(tag.group(1)!, tag.group(2)!, tag.group(3));
          if (between.isEmpty) {
            if (i == wordTags.length - 1) endTime = t + offset;
          } else {
            wt.add(WordTiming(time: t + offset, text: between));
          }
        }
        words = wt;
        plainText = wt.map((w) => w.text).join(' ');
      }

      // Enhanced-LRC adlibs already carry literal parentheses in the source
      // text (e.g. `{adlib}(Straight up)`), and the renderer wraps adlib
      // text in parens again — so strip one surrounding pair here to keep
      // the model's "parens are added by the renderer, not stored" contract
      // and avoid rendering "((Straight up))".
      if (isAdlib &&
          plainText.length >= 2 &&
          plainText.startsWith('(') &&
          plainText.endsWith(')')) {
        plainText = plainText.substring(1, plainText.length - 1).trim();
      }

      for (final m in stamps) {
        final t = _parseTime(m.group(1)!, m.group(2)!, m.group(3)) + offset;
        flatLines.add(_RawLine(
          time: t.isNegative ? Duration.zero : t,
          text: plainText,
          words: words,
          endTime: endTime,
          speakerIdx: speakerIdx,
          isAdlib: isAdlib,
        ));
      }
    }

    flatLines.sort((a, b) => a.time.compareTo(b.time));

    final result = <LyricLine>[];
    for (var i = 0; i < flatLines.length; i++) {
      final raw = flatLines[i];
      // Non-final lines fall back to the next line's start. The FINAL line
      // is left null (not a fixed +5s) so the view resolves its end against
      // the real song duration — a fixed cap froze the karaoke sweep on long
      // outros and made the active-line gap-clear fire too early.
      final Duration? resolvedEnd = raw.endTime ??
          (i + 1 < flatLines.length ? flatLines[i + 1].time : null);
      final name = (raw.speakerIdx != null &&
              raw.speakerIdx! >= 0 &&
              raw.speakerIdx! < speakerNames.length)
          ? speakerNames[raw.speakerIdx!]
          : null;
      result.add(LyricLine(
        time: raw.time,
        text: raw.text,
        words: raw.words,
        endTime: resolvedEnd,
        speakerIndex: raw.speakerIdx,
        speakerName: name,
        isAdlib: raw.isAdlib,
      ));
    }
    return result;
  }

  static Duration _parseTime(String mm, String ss, String? frac) {
    final m = int.parse(mm);
    final s = int.parse(ss);
    var ms = 0;
    if (frac != null) {
      final padded = frac.padRight(3, '0').substring(0, 3);
      ms = int.parse(padded);
    }
    return Duration(minutes: m, seconds: s, milliseconds: ms);
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

class _RawLine {
  _RawLine({
    required this.time,
    required this.text,
    required this.words,
    required this.endTime,
    required this.speakerIdx,
    required this.isAdlib,
  });
  final Duration time;
  final String text;
  final List<WordTiming> words;
  final Duration? endTime;
  final int? speakerIdx;
  final bool isAdlib;
}
