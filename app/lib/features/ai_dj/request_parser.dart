/// Parses a free-text DJ request into structured filters / scoring
/// overlays. Strictly offline — keyword + regex over a controlled
/// vocabulary. Good enough for one user's phrasings; will miss things
/// outside the vocab. The screen surfaces what the parser caught as
/// pill chips so silent misparses are visible to the user.
class IntRange {
  const IntRange(this.min, this.max);
  final int min;
  final int max;
  bool contains(int v) => v >= min && v <= max;
}

class RequestIntent {
  RequestIntent({
    Set<String>? moods,
    this.bpm,
    this.instrumentalOnly,
    Set<String>? excludeArtists,
    Set<String>? requireGenres,
    Set<String>? excludeGenres,
    this.discover,
  })  : moods = moods ?? <String>{},
        excludeArtists = excludeArtists ?? <String>{},
        requireGenres = requireGenres ?? <String>{},
        excludeGenres = excludeGenres ?? <String>{};

  final Set<String> moods;
  final IntRange? bpm;
  final bool? instrumentalOnly;
  final Set<String> excludeArtists;
  final Set<String> requireGenres;
  final Set<String> excludeGenres;
  final bool? discover;

  bool get isEmpty =>
      moods.isEmpty &&
      bpm == null &&
      instrumentalOnly != true &&
      excludeArtists.isEmpty &&
      requireGenres.isEmpty &&
      excludeGenres.isEmpty &&
      discover != true;

  /// Short human-facing summary like "chill • 82-98 bpm • no vocals".
  /// Returned as a list of chip-friendly fragments so the UI can render
  /// each as a separate pill.
  List<String> describe() {
    final parts = <String>[];
    for (final m in moods) {
      parts.add(m);
    }
    if (bpm != null) parts.add('${bpm!.min}-${bpm!.max} bpm');
    if (instrumentalOnly == true) parts.add('no vocals');
    for (final g in requireGenres) {
      parts.add(g);
    }
    for (final g in excludeGenres) {
      parts.add('no $g');
    }
    for (final a in excludeArtists) {
      parts.add('no $a');
    }
    if (discover == true) parts.add('new only');
    return parts;
  }
}

class RequestParser {
  const RequestParser();

  static const _negations = {'no', 'not', "don't", 'without', 'except', 'minus'};

  static const _moodSynonyms = <String, String>{
    'chill': 'chill',
    'mellow': 'chill',
    'relaxed': 'chill',
    'lo-fi': 'lofi',
    'lofi': 'lofi',
    'lo': 'lofi',
    'calm': 'calm',
    'study': 'study',
    'focus': 'study',
    'focused': 'study',
    'instrumental': 'instrumental',
    'ambient': 'ambient',
    'energetic': 'energetic',
    'energy': 'energetic',
    'hype': 'energetic',
    'pumped': 'energetic',
    'workout': 'workout',
    'gym': 'workout',
    'party': 'party',
    'sleep': 'sleep',
    'sleepy': 'sleep',
    'night': 'night',
    'late': 'night',
  };

  static const _genres = {
    'rock',
    'pop',
    'jazz',
    'classical',
    'electronic',
    'edm',
    'rap',
    'hiphop',
    'hip-hop',
    'country',
    'folk',
    'r&b',
    'rnb',
    'soul',
    'blues',
    'metal',
    'punk',
    'reggae',
    'house',
    'techno',
    'trance',
    'dubstep',
    'indie',
    'alternative',
  };

  static const _instrumentalTriggers = {
    'instrumental',
    'wordless',
    'lyricless',
  };

  /// Multi-word phrases that imply instrumentalOnly when negated:
  /// "no vocals", "without vocals", "no lyrics", "without lyrics".
  static const _vocalTokens = {'vocals', 'vocal', 'lyrics', 'singing'};

  static const _discoverTokens = {'new', 'unheard', 'discover', 'fresh'};

