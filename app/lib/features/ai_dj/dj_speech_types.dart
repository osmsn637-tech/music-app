import '../../data/database/app_database.dart';
import '../lyrics/lyrics_hook_extractor.dart';
import 'dj_mode.dart';
import 'user_listening_profile.dart';

/// Why the DJ is talking *now*. The selector picks one based on song +
/// queue + listening signals; the commentary engine maps it to a phrasing.
///
/// Most intents map to several phrasings; some imply structural cues
/// (introSet → opener, setCloser → closer) that the position helper also
/// picks up independently.
enum DjIntent {
  introSet,
  nextTrack,
  energyUp,
  energyDown,
  keepVibe,
  studyFocus,
  chillTransition,
  workoutBoost,
  nightDrive,
  discovery,
  throwback,
  favoriteReturn,
  artistSpotlight,
  moodShift,
  recoverFromSkip,
  setCloser,
}

extension DjIntentX on DjIntent {
  /// Stable string for storage / cache keys / logs.
  String get id {
    switch (this) {
      case DjIntent.introSet:
        return 'intro_set';
      case DjIntent.nextTrack:
        return 'next_track';
      case DjIntent.energyUp:
        return 'energy_up';
      case DjIntent.energyDown:
        return 'energy_down';
      case DjIntent.keepVibe:
        return 'keep_vibe';
      case DjIntent.studyFocus:
        return 'study_focus';
      case DjIntent.chillTransition:
        return 'chill_transition';
      case DjIntent.workoutBoost:
        return 'workout_boost';
      case DjIntent.nightDrive:
        return 'night_drive';
      case DjIntent.discovery:
        return 'discovery';
      case DjIntent.throwback:
        return 'throwback';
      case DjIntent.favoriteReturn:
        return 'favorite_return';
      case DjIntent.artistSpotlight:
        return 'artist_spotlight';
      case DjIntent.moodShift:
        return 'mood_shift';
      case DjIntent.recoverFromSkip:
        return 'recover_from_skip';
      case DjIntent.setCloser:
        return 'set_closer';
    }
  }
}

/// Where the song sits in the active queue. Drives both intent selection
/// (only `setCloser` makes sense at `closer`) and template variant choice
/// (a `studyFocus` line at the opener should introduce the set; the same
/// intent mid-set should sound like flow maintenance).
enum QueuePositionType { opener, early, middle, late, closer }

extension QueuePositionTypeX on QueuePositionType {
  String get id {
    switch (this) {
      case QueuePositionType.opener:
        return 'opener';
      case QueuePositionType.early:
        return 'early';
      case QueuePositionType.middle:
        return 'middle';
      case QueuePositionType.late:
        return 'late';
      case QueuePositionType.closer:
        return 'closer';
    }
  }
}

/// Maps a queue index + length to a position bucket. Boundaries:
///   - 0 → opener
///   - last → closer
///   - first quarter → early
///   - last quarter → late
///   - everything else → middle
QueuePositionType getQueuePositionType(int index, int length) {
  if (length <= 0) return QueuePositionType.opener;
  if (index <= 0) return QueuePositionType.opener;
  if (index >= length - 1) return QueuePositionType.closer;
  final ratio = index / length;
  if (ratio < 0.25) return QueuePositionType.early;
  if (ratio < 0.75) return QueuePositionType.middle;
  return QueuePositionType.late;
}

/// All inputs the commentary engine + intent selector need to produce a
/// natural DJ line. Built once per transition by the queue controller.
class DjSpeechContext {
  const DjSpeechContext({
    required this.song,
    required this.previousSong,
    required this.nextSong,
    required this.mode,
    required this.queueIndex,
    required this.queueLength,
    required this.queuePosition,
    required this.profile,
    required this.now,
    this.cameFromSkip = false,
    this.intent,
    this.reason,
    this.firstLyricLine,
    this.hookLyricLine,
    this.hookConfidence = LyricHookConfidence.none,
  });

  final SongRow song;
  final SongRow? previousSong;
  final SongRow? nextSong;
  final DjMode mode;
  final int queueIndex;
  final int queueLength;
  final QueuePositionType queuePosition;
  final UserListeningProfile profile;
  final DateTime now;

  /// True when this context was built immediately after a user-initiated
  /// skip. The selector reads it to surface a `recoverFromSkip` intent
  /// ("yeah, not that one") instead of a generic transition line.
  final bool cameFromSkip;

  /// The chosen intent. Initially null; set by the selector.
  final DjIntent? intent;

  /// Why this intent was chosen. Initially null; set by the selector.
  final DjDecisionReason? reason;

  /// First non-trivial line of the song's synced lyrics (extracted from
  /// `song.localLyricsPath`). Null when no `.lrc` is on disk or it didn't
  /// produce a usable line. Lyric-quoting templates gate on `hasLyricHook`.
  final String? firstLyricLine;

  /// Most-repeated lyric line — usually the chorus opener. Same null
  /// semantics as [firstLyricLine].
  final String? hookLyricLine;

  /// How confident the extractor was that the hook is worth quoting. The
  /// commentary engine's quote-gate cross-references this with [isFavorite]
  /// / [isDiscovery] / [cameFromSkip] etc. to decide whether to actually
  /// pick a lyric template for this transition.
  final LyricHookConfidence hookConfidence;

  bool get isFirstSong => queuePosition == QueuePositionType.opener;
  bool get isLastSong => queuePosition == QueuePositionType.closer;
  bool get isFavorite => profile.isFavorite(song.id);
  bool get isDiscovery => profile.isNeverPlayed(song.id);
  bool get wasPlayedRecently => profile.playedRecently(song.id);

  /// True iff a lyric snippet is available to quote in commentary.
  bool get hasLyricHook =>
      (firstLyricLine != null && firstLyricLine!.isNotEmpty) ||
      (hookLyricLine != null && hookLyricLine!.isNotEmpty);

  DjSpeechContext withIntent(DjIntent intent, DjDecisionReason reason) {
    return DjSpeechContext(
      song: song,
      previousSong: previousSong,
      nextSong: nextSong,
      mode: mode,
      queueIndex: queueIndex,
      queueLength: queueLength,
      queuePosition: queuePosition,
      profile: profile,
      now: now,
      cameFromSkip: cameFromSkip,
      intent: intent,
      reason: reason,
      firstLyricLine: firstLyricLine,
      hookLyricLine: hookLyricLine,
      hookConfidence: hookConfidence,
    );
  }
}

/// One contributing reason the selector can attach to an intent. Multiple
/// candidates are scored by [weight]; highest wins. The `humanReason` is
/// not spoken verbatim — the commentary engine uses the intent + position
/// to pick a phrasing — but it's stored on `recent_dj_lines` for debug
/// and surfaced in the Up Next list.
class DjDecisionReason {
  const DjDecisionReason({
    required this.code,
    required this.humanReason,
    required this.intent,
    required this.weight,
  });

  final String code;
  final String humanReason;
  final DjIntent intent;
  final int weight;
}
