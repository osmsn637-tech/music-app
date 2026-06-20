import 'automix_enums.dart';
import 'camelot.dart';

/// Dart mirror of one `*.automix.json` sidecar produced by
/// `tools/automix/analyze.py`. Field names map to the snake_case JSON keys.
/// Keep this in lock-step with the Python `TrackAnalysis` dataclass — the
/// `schema` int guards against silent drift.
class TrackAnalysis {
  const TrackAnalysis({
    required this.schema,
    required this.file,
    required this.durationSec,
    required this.sampleRate,
    required this.bpm,
    required this.bpmConfidence,
    required this.beatGrid,
    required this.key,
    required this.lufs,
    required this.sections,
    required this.cuePoints,
    required this.vocalSource,
    required this.stems,
  });

  static const int currentSchema = 1;

  final int schema;
  final String file; // original audio basename — the join key to SongRow
  final double durationSec;
  final int sampleRate;
  final double bpm;
  final double bpmConfidence;
  final BeatGrid beatGrid;
  final MusicalKey key;
  final double lufs;
  final List<Section> sections;
  final CuePoints cuePoints;
  final String vocalSource; // 'stems' | 'proxy'
  final StemSet stems;

  bool get vocalRatioIsAccurate => vocalSource == 'stems';

  factory TrackAnalysis.fromJson(Map<String, dynamic> j) {
    return TrackAnalysis(
      schema: (j['schema'] as num?)?.toInt() ?? 0,
      file: j['file'] as String? ?? '',
      durationSec: _d(j['duration_sec']),
      sampleRate: (j['sample_rate'] as num?)?.toInt() ?? 44100,
      bpm: _d(j['bpm']),
      bpmConfidence: _d(j['bpm_confidence']),
      beatGrid: BeatGrid.fromJson(j['beat_grid'] as Map<String, dynamic>),
      key: MusicalKey.fromJson(j['key'] as Map<String, dynamic>),
      lufs: _d(j['lufs'], fallback: -14),
      sections: ((j['sections'] as List?) ?? [])
          .map((e) => Section.fromJson(e as Map<String, dynamic>))
          .toList(),
      cuePoints: CuePoints.fromJson(j['cue_points'] as Map<String, dynamic>),
      vocalSource: j['vocal_source'] as String? ?? 'proxy',
      stems: StemSet.fromJson(
          (j['stems'] as Map<String, dynamic>?) ?? const {}),
    );
  }

  /// The section containing [sec], or null.
  Section? sectionAt(double sec) {
    for (final s in sections) {
      if (sec >= s.startSec && sec < s.endSec) return s;
    }
    return sections.isNotEmpty && sec >= sections.last.endSec
        ? sections.last
        : null;
  }

  Section? get introSection =>
      sections.isEmpty ? null : sections.first;
  Section? get outroSection => sections.isEmpty ? null : sections.last;

  /// Lowest-vocal section in the back half — the natural place to mix *out*
  /// of (so the incoming track isn't fighting a lead vocal).
  Section? get mostInstrumentalOutroSide {
    if (sections.isEmpty) return null;
    final back = sections
        .where((s) => s.startSec >= durationSec * 0.5)
        .toList();
    final pool = back.isEmpty ? sections : back;
    pool.sort((a, b) => a.vocalRatio.compareTo(b.vocalRatio));
    return pool.first;
  }

  /// Approximate instantaneous energy at [sec] (section energy).
  double energyAt(double sec) => sectionAt(sec)?.energy ?? 0.5;

  /// Approximate vocal presence at [sec] in 0..1.
  double vocalRatioAt(double sec) => sectionAt(sec)?.vocalRatio ?? 0.5;
}

class BeatGrid {
  const BeatGrid({
    required this.firstBeatSec,
    required this.beatsPerBar,
    required this.beatTimes,
    required this.downbeatTimes,
  });

  final double firstBeatSec;
  final int beatsPerBar;
  final List<double> beatTimes;
  final List<double> downbeatTimes;

  factory BeatGrid.fromJson(Map<String, dynamic> j) => BeatGrid(
        firstBeatSec: _d(j['first_beat_sec']),
        beatsPerBar: (j['beats_per_bar'] as num?)?.toInt() ?? 4,
        beatTimes: _dl(j['beat_times']),
        downbeatTimes: _dl(j['downbeat_times']),
      );

  bool get hasGrid => beatTimes.length >= 2;

