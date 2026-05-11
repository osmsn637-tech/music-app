import 'dart:io';

import 'lrc_parser.dart';

/// Snippets pulled out of a song's `.lrc` so the DJ can quote them in
/// commentary. Two flavors so the templates can pick whichever phrasing
/// reads more naturally:
///
///   - [firstLine]: first non-trivial timestamped lyric. The DJ uses this
///     to introduce a track ("kicks off with: '...'") — radio-DJ-style
///     "play the opening bar" energy.
///   - [hookLine]: the most-repeated line, normalized for casing /
///     punctuation. Usually the chorus opener. Used for tracks the user
///     is likely to recognize ("you know how it goes — '...'").
///
/// Either field is null when no plausible candidate exists (e.g., an
/// instrumental or a stub `.lrc` that's just one line). Callers MUST
/// gate lyric-quoting templates on the field being non-null.
///
/// [confidence] tells the DJ *how confident* we are that quoting will
/// land. The gate in the commentary engine reads this so it doesn't
/// quote a marginal hook the same way it'd quote a real chorus.
class LyricsHook {
  const LyricsHook({
    this.firstLine,
    this.hookLine,
    this.hookRepeatCount = 0,
    this.confidence = LyricHookConfidence.none,
  });

  final String? firstLine;
  final String? hookLine;

  /// How many times the chosen hook line repeats in the lyrics. 1 = it
  /// appeared once (so really just a "favorite line"), 3+ = a real chorus.
  /// Drives [confidence] but exposed separately for callers that want
  /// finer-grained gating.
  final int hookRepeatCount;

  /// How strong the hook is — set by the extractor based on repeat count
  /// and first-line richness. The commentary gate uses this together with
  /// context (favorite, discovery, etc.) to decide whether to quote.
  final LyricHookConfidence confidence;

  bool get hasFirstLine => firstLine != null && firstLine!.trim().isNotEmpty;
  bool get hasHook => hookLine != null && hookLine!.trim().isNotEmpty;
  bool get hasAny => hasFirstLine || hasHook;

  /// True when at least one snippet is available *and* the extractor
  /// thinks it's worth quoting (filters out junky one-word ad-libs that
  /// passed the per-line filter but don't read well in commentary).
  bool get isQuotable =>
      hasAny && confidence != LyricHookConfidence.none;

  static const empty = LyricsHook();
}

/// Coarse signal of how strong a hook is. Strong: a real recurring chorus
/// (3+ repeats). Medium: hook is a one-off but the first line is rich
/// enough to quote. Weak: nothing very quote-worthy. None: no usable text.
enum LyricHookConfidence { none, weak, medium, strong }

class LyricsHookExtractor {
  /// Reads the `.lrc` at [path] and returns a hook. Returns [LyricsHook.empty]
  /// when the file is missing, unreadable, or contains nothing usable.
  /// Tolerates plain-text `.lrc` files (un-synced) — uses raw lines when no
  /// timestamps are present.
  Future<LyricsHook> extract(String? path) async {
    if (path == null || path.isEmpty) return LyricsHook.empty;
    final file = File(path);
    if (!await file.exists()) return LyricsHook.empty;
    String content;
    try {
      content = await file.readAsString();
    } catch (_) {
      return LyricsHook.empty;
    }
    if (content.trim().isEmpty) return LyricsHook.empty;
    return _extractFromText(content);
  }

  /// Synchronous variant, useful for tests + unit-testable callers that
  /// already have the file body in memory.
  LyricsHook extractFromText(String content) => _extractFromText(content);

  // --- internals -------------------------------------------------------

  LyricsHook _extractFromText(String content) {
    final synced = LrcParser.parse(content);
    final candidates = synced.isNotEmpty
        ? synced.map((l) => l.text)
        : _splitPlainLines(content);

    final cleaned = candidates
        .map(_clean)
        .where(_isUsableLine)
        .toList(growable: false);
    if (cleaned.isEmpty) return LyricsHook.empty;

    final firstLine = cleaned.first;

    // Hook = most-repeated normalized line (case + punctuation insensitive).
    // Tie-break: longer original wins (more "lyric-y" than a one-word ad-lib).
    final counts = <String, int>{};
    final exemplars = <String, String>{};
    for (final line in cleaned) {
      final key = _normalizeForCount(line);
      if (key.isEmpty) continue;
      counts[key] = (counts[key] ?? 0) + 1;
      final existing = exemplars[key];
      if (existing == null || line.length > existing.length) {
        exemplars[key] = line;
      }
    }
    String? hook;
    var bestCount = 1;
    counts.forEach((key, n) {
      if (n > bestCount) {
        bestCount = n;
        hook = exemplars[key];
      }
    });

    final confidence = _scoreConfidence(
      firstLine: firstLine,
      hook: hook,
      repeatCount: bestCount,
    );

    return LyricsHook(
      firstLine: firstLine,
      hookLine: hook,
      hookRepeatCount: bestCount,
      confidence: confidence,
    );
  }

