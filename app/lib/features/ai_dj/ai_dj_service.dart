import 'dart:math' as math;

import '../../data/database/app_database.dart';
import '../../data/models/remote_artist.dart';
import 'dj_mode.dart';
import 'request_parser.dart';
import 'user_listening_profile.dart';

/// One contributor to a song's score, plus the points it added.
class ScoreComponent {
  const ScoreComponent({required this.key, required this.label, required this.points});
  final String key;
  final String label;
  final int points;
}

class ScoredSong {
  ScoredSong({required this.song, required this.components});
  final SongRow song;
  final List<ScoreComponent> components;

  int get total =>
      components.fold<int>(0, (sum, c) => sum + c.points);

  /// The component with the largest positive contribution, or null.
  ScoreComponent? get topPositive {
    final positives = components.where((c) => c.points > 0).toList()
      ..sort((a, b) => b.points.compareTo(a.points));
    return positives.isEmpty ? null : positives.first;
  }
}

class AiDjQueueEntry {
  const AiDjQueueEntry({
    required this.song,
    required this.score,
    required this.reason,
  });
  final SongRow song;
  final int score;
  final String reason;
}

class AiDjService {
  AiDjService({math.Random? random}) : _random = random ?? math.Random();

  final math.Random _random;

  static const _calmMoods = {'study', 'chill', 'calm', 'instrumental', 'lofi'};
  static const _energeticMoods = {'workout', 'energetic', 'party', 'hype'};

  /// Builds a queue of [limit] songs, scored, **diversified by artist** so
  /// no artist clusters back-to-back, and lightly shuffled within the top
  /// quartile so each invocation isn't identical. When [intent] is provided,
  /// songs that fail its hard filters are dropped before scoring, and
  /// matching songs receive scoring overlays.
  List<AiDjQueueEntry> buildQueue({
    required List<SongRow> songs,
    required DjMode mode,
    required UserListeningProfile profile,
    RequestIntent? intent,
    int limit = 30,
  }) {
    final pool = _applyIntentFilters(songs, intent);
    final eligible = _filterEligible(pool, mode, profile);
    // Score every eligible song. We deliberately do NOT drop zero-score
    // songs here: with sparse listening history (a couple of plays from one
    // or two artists), the score>0 cohort is tiny — the "favorite_artist"
    // boost would then dominate the queue and the user sees the same one
    // or two artists on loop. Including zero-score songs in the candidate
    // pool, then enforcing artist spacing, gives the AI DJ room to explore
    // the rest of the library while still leading with high-confidence
    // picks at the top of the queue.
    // Add per-song score jitter so generation isn't fully deterministic.
    // Without this, identical library + profile + mode produces the exact
    // same top-30 every session — users complain "same songs every time".
    // ±[_jitterRange] is wide enough to let near-tier songs leapfrog into
    // the queue but narrow enough that strong signals (favorite +50,
    // completed +25) still dominate ordering.
    final scored = eligible
        .map((s) {
          final base = _scoreWithIntent(
            song: s,
            mode: mode,
            profile: profile,
            intent: intent,
          );
          final jitter =
              _random.nextInt(_jitterRange * 2 + 1) - _jitterRange;
          return ScoredSong(
            song: base.song,
            components: [
              ...base.components,
              if (jitter != 0)
                ScoreComponent(
                  key: 'jitter',
                  label: 'Variety',
                  points: jitter,
                ),
            ],
          );
        })
        .toList()
      ..sort((a, b) => b.total.compareTo(a.total));

    // Oversample and diversify: walk the sorted list and avoid placing two
    // songs from the same artist within `_artistSpacing` of each other,
    // *and* cap how many slots one artist can fill total. Otherwise a few
    // top-scoring favorite-artist + completed + favorite tracks fill the
    // queue with the same 2–3 names. Oversampling by 4× gives the
    // diversifier enough variety to honor both rules even when the head
    // of the sort is artist-heavy.
    final overSampled =
        scored.take(math.min(limit * 4, scored.length)).toList();
    final diversified = _diversifyByArtist(overSampled, targetSize: limit);
    final top = diversified.take(limit).toList();

    // Shuffle the top half of the queue (was: top quartile). The earlier
    // 25% window meant only ~8 of 30 slots ever varied in order between
    // sessions — the back half always lined up identically. 50% gives a
    // stronger sense of a fresh set without surfacing low-score songs at
    // the front.
    final shuffleSize = math.max(1, (top.length * 0.5).ceil());
    if (shuffleSize > 1 && top.length >= shuffleSize) {
      final head = top.sublist(0, shuffleSize)..shuffle(_random);
      final tail = top.sublist(shuffleSize);
      return [...head, ...tail].map((s) => _toEntry(s, mode)).toList();
    }
    return top.map((s) => _toEntry(s, mode)).toList();
  }