  /// Median beat period (seconds). Robust to the odd dropped/extra beat.
  double get beatPeriodSec {
    if (beatTimes.length < 2) return 0.5;
    final diffs = <double>[];
    for (var i = 1; i < beatTimes.length; i++) {
      final dd = beatTimes[i] - beatTimes[i - 1];
      if (dd > 0.1 && dd < 2.0) diffs.add(dd);
    }
    if (diffs.isEmpty) return 0.5;
    diffs.sort();
    return diffs[diffs.length ~/ 2];
  }

  /// Nearest downbeat to [t] (falls back to nearest beat, then [t]).
  double nearestDownbeat(double t) {
    final pool = downbeatTimes.isNotEmpty ? downbeatTimes : beatTimes;
    if (pool.isEmpty) return t;
    var best = pool.first;
    var bestD = (pool.first - t).abs();
    for (final d in pool) {
      final dd = (d - t).abs();
      if (dd < bestD) {
        bestD = dd;
        best = d;
      }
    }
    return best;
  }

  /// First downbeat at or after [t] — used to align a mix-in to the bar.
  double nextDownbeatAtOrAfter(double t) {
    for (final d in downbeatTimes) {
      if (d >= t - 1e-3) return d;
    }
    return downbeatTimes.isNotEmpty ? downbeatTimes.last : t;
  }
}

class MusicalKey {
  const MusicalKey({
    required this.tonic,
    required this.mode,
    required this.camelotCode,
    required this.confidence,
  });

  final String tonic; // "A", "C#"
  final KeyMode mode;
  final String camelotCode; // "8A"
  final double confidence;

  CamelotKey? get camelot =>
      CamelotKey.parse(camelotCode) ?? camelotFromKey(tonic, mode);

  String get display => '$tonic${mode == KeyMode.minor ? 'm' : ''}';

  factory MusicalKey.fromJson(Map<String, dynamic> j) => MusicalKey(
        tonic: j['tonic'] as String? ?? 'C',
        mode: (j['mode'] as String? ?? 'major') == 'minor'
            ? KeyMode.minor
            : KeyMode.major,
        camelotCode: j['camelot'] as String? ?? '',
        confidence: _d(j['confidence']),
      );
}

class Section {
  const Section({
    required this.label,
    required this.startSec,
    required this.endSec,
    required this.energy,
    required this.vocalRatio,
  });

  final SectionLabel label;
  final double startSec;
  final double endSec;
  final double energy; // 0..1 relative to track peak
  final double vocalRatio; // 0..1

  double get durationSec => endSec - startSec;
  bool get isVocalHeavy => vocalRatio >= 0.6;
  bool get isInstrumental => vocalRatio <= 0.35;

  factory Section.fromJson(Map<String, dynamic> j) => Section(
        label: SectionLabel.parse(j['label'] as String?),
        startSec: _d(j['start_sec']),
        endSec: _d(j['end_sec']),
        energy: _d(j['energy']),
        vocalRatio: _d(j['vocal_ratio']),
      );
}

class CuePoints {
  const CuePoints({
    required this.mixInSec,
    required this.mixOutSec,
    required this.introEndSec,
    required this.outroStartSec,
    required this.firstDropSec,
  });

  final double mixInSec;
  final double mixOutSec;
  final double introEndSec;
  final double outroStartSec;
  final double? firstDropSec;

  factory CuePoints.fromJson(Map<String, dynamic> j) => CuePoints(
        mixInSec: _d(j['mix_in_sec']),
        mixOutSec: _d(j['mix_out_sec']),
        introEndSec: _d(j['intro_end_sec']),
        outroStartSec: _d(j['outro_start_sec']),
        firstDropSec: j['first_drop_sec'] == null
            ? null
            : _d(j['first_drop_sec']),
      );
}

class StemSet {
  const StemSet({
    required this.available,
    required this.model,
    required this.dir,
    required this.files,
  });

  final bool available;
  final String? model;
  final String? dir;
  final Map<String, String> files; // 'vocals' -> path, etc.

  bool has(String stem) => available && files.containsKey(stem);

  factory StemSet.fromJson(Map<String, dynamic> j) => StemSet(
        available: j['available'] as bool? ?? false,
        model: j['model'] as String?,
        dir: j['dir'] as String?,
        files: ((j['files'] as Map?) ?? const {})
            .map((k, v) => MapEntry(k.toString(), v.toString())),
      );
}

double _d(Object? v, {double fallback = 0}) =>
    v is num ? v.toDouble() : fallback;

List<double> _dl(Object? v) =>
    v is List ? v.map((e) => e is num ? e.toDouble() : 0.0).toList() : const [];