  /// Confidence is high when:
  ///   - The hook is a real chorus (≥ 3 repeats AND ≥ 4 words), OR
  ///   - The first line is long and rich enough to stand on its own.
  /// Medium when one of those holds partially. Weak otherwise. The DJ
  /// commentary gate uses this together with situational signals
  /// (favorite, discovery, etc.) to decide whether to actually quote.
  LyricHookConfidence _scoreConfidence({
    required String firstLine,
    required String? hook,
    required int repeatCount,
  }) {
    final firstWords = firstLine.split(RegExp(r'\s+')).length;
    final hookWords = hook == null ? 0 : hook.split(RegExp(r'\s+')).length;

    final hookIsStrong = hook != null && repeatCount >= 3 && hookWords >= 4;
    final hookIsMedium = hook != null && repeatCount >= 2 && hookWords >= 3;
    final firstIsRich = firstWords >= 5 && firstLine.length >= 18;
    final firstIsOk = firstWords >= 3 && firstLine.length >= 10;

    if (hookIsStrong || (firstIsRich && hookIsMedium)) {
      return LyricHookConfidence.strong;
    }
    if (hookIsMedium || firstIsRich) {
      return LyricHookConfidence.medium;
    }
    if (firstIsOk) {
      return LyricHookConfidence.weak;
    }
    return LyricHookConfidence.none;
  }

  Iterable<String> _splitPlainLines(String content) {
    return content
        .split(RegExp(r'\r\n|\r|\n'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty);
  }

  /// Strip `[Intro]` / `[Verse 1]` / `[Chorus: X]` markers, music note
  /// glyphs, and stray brackets. Trim outer punctuation so quotes read
  /// naturally inside the DJ's announcement.
  String _clean(String line) {
    var out = line.trim();
    out = out.replaceAll(RegExp(r'^\s*\[[^\]]*\]\s*'), '');
    out = out.replaceAll(RegExp(r'\s*\[[^\]]*\]\s*$'), '');
    out = out.replaceAll('♪', '').trim();
    // Strip wrapping quotes / parens so we can re-quote it ourselves.
    out = out.replaceFirst(RegExp(r'^["‘“(]'), '');
    out = out.replaceFirst(RegExp(r'["’”)]$'), '');
    return out.trim();
  }

  static const _filler = {
    'yeah', 'oh', 'uh', 'mm', 'mmm', 'hmm', 'ah', 'la',
    'ay', 'eh', 'ohhh', 'whoa', 'woo', 'yo', 'huh',
  };

  bool _isUsableLine(String s) {
    if (s.isEmpty) return false;
    if (s.length < 6) return false;
    // Reject section-marker fragments that survived the bracket strip.
    final lower = s.toLowerCase();
    if (lower.startsWith('intro') ||
        lower.startsWith('verse ') ||
        lower.startsWith('chorus') ||
        lower.startsWith('bridge') ||
        lower.startsWith('outro') ||
        lower.startsWith('hook')) {
      // Allow if the line contains real words after the marker —
      // some LRCs do `Chorus this is the line` without brackets.
      final rest = s.substring(s.indexOf(' ') + 1).trim();
      if (rest.isEmpty || rest.length < 6) return false;
    }
    final words = s.split(RegExp(r'\s+'));
    if (words.length < 3) return false;
    // Reject all-filler lines like "yeah yeah yeah".
    final realWords = words
        .map((w) => w.toLowerCase().replaceAll(RegExp(r'[^a-z]'), ''))
        .where((w) => w.isNotEmpty && !_filler.contains(w))
        .toList();
    if (realWords.length < 2) return false;
    return true;
  }

  String _normalizeForCount(String s) {
    return s
        .toLowerCase()
        .replaceAll(RegExp(r"[^a-z0-9 ]"), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}

/// Convenience: trims a hook to a quotable length without breaking words.
/// 70-char ceiling reads cleanly inside a longer DJ sentence.
String shortenForQuote(String line, {int maxChars = 70}) {
  final trimmed = line.trim();
  if (trimmed.length <= maxChars) return trimmed;
  final cut = trimmed.substring(0, maxChars);
  final lastSpace = cut.lastIndexOf(' ');
  return (lastSpace > maxChars * 0.6 ? cut.substring(0, lastSpace) : cut)
      .trimRight();
}
