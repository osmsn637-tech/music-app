import 'dj_mode.dart';
import 'dj_speech_types.dart';

/// Picks a [DjIntent] for a transition by scoring every candidate reason
/// against the context and returning the highest-weight one. Pure
/// function — no DB access, no async — so it's trivially testable.
///
/// Position dominates: at the opener / closer of a queue the structural
/// intents (`introSet`, `setCloser`) win unconditionally. Otherwise the
/// signals stack: a discovery track from a favorite artist still picks
/// `discovery` (highest weight wins), but the reason ladder ensures the
/// commentary engine sees both signals.
class DjIntentSelector {
  const DjIntentSelector();

  /// Returns the chosen reason. The caller usually wraps:
  ///   `ctx.withIntent(reason.intent, reason)`
  DjDecisionReason select(DjSpeechContext ctx) {
    final candidates = <DjDecisionReason>[];

    // Structural intents — always considered.
    if (ctx.queuePosition == QueuePositionType.opener) {
      candidates.add(const DjDecisionReason(
        code: 'queue_opener',
        humanReason: 'first track of the set',
        intent: DjIntent.introSet,
        weight: 100,
      ));
    }
    if (ctx.queuePosition == QueuePositionType.closer) {
      candidates.add(const DjDecisionReason(
        code: 'queue_closer',
        humanReason: 'last track of the set',
        intent: DjIntent.setCloser,
        weight: 100,
      ));
    }

    // Recovering from a user skip beats every history signal except the
    // structural opener/closer overrides — the DJ should acknowledge the
    // signal before going back to "you usually finish this".
    if (ctx.cameFromSkip) {
      candidates.add(const DjDecisionReason(
        code: 'recover_from_skip',
        humanReason: 'switching it up after the last track',
        intent: DjIntent.recoverFromSkip,
        weight: 90,
      ));
    }

    // Listening-history signals.
    if (ctx.profile.isNeverPlayed(ctx.song.id)) {
      candidates.add(const DjDecisionReason(
        code: 'never_played',
        humanReason: "you haven't put this one on yet",
        intent: DjIntent.discovery,
        weight: 70,
      ));
    }
    if (ctx.profile.isFavorite(ctx.song.id)) {
      candidates.add(const DjDecisionReason(
        code: 'favorite',
        humanReason: 'you keep coming back to this one',
        intent: DjIntent.favoriteReturn,
        weight: 60,
      ));
    }
    final lastPlayed = ctx.profile.lastPlayedById[ctx.song.id];
    if (lastPlayed != null && ctx.now.difference(lastPlayed).inDays >= 30) {
      candidates.add(const DjDecisionReason(
        code: 'not_played_recently',
        humanReason: "it's been a while since this one came through",
        intent: DjIntent.throwback,
        weight: 55,
      ));
    }
    // The baked `artist_spotlight` clips all imply two consecutive tracks
    // by the same artist ("Same artist, different angle", "Two from the
    // same hand"). So this intent must only fire when the previous track
    // *was actually* the same artist — otherwise the DJ claims a sequence
    // that didn't happen. The "favorite artist" signal alone isn't enough.
    final prevArtist = ctx.previousSong?.artist;
    final curArtist = ctx.song.artist;
    final sameArtistRun = prevArtist != null &&
        curArtist != null &&
        prevArtist.isNotEmpty &&
        curArtist.isNotEmpty &&
        prevArtist.toLowerCase().trim() == curArtist.toLowerCase().trim();
    if (sameArtistRun && ctx.profile.isFavoriteArtist(curArtist)) {
      candidates.add(const DjDecisionReason(
        code: 'favorite_artist_run',
        humanReason: 'two in a row from this artist',
        intent: DjIntent.artistSpotlight,
        weight: 45,
      ));
    }

    // Mode signals.
    switch (ctx.mode) {
      case DjMode.workout:
        if ((ctx.song.bpm ?? 0) >= 120) {
          candidates.add(const DjDecisionReason(
            code: 'workout_high_bpm',
            humanReason: 'high BPM, set needs to keep moving',
            intent: DjIntent.workoutBoost,
            weight: 40,
          ));
        }
        break;
      case DjMode.study:
        if (_isCalm(ctx.song.mood)) {
          candidates.add(const DjDecisionReason(
            code: 'study_calm',
            humanReason: 'calm enough to stay out of the way',
            intent: DjIntent.studyFocus,
            weight: 40,
          ));
        }
        break;
      case DjMode.chill:
        candidates.add(const DjDecisionReason(
          code: 'chill_mode',
          humanReason: 'pulling the mood down a notch',
          intent: DjIntent.chillTransition,
          weight: 40,
        ));
        break;
      case DjMode.night:
        candidates.add(const DjDecisionReason(
          code: 'night_mode',
          humanReason: 'late, low room',
          intent: DjIntent.nightDrive,
          weight: 40,
        ));
        break;
      case DjMode.smartShuffle:
      case DjMode.discover:
      case DjMode.favorites:
      case DjMode.general:
        break;
    }

    // Transition signals — only meaningful when there's a previous track.
    final prev = ctx.previousSong;
    if (prev != null) {
      final prevBpm = prev.bpm;
      final curBpm = ctx.song.bpm;
      if (prevBpm != null && curBpm != null) {
        final diff = curBpm - prevBpm;
        if (diff >= 20) {
          candidates.add(const DjDecisionReason(
            code: 'energy_transition_up',
            humanReason: 'the set needs more energy',
            intent: DjIntent.energyUp,
            weight: 35,
          ));
        } else if (diff <= -20) {
          candidates.add(const DjDecisionReason(
            code: 'energy_transition_down',
            humanReason: 'easing the room down',
            intent: DjIntent.energyDown,
            weight: 35,
          ));
        }
      }
      final prevGenre = prev.genre;
      final curGenre = ctx.song.genre;
      if (prevGenre != null &&
          curGenre != null &&
          prevGenre.isNotEmpty &&
          curGenre.isNotEmpty &&
          prevGenre != curGenre) {
        candidates.add(const DjDecisionReason(
          code: 'genre_change',
          humanReason: 'switching the sound',
          intent: DjIntent.moodShift,
          weight: 25,
        ));
      }
    }

    // Default fallback so we always return something.
    candidates.add(const DjDecisionReason(
      code: 'keep_vibe',
      humanReason: 'fits the run',
      intent: DjIntent.keepVibe,
      weight: 10,
    ));

    candidates.sort((a, b) => b.weight.compareTo(a.weight));
    return candidates.first;
  }

  bool _isCalm(String? mood) {
    if (mood == null || mood.isEmpty) return false;
    const calm = {'study', 'chill', 'calm', 'instrumental', 'lofi', 'ambient'};
    return calm.contains(mood.toLowerCase());
  }
}