  /// Half-width of the random jitter added to each song's total score.
  /// ±10 means a typical run swaps neighbours that are within 20 points of
  /// each other — enough variety without inverting strong signals.
  static const int _jitterRange = 10;

  /// Spacing window: an artist can't appear within this many positions of
  /// itself. Wider than the old value of 3 because users repeatedly
  /// noticed clusters of the same 2–3 top artists in a 30-track queue.
  static const int _artistSpacing = 5;

  /// Per-artist cap as a fraction of the requested queue size. With a
  /// target of 30 and 0.20 → max 6 tracks per artist; with 10 → max 2.
  /// Floor of 2 so single-artist sets still produce *something*.
  static const double _artistCapFraction = 0.20;

  /// Reorders [sorted] (highest score first) so that no artist appears
  /// within [_artistSpacing] positions of itself, **and** no artist fills
  /// more than ~[_artistCapFraction] of the final queue. Picks the
  /// highest-scored candidate whose artist isn't blocked or capped;
  /// falls back to the top candidate when the queue dictates it (e.g., a
  /// small library with few artists).
  ///
  /// Why a cap on top of spacing: spacing alone enforces local
  /// alternation but lets one artist still take a quarter of the queue
  /// across a 30-track set. The cap puts a global ceiling so the user
  /// hears a real spread of names.
  List<ScoredSong> _diversifyByArtist(
    List<ScoredSong> sorted, {
    required int targetSize,
  }) {
    if (sorted.length <= _artistSpacing + 1) return sorted;
    final perArtistCap =
        math.max(2, (targetSize * _artistCapFraction).ceil());
    final perArtistCount = <String, int>{};
    final result = <ScoredSong>[];
    final pending = [...sorted];

    bool isCapped(Iterable<String> names) =>
        names.isNotEmpty && names.every((n) => (perArtistCount[n] ?? 0) >= perArtistCap);

    while (pending.isNotEmpty) {
      // Multi-artist songs ("Drake, 21 Savage") contribute *every* name
      // they list — otherwise a Drake solo could land right next to a
      // Drake feature because the raw strings don't match.
      final blocked = <String>{};
      final lookback = result.length < _artistSpacing
          ? result
          : result.sublist(result.length - _artistSpacing);
      for (final s in lookback) {
        blocked.addAll(splitMultiArtist(s.song.artist));
      }

      // First pass: prefer a candidate that satisfies BOTH constraints
      // (no spacing collision AND under the per-artist cap).
      var picked = -1;
      for (var i = 0; i < pending.length; i++) {
        final names = splitMultiArtist(pending[i].song.artist);
        final spacingOk = names.isEmpty || !names.any(blocked.contains);
        final capOk = !isCapped(names);
        if (spacingOk && capOk) {
          picked = i;
          break;
        }
      }

      // Second pass: if the cap is exhausted across the head of the
      // pending list, allow a spacing-only match so we still produce a
      // sensible queue when only a few artists are eligible.
      if (picked < 0) {
        for (var i = 0; i < pending.length; i++) {
          final names = splitMultiArtist(pending[i].song.artist);
          if (names.isEmpty || !names.any(blocked.contains)) {
            picked = i;
            break;
          }
        }
      }

      if (picked < 0) picked = 0;
      final chosen = pending.removeAt(picked);
      result.add(chosen);
      for (final n in splitMultiArtist(chosen.song.artist)) {
        perArtistCount[n] = (perArtistCount[n] ?? 0) + 1;
      }
    }
    return result;
  }

  // ---- intent application ---------------------------------------------

  List<SongRow> _applyIntentFilters(List<SongRow> songs, RequestIntent? intent) {
    if (intent == null || intent.isEmpty) return songs;
    return songs.where((s) {
      final artist = s.artist?.toLowerCase() ?? '';
      final genre = s.genre?.toLowerCase() ?? '';
      final mood = s.mood?.toLowerCase() ?? '';
      for (final a in intent.excludeArtists) {
        if (artist.contains(a)) return false;
      }
      for (final g in intent.excludeGenres) {
        if (genre.contains(g)) return false;
      }
      if (intent.requireGenres.isNotEmpty) {
        final any = intent.requireGenres.any((g) => genre.contains(g));
        if (!any) return false;
      }
      if (intent.instrumentalOnly == true) {
        final isInst = mood.contains('instrumental') ||
            genre.contains('instrumental') ||
            genre.contains('score') ||
            genre.contains('soundtrack') ||
            genre.contains('classical') ||
            genre.contains('ambient');
        if (!isInst) return false;
      }
      return true;
    }).toList();
  }

