/// One sung word inside a [LyricLine], with its start time inside the song.
/// Sourced from the server's forced-alignment pass (WhisperX over the demucs
/// vocal stem). When word timings aren't available the [LyricLine.words]
/// list is empty and the renderer falls back to whole-line highlighting.
class WordTiming {
  const WordTiming({required this.time, required this.text});

  final Duration time;
  final String text;
}

class LyricLine {
  const LyricLine({
    required this.time,
    required this.text,
    this.words = const [],
    this.endTime,
    this.speakerIndex,
    this.speakerName,
    this.isAdlib = false,
  });

  /// Line start time.
  final Duration time;

  /// Plain-text rendering of the line. For adlibs the parens are added by
  /// the renderer, NOT stored here.
  final String text;

  /// Word-level timings, empty when alignment wasn't done.
  final List<WordTiming> words;

  /// End-of-line time. Comes from the trailing `<mm:ss.xx>` tag in
  /// enhanced LRC; falls back to the next line's start at parse time.
  final Duration? endTime;

  /// Speaker index from diarization. null if not diarized.
  final int? speakerIndex;

  /// Human-readable speaker name resolved via `[ar:name1,name2]`.
  /// null if no name map / index out of range.
  final String? speakerName;

  /// True if the line was tagged `{adlib}` — render smaller, parenthesized,
  /// dim.
  final bool isAdlib;

  bool get hasWordTimings => words.isNotEmpty;
}