  static const _slowSynonyms = {'slow', 'slower'};
  static const _fastSynonyms = {'fast', 'faster', 'quick', 'energetic'};
  static const _midSynonyms = {'medium', 'mid', 'moderate'};

  RequestIntent parse(String prompt) {
    final lowered = prompt.toLowerCase().trim();
    if (lowered.isEmpty) return RequestIntent();

    // Pull out any "<n> bpm" / "around <n> bpm" / "<n>-<m> bpm" phrases
    // first; remove them so the rest of the parser doesn't re-tokenize the
    // numerals as artist names or whatever.
    var working = lowered;
    IntRange? bpm;

    final bpmRange = RegExp(r'(\d{2,3})\s*(?:-|to)\s*(\d{2,3})\s*bpm');
    final rangeMatch = bpmRange.firstMatch(working);
    if (rangeMatch != null) {
      final lo = int.parse(rangeMatch.group(1)!);
      final hi = int.parse(rangeMatch.group(2)!);
      bpm = IntRange(lo < hi ? lo : hi, lo < hi ? hi : lo);
      working = working.replaceFirst(bpmRange, ' ');
    } else {
      final bpmSingle = RegExp(
        r'(?:around\s+|about\s+|near\s+|at\s+|~)?(\d{2,3})\s*bpm',
      );
      final m = bpmSingle.firstMatch(working);
      if (m != null) {
        final n = int.parse(m.group(1)!);
        bpm = IntRange(n - 8, n + 8);
        working = working.replaceFirst(bpmSingle, ' ');
      }
    }

    final tokens = working
        .split(RegExp(r'[\s,;.!?()/]+'))
        .where((t) => t.isNotEmpty)
        .toList();

    final moods = <String>{};
    final excludeArtists = <String>{};
    final requireGenres = <String>{};
    final excludeGenres = <String>{};
    bool? instrumentalOnly;
    bool? discover;

    var negate = false;
    for (final tok in tokens) {
      if (_negations.contains(tok)) {
        negate = true;
        continue;
      }

      // Vocal markers ("vocals", "lyrics") — negation flips to "no vocals"
      // = instrumentalOnly. A bare "vocals" token without negation is
      // ambiguous and we ignore it.
      if (_vocalTokens.contains(tok)) {
        if (negate) instrumentalOnly = true;
        negate = false;
        continue;
      }

      if (_instrumentalTriggers.contains(tok)) {
        instrumentalOnly = true;
        negate = false;
        continue;
      }

      if (_discoverTokens.contains(tok)) {
        discover = !negate;
        negate = false;
        continue;
      }

      if (_slowSynonyms.contains(tok) && bpm == null) {
        bpm = const IntRange(40, 80);
        negate = false;
        continue;
      }
      if (_fastSynonyms.contains(tok) && bpm == null) {
        bpm = const IntRange(120, 200);
        negate = false;
        continue;
      }
      if (_midSynonyms.contains(tok) && bpm == null) {
        bpm = const IntRange(80, 120);
        negate = false;
        continue;
      }

      if (_moodSynonyms.containsKey(tok)) {
        if (!negate) moods.add(_moodSynonyms[tok]!);
        // "no chill" simply doesn't add it; we don't model excluded moods.
        negate = false;
        continue;
      }

      if (_genres.contains(tok)) {
        if (negate) {
          excludeGenres.add(tok);
        } else {
          requireGenres.add(tok);
        }
        negate = false;
        continue;
      }

      // Unknown token under negation → assume artist name to exclude.
      if (negate && tok.length >= 2) {
        excludeArtists.add(tok);
        negate = false;
        continue;
      }

      // Unmatched non-negated token: ignore. The user can see it didn't
      // register because the chip row won't include it.
      negate = false;
    }

    return RequestIntent(
      moods: moods,
      bpm: bpm,
      instrumentalOnly: instrumentalOnly,
      excludeArtists: excludeArtists,
      requireGenres: requireGenres,
      excludeGenres: excludeGenres,
      discover: discover,
    );
  }
}