  ScoredSong _scoreWithIntent({
    required SongRow song,
    required DjMode mode,
    required UserListeningProfile profile,
    required RequestIntent? intent,
  }) {
    final base = scoreSong(song: song, mode: mode, profile: profile);
    if (intent == null || intent.isEmpty) return base;
    final overlays = <ScoreComponent>[];
    final mood = song.mood?.toLowerCase() ?? '';
    if (intent.moods.isNotEmpty &&
        intent.moods.any((m) => mood.contains(m))) {
      overlays.add(const ScoreComponent(
        key: 'intent_mood',
        label: 'Matches request',
        points: 30,
      ));
    }
    final bpm = song.bpm;
    if (intent.bpm != null && bpm != null) {
      if (intent.bpm!.contains(bpm)) {
        overlays.add(const ScoreComponent(
          key: 'intent_bpm',
          label: 'Right tempo',
          points: 25,
        ));
      } else {
        overlays.add(const ScoreComponent(
          key: 'intent_bpm_miss',
          label: 'Off-tempo',
          points: -25,
        ));
      }
    }
    if (intent.discover == true && profile.isNeverPlayed(song.id)) {
      overlays.add(const ScoreComponent(
        key: 'intent_discover',
        label: 'New to you',
        points: 30,
      ));
    }
    if (intent.requireGenres.isNotEmpty) {
      final genre = song.genre?.toLowerCase() ?? '';
      if (intent.requireGenres.any((g) => genre.contains(g))) {
        overlays.add(const ScoreComponent(
          key: 'intent_genre',
          label: 'Requested genre',
          points: 20,
        ));
      }
    }
    if (overlays.isEmpty) return base;
    return ScoredSong(
      song: base.song,
      components: [...base.components, ...overlays],
    );
  }

  /// Computes the score (and contributing components) for one song.
  ScoredSong scoreSong({
    required SongRow song,
    required DjMode mode,
    required UserListeningProfile profile,
  }) {
    final components = <ScoreComponent>[];
    final modeId = mode.id;

    if (profile.isFavorite(song.id)) {
      components.add(const ScoreComponent(
        key: 'favorite',
        label: 'Favorite',
        points: 50,
      ));
    }
    if (profile.wasCompleted(song.id)) {
      components.add(const ScoreComponent(
        key: 'completed',
        label: 'Often completed',
        points: 25,
      ));
    }
    if (profile.wasReplayed(song.id)) {
      components.add(const ScoreComponent(
        key: 'replayed',
        label: 'Replayed',
        points: 15,
      ));
    }
    if (profile.hasHighPlayCount(song.id)) {
      components.add(const ScoreComponent(
        key: 'high_play_count',
        label: 'Played often',
        points: 10,
      ));
    }
    if (profile.wasSkipped(song.id)) {
      components.add(const ScoreComponent(
        key: 'skipped',
        label: 'Often skipped',
        points: -35,
      ));
    }
    if (profile.playedRecently(song.id)) {
      components.add(const ScoreComponent(
        key: 'recent',
        label: 'Played recently',
        points: -25,
      ));
    }
    if (profile.isFavoriteArtist(song.artist)) {
      components.add(const ScoreComponent(
        key: 'favorite_artist',
        label: 'Favorite artist',
        points: 15,
      ));
    }
    if (_moodMatchesMode(song.mood, mode)) {
      components.add(const ScoreComponent(
        key: 'mood_match',
        label: 'Matches mood',
        points: 25,
      ));
    }
    if (profile.completesInContext(song.id, modeId)) {
      components.add(const ScoreComponent(
        key: 'context_completes',
        label: 'You finish this in this mode',
        points: 20,
      ));
    }

    switch (mode) {
      case DjMode.discover:
        if (profile.isNeverPlayed(song.id)) {
          components.add(const ScoreComponent(
            key: 'discover_new',
            label: 'New to you',
            points: 30,
          ));
        }
        // Light bonus if the artist is one you like, but the song is new
        if (profile.isNeverPlayed(song.id) &&
            profile.isFavoriteArtist(song.artist)) {
          components.add(const ScoreComponent(
            key: 'discover_kin',
            label: 'New from a favorite artist',
            points: 15,
          ));
        }
        break;
      case DjMode.study:
        if (_isCalmMood(song.mood)) {
          components.add(const ScoreComponent(
            key: 'study_calm',
            label: 'Calm vibe',
            points: 20,
          ));
        }
        // Penalize obviously high-energy in study
        if ((song.bpm ?? 0) >= 140 || _isEnergeticMood(song.mood)) {
          components.add(const ScoreComponent(
            key: 'study_too_hot',
            label: 'High energy',
            points: -20,
          ));
        }
        break;
      case DjMode.workout:
        if ((song.bpm ?? 0) >= 120) {
          components.add(const ScoreComponent(
            key: 'workout_high_bpm',
            label: 'High BPM',
            points: 20,
          ));
        }
        if (_isCalmMood(song.mood)) {
          components.add(const ScoreComponent(
            key: 'workout_too_calm',
            label: 'Too calm',
            points: -10,
          ));
        }
        break;
      case DjMode.favorites:
        // Filtering already restricts the input set, but make sure favorites
        // dominate ordering with a strong bonus.
        if (profile.isFavorite(song.id)) {
          components.add(const ScoreComponent(
            key: 'favorites_mode',
            label: 'Favorite (mode)',
            points: 10,
          ));
        }
        break;
      case DjMode.chill:
      case DjMode.night:
      case DjMode.general:
      case DjMode.smartShuffle:
        break;
    }

    return ScoredSong(song: song, components: components);
  }

