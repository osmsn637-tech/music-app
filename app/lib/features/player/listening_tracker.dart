import 'dart:async';

import '../../data/database/app_database.dart';
import '../../data/repositories/listening_repository.dart';

/// Listening event types — match the values stored in `listening_events.event_type`.
class ListeningEventType {
  static const play = 'play';
  static const pause = 'pause';
  static const complete = 'complete';
  static const skip = 'skip';
  static const replay = 'replay';
  static const favorite = 'favorite';
  static const unfavorite = 'unfavorite';
  static const addToPlaylist = 'add_to_playlist';
}

/// Translates raw player + UI events into typed listening events and
/// rolls them up into `song_stats` / `context_stats`.
///
/// Decisions follow the spec:
///  - `complete` fires once per session when position >= 98% of duration.
///  - `skip` fires when a new song starts before the previous reached
///    30s **and** before 50% of its duration.
///  - `replay` fires when the same song is re-started within 10s of a
///    `complete` event.
class ListeningTracker {
  ListeningTracker({
    required this.repo,
    required this.contextResolver,
    DateTime Function() now = _systemNow,
  }) : _now = now;

  final ListeningRepository repo;

  /// Returns the active listening context (e.g. "study", "workout", or
  /// "general" when no DJ mode is active). Wired to a Riverpod provider in
  /// production; pluggable for tests.
  final String Function() contextResolver;

  final DateTime Function() _now;

  // Active session state
  SongRow? _currentSong;
  int _maxPositionMs = 0;
  bool _completedThisSession = false;
  bool _pausedSinceLastPlay = false;

  // Cross-session state
  String? _lastCompletedSongId;
  DateTime? _lastCompletedAt;

  static const _completeThreshold = 0.98;
  static const _skipMaxPositionMs = 30 * 1000;
  static const _skipMaxRatio = 0.5;
  static const _replayWindow = Duration(seconds: 10);

  /// Call when the active song changes (i.e. user picks a new song or the
  /// queue advances). Resolves the previous session (potentially emitting
  /// `skip`) and starts a fresh one for [newSong].
  Future<void> onSongChanged(SongRow? newSong) async {
    final previous = _currentSong;
    if (previous != null &&
        (newSong == null || newSong.id != previous.id)) {
      await _resolveOpenSession();
    }

    _currentSong = newSong;
    _maxPositionMs = 0;
    _completedThisSession = false;
    _pausedSinceLastPlay = false;

    if (newSong == null) return;

    final isReplay = _lastCompletedSongId == newSong.id &&
        _lastCompletedAt != null &&
        _now().difference(_lastCompletedAt!) <= _replayWindow;

    await _emit(
      songId: newSong.id,
      type: isReplay
          ? ListeningEventType.replay
          : ListeningEventType.play,
    );
  }

  /// Call on every position tick. We only need the latest position; the
  /// tracker decides when to fire `complete`.
  Future<void> onPosition(Duration position, Duration? duration) async {
    final song = _currentSong;
    if (song == null) return;
    final ms = position.inMilliseconds;
    if (ms > _maxPositionMs) _maxPositionMs = ms;

    if (_completedThisSession) return;
    if (duration == null || duration.inMilliseconds <= 0) return;

    final ratio = ms / duration.inMilliseconds;
    if (ratio >= _completeThreshold) {
      _completedThisSession = true;
      _lastCompletedSongId = song.id;
      _lastCompletedAt = _now();
      await _emit(
        songId: song.id,
        type: ListeningEventType.complete,
        positionMs: ms,
        listenedMs: ms,
      );
    }
  }

  /// Call when the player toggles to paused.
  Future<void> onPaused() async {
    final song = _currentSong;
    if (song == null) return;
    if (_pausedSinceLastPlay) return;
    _pausedSinceLastPlay = true;
    await _emit(
      songId: song.id,
      type: ListeningEventType.pause,
      positionMs: _maxPositionMs,
    );
  }

  /// Call when the player goes from paused → playing on the same song.
  void onResumed() {
    _pausedSinceLastPlay = false;
  }

  /// Call when the user toggles favorite.
  Future<void> onFavoriteToggled({
    required String songId,
    required bool nowFavorite,
  }) {
    return _emit(
      songId: songId,
      type: nowFavorite
          ? ListeningEventType.favorite
          : ListeningEventType.unfavorite,
    );
  }

  /// Call when the user adds a song to a playlist.
  Future<void> onAddedToPlaylist(String songId) {
    return _emit(
      songId: songId,
      type: ListeningEventType.addToPlaylist,
    );
  }

  /// Resolves the currently-open session (if any) — used at app shutdown
  /// or when the player is fully stopped.
  Future<void> flush() async {
    if (_currentSong == null) return;
    await _resolveOpenSession();
    _currentSong = null;
  }

  // --- internals --------------------------------------------------------

  Future<void> _resolveOpenSession() async {
    final song = _currentSong;
    if (song == null) return;
    if (_completedThisSession) return;

    final positionMs = _maxPositionMs;
    final durationMs = song.durationMs;
    final under30s = positionMs < _skipMaxPositionMs;
    final underHalf = durationMs == null || durationMs <= 0
        ? true
        : (positionMs / durationMs) < _skipMaxRatio;

    if (under30s && underHalf) {
      await _emit(
        songId: song.id,
        type: ListeningEventType.skip,
        positionMs: positionMs,
        listenedMs: positionMs,
      );
    }
  }

  Future<void> _emit({
    required String songId,
    required String type,
    int? positionMs,
    int? listenedMs,
  }) async {
    final context = contextResolver();
    await repo.insertEvent(
      songId: songId,
      eventType: type,
      context: context,
      positionMs: positionMs,
      listenedMs: listenedMs,
    );
    await repo.applyEventToStats(
      songId: songId,
      eventType: type,
      context: context,
      listenedMs: listenedMs ?? 0,
    );
  }

  static DateTime _systemNow() => DateTime.now();
}
