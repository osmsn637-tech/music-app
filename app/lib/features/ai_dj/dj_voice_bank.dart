import 'dart:math' as math;

import 'dj_mode.dart';
import 'dj_speech_types.dart';

class DjVoiceBankManifest {
  const DjVoiceBankManifest({
    required this.voiceId,
    required this.clips,
    this.version = 1,
  });

  factory DjVoiceBankManifest.empty() {
    return const DjVoiceBankManifest(voiceId: 'empty', clips: []);
  }

  factory DjVoiceBankManifest.fromJson(Map<String, Object?> json) {
    final rawClips = json['clips'];
    return DjVoiceBankManifest(
      version: _asInt(json['version']) ?? 1,
      voiceId: json['voiceId']?.toString() ?? 'default',
      clips: rawClips is List
          ? rawClips
                .whereType<Map>()
                .map((raw) => DjVoiceClip.fromJson(raw.cast<String, Object?>()))
                .where((clip) => clip != null)
                .cast<DjVoiceClip>()
                .toList(growable: false)
          : const [],
    );
  }

  final int version;
  final String voiceId;
  final List<DjVoiceClip> clips;

  bool get isEmpty => clips.isEmpty;
}

class DjVoiceClip {
  const DjVoiceClip({
    required this.id,
    required this.path,
    this.songId,
    this.songSlug,
    this.artistId,
    this.intent,
    this.position,
    this.mode,
    this.priority = 0,
  });

  static DjVoiceClip? fromJson(Map<String, Object?> json) {
    final id = json['id']?.toString().trim();
    final path = json['path']?.toString().trim();
    if (id == null || id.isEmpty || path == null || path.isEmpty) {
      return null;
    }
    return DjVoiceClip(
      id: id,
      path: path,
      songId: _blankToNull(json['songId']?.toString()),
      songSlug: _blankToNull(json['songSlug']?.toString()),
      artistId: _blankToNull(json['artistId']?.toString()),
      intent: _parseIntent(json['intent']?.toString()),
      position: _parsePosition(json['position']?.toString()),
      mode: _parseMode(json['mode']?.toString()),
      priority: _asInt(json['priority']) ?? 0,
    );
  }

  final String id;
  final String path;

  /// Exact content-hash song id (rare — only when you really want this clip
  /// tied to a specific file). Most per-song clips use [songSlug] instead.
  final String? songId;

  /// Title-based slug for matching (e.g. "sicko-mode", "what-did-i-miss").
  /// Selector matches via `contains` on the slugified active title, so
  /// "Knife Talk (feat. 21 Savage)" still matches a clip with
  /// `songSlug: "knife-talk"`.
  final String? songSlug;

  final String? artistId;
  final DjIntent? intent;
  final QueuePositionType? position;
  final DjMode? mode;
  final int priority;
}

class DjVoiceBankRequest {
  const DjVoiceBankRequest({
    required this.songId,
    required this.songTitleSlug,
    required this.artistIds,
    required this.mode,
    required this.intent,
    required this.position,
  });

  final String songId;

  /// Slugified song title (e.g. "knife-talk-feat-21-savage-project-pat").
  /// Clips with `songSlug` set match if their slug appears anywhere in
  /// this string — robust to feature-credit suffixes in the title.
  final String songTitleSlug;

  /// Slugified artist names for the active song (e.g. {"drake", "21-savage"}
  /// for "Drake, 21 Savage"). A clip with `artistId` set must match one of
  /// these slugs to be eligible.
  final Set<String> artistIds;

  final DjMode mode;
  final DjIntent intent;
  final QueuePositionType position;
}

/// Lowercase, alphanumerics + hyphens only. Multi-word becomes
/// `hyphen-separated`. Drops `$`, `.`, `'`, and other punctuation so
/// "A$AP Rocky" -> "asap-rocky" and "PARTYNEXTDOOR" -> "partynextdoor".
String slugifyArtist(String raw) {
  final cleaned = raw
      .toLowerCase()
      .replaceAll(RegExp(r"[^a-z0-9 ]+"), "")
      .trim();
  if (cleaned.isEmpty) return "";
  return cleaned.replaceAll(RegExp(r"\s+"), "-");
}

class DjVoiceBankSelector {
  const DjVoiceBankSelector(this.manifest);

  final DjVoiceBankManifest manifest;