  /// Generates the human-readable reason text shown next to a queued song.
  String explainChoice({
    required ScoredSong scored,
    required DjMode mode,
  }) {
    final song = scored.song;
    final keys = scored.components
        .where((c) => c.points > 0)
        .map((c) => c.key)
        .toSet();

    if (keys.contains('discover_kin')) {
      return 'A new ${song.artist ?? "artist"} track you haven\'t played yet.';
    }
    if (keys.contains('discover_new')) {
      return "Something new — you haven't played this one yet.";
    }
    if (keys.contains('favorite') && keys.contains('mood_match')) {
      return 'A favorite that fits your ${mode.label.toLowerCase()} mood.';
    }
    if (keys.contains('favorite_artist') &&
        keys.contains('context_completes')) {
      return 'You usually finish this artist\'s songs in '
          '${mode.label.toLowerCase()} mode.';
    }
    if (keys.contains('workout_high_bpm') && keys.contains('completed')) {
      return 'High-energy track you\'ve crushed before.';
    }
    if (keys.contains('workout_high_bpm')) {
      return 'High-BPM track for the workout.';
    }
    if (keys.contains('study_calm') && keys.contains('completed')) {
      return 'Calm track you\'ve listened all the way through before.';
    }
    if (keys.contains('study_calm')) {
      return 'Calm vibe for studying.';
    }
    if (keys.contains('mood_match')) {
      return 'Matches your ${mode.label.toLowerCase()} vibe.';
    }
    if (keys.contains('favorite')) {
      return 'One of your favorites.';
    }
    if (keys.contains('completed')) {
      return 'You usually finish this one.';
    }
    if (keys.contains('replayed')) {
      return 'You\'ve replayed this before.';
    }
    if (keys.contains('favorite_artist')) {
      return 'From an artist you listen to a lot.';
    }
    if (keys.contains('high_play_count')) {
      return 'A song you reach for often.';
    }
    return 'Picked for you.';
  }

  // --- internals --------------------------------------------------------

  AiDjQueueEntry _toEntry(ScoredSong s, DjMode mode) {
    return AiDjQueueEntry(
      song: s.song,
      score: s.total,
      reason: explainChoice(scored: s, mode: mode),
    );
  }

  List<SongRow> _filterEligible(
    List<SongRow> songs,
    DjMode mode,
    UserListeningProfile profile,
  ) {
    switch (mode) {
      case DjMode.favorites:
        return songs.where((s) => profile.isFavorite(s.id)).toList();
      case DjMode.discover:
        // Songs with high skip count aren't a great surprise.
        return songs.where((s) => !profile.wasSkipped(s.id)).toList();
      default:
        return songs;
    }
  }

  bool _moodMatchesMode(String? mood, DjMode mode) {
    if (mood == null || mood.isEmpty) return false;
    final m = mood.toLowerCase();
    switch (mode) {
      case DjMode.study:
        return m == 'study' || m == 'calm' || m == 'instrumental';
      case DjMode.workout:
        return m == 'workout' || m == 'energetic';
      case DjMode.chill:
        return m == 'chill' || m == 'lofi' || m == 'calm';
      case DjMode.night:
        return m == 'night' || m == 'sleep' || m == 'ambient';
      case DjMode.favorites:
      case DjMode.discover:
      case DjMode.smartShuffle:
      case DjMode.general:
        return false;
    }
  }

  bool _isCalmMood(String? mood) {
    if (mood == null) return false;
    return _calmMoods.contains(mood.toLowerCase());
  }

  bool _isEnergeticMood(String? mood) {
    if (mood == null) return false;
    return _energeticMoods.contains(mood.toLowerCase());
  }
}