  DjVoiceClip? selectForContext(
    DjSpeechContext context, {
    Set<String> excludeIds = const {},
    math.Random? random,
  }) {
    final rawArtist = context.song.artist ?? '';
    final artistIds = <String>{};
    for (final part in rawArtist.split(RegExp(r'[,&]|\bft\.?\b|\bfeat\.?\b'))) {
      final slug = slugifyArtist(part);
      if (slug.isNotEmpty) artistIds.add(slug);
    }

    return select(
      DjVoiceBankRequest(
        songId: context.song.id,
        songTitleSlug: slugifyArtist(context.song.title),
        artistIds: artistIds,
        mode: context.mode,
        intent: context.intent ?? DjIntent.nextTrack,
        position: context.queuePosition,
      ),
      excludeIds: excludeIds,
      random: random,
    );
  }

  /// Picks a clip for [request]. To avoid the "same line every time"
  /// problem, we collect *all* clips matching the hard filters, group
  /// them by score, and randomly pick from the top-scoring tier — biased
  /// away from anything in [excludeIds] (recently-played clip IDs). If
  /// every top-tier clip is excluded, we fall back to the next tier; if
  /// every clip is excluded, we ignore [excludeIds] for this pick rather
  /// than returning null.
  DjVoiceClip? select(
    DjVoiceBankRequest request, {
    Set<String> excludeIds = const {},
    math.Random? random,
  }) {
    final scored = <_ScoredClip>[];
    for (final clip in manifest.clips) {
      final score = _score(clip, request);
      if (score == null) continue;
      scored.add(_ScoredClip(clip, score));
    }
    if (scored.isEmpty) return null;

    // Sort highest score first.
    scored.sort((a, b) => b.score.compareTo(a.score));

    final rng = random ?? math.Random();

    // Walk score tiers from best to worst, picking the first tier that
    // contains a non-excluded clip.
    var i = 0;
    while (i < scored.length) {
      final tierScore = scored[i].score;
      final tier = <_ScoredClip>[];
      while (i < scored.length && scored[i].score == tierScore) {
        tier.add(scored[i]);
        i += 1;
      }
      final fresh = tier.where((s) => !excludeIds.contains(s.clip.id)).toList();
      if (fresh.isNotEmpty) {
        return fresh[rng.nextInt(fresh.length)].clip;
      }
    }

    // Every clip was excluded — pick randomly from the top tier anyway
    // so we still say *something* rather than going silent.
    final topScore = scored.first.score;
    final topTier =
        scored.where((s) => s.score == topScore).toList(growable: false);
    return topTier[rng.nextInt(topTier.length)].clip;
  }

  int? _score(DjVoiceClip clip, DjVoiceBankRequest request) {
    var score = clip.priority;

    final songId = clip.songId;
    if (songId != null) {
      if (songId != request.songId) return null;
      score += 1000;
    }

    final songSlug = clip.songSlug;
    if (songSlug != null) {
      if (!request.songTitleSlug.contains(songSlug)) return null;
      score += 900;
    }

    final artistId = clip.artistId;
    if (artistId != null) {
      if (!request.artistIds.contains(artistId)) return null;
      score += 500;
    }

    final intent = clip.intent;
    if (intent != null) {
      if (intent != request.intent) return null;
      score += 250;
    }

    final position = clip.position;
    if (position != null) {
      if (position != request.position) return null;
      score += 160;
    }

    final mode = clip.mode;
    if (mode != null) {
      if (mode != request.mode) return null;
      score += 90;
    }

    return score;
  }
}

class _ScoredClip implements Comparable<_ScoredClip> {
  const _ScoredClip(this.clip, this.score);

  final DjVoiceClip clip;
  final int score;

  @override
  int compareTo(_ScoredClip other) {
    final byScore = other.score.compareTo(score);
    if (byScore != 0) return byScore;
    return clip.id.compareTo(other.clip.id);
  }
}

DjIntent? _parseIntent(String? raw) {
  final id = _blankToNull(raw);
  if (id == null) return null;
  for (final value in DjIntent.values) {
    if (value.id == id) return value;
  }
  return null;
}

QueuePositionType? _parsePosition(String? raw) {
  final id = _blankToNull(raw);
  if (id == null) return null;
  for (final value in QueuePositionType.values) {
    if (value.id == id) return value;
  }
  return null;
}

DjMode? _parseMode(String? raw) {
  final id = _blankToNull(raw);
  if (id == null) return null;
  for (final value in DjMode.values) {
    if (value.id == id) return value;
  }
  return null;
}

String? _blankToNull(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  return trimmed;
}

int? _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}
