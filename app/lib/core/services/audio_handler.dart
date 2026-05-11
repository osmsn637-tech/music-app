import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart' as ja;

import '../../data/database/app_database.dart';
import '../../features/player/player_service.dart';

/// Bridge between our two-deck [PlayerService] and the OS playback notification
/// (lockscreen widget, Bluetooth media buttons, Wear OS controls). Owned as a
/// singleton via [AudioService.init] in `main.dart` and exposed through a
/// Riverpod provider.
///
/// Lockscreen commands route through [AppAudioHandler] back into our app:
///   - play / pause / seek → directly to the active deck of [PlayerService].
///   - skipToNext → forwarded to [onSkipNextRequested]; the AI DJ controller
///     installs a callback there so a Bluetooth "next" button counts as a
///     user-initiated skip (and triggers negative-signal re-ranking).
///   - skipToPrevious → forwarded to [onSkipPreviousRequested].
///
/// Going the other direction, [PlayerService]'s active-deck streams flow into
/// `playbackState` so the OS's notification scrubber tracks position, and
/// callers invoke [announceSong] after starting a track to publish the
/// `MediaItem` (title, artist, artwork) the OS displays.
class AppAudioHandler extends BaseAudioHandler with SeekHandler {
  AppAudioHandler(this._service) {
    _stateSub = _service.playerStateStream.listen(_onPlayerState);
    _posSub = _service.positionStream.listen(_onPosition);
    _durSub = _service.durationStream.listen(_onDuration);
    _emit();
  }

  final PlayerService _service;

  StreamSubscription<ja.PlayerState>? _stateSub;
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<Duration?>? _durSub;

  Duration _position = Duration.zero;
  Duration? _duration;
  bool _playing = false;
  ja.ProcessingState _processing = ja.ProcessingState.idle;

  /// Installed by AiDjQueueController so lockscreen / Bluetooth "next" gets
  /// the same negative-signal treatment as the in-app skip button.
  Future<void> Function()? onSkipNextRequested;

  /// Installed by AiDjQueueController so lockscreen "previous" jumps back
  /// in the queue (no negative signal — symmetric).
  Future<void> Function()? onSkipPreviousRequested;

  /// Publish the now-playing metadata to the OS. Called by callers that
  /// know about songs (NowPlayingController). Pure data — does not start
  /// or stop playback.
  void announceSong(SongRow song) {
    final artworkPath = song.localArtworkPath;
    mediaItem.add(MediaItem(
      id: song.id,
      title: song.title,
      artist: song.artist,
      album: song.album,
      duration: song.durationMs == null
          ? null
          : Duration(milliseconds: song.durationMs!),
      artUri: (artworkPath != null) ? Uri.file(artworkPath) : null,
    ));
  }

  // ---- AudioHandler overrides — lockscreen / BT commands ---------------

  @override
  Future<void> play() => _service.resume();

  @override
  Future<void> pause() => _service.pause();

  @override
  Future<void> stop() async {
    await _service.stop();
    await super.stop();
  }

  @override
  Future<void> seek(Duration position) => _service.seek(position);

  @override
  Future<void> skipToNext() async {
    final cb = onSkipNextRequested;
    if (cb != null) await cb();
  }

  @override
  Future<void> skipToPrevious() async {
    final cb = onSkipPreviousRequested;
    if (cb != null) await cb();
  }

  // ---- bridge from PlayerService streams to playbackState --------------

  void _onPlayerState(ja.PlayerState ps) {
    _playing = ps.playing;
    _processing = ps.processingState;
    _emit();
  }

  void _onPosition(Duration p) {
    _position = p;
    _emit();
  }

  void _onDuration(Duration? d) {
    _duration = d;
  }

  void _emit() {
    playbackState.add(PlaybackState(
      controls: const [
        MediaControl.skipToPrevious,
        MediaControl.pause,
        MediaControl.play,
        MediaControl.skipToNext,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.skipToNext,
        MediaAction.skipToPrevious,
      },
      androidCompactActionIndices: const [0, 1, 3],
      processingState: _mapProcessing(_processing),
      playing: _playing,
      updatePosition: _position,
      bufferedPosition: _duration ?? Duration.zero,
      speed: 1.0,
    ));
  }

  AudioProcessingState _mapProcessing(ja.ProcessingState ps) {
    switch (ps) {
      case ja.ProcessingState.idle:
        return AudioProcessingState.idle;
      case ja.ProcessingState.loading:
        return AudioProcessingState.loading;
      case ja.ProcessingState.buffering:
        return AudioProcessingState.buffering;
      case ja.ProcessingState.ready:
        return AudioProcessingState.ready;
      case ja.ProcessingState.completed:
        return AudioProcessingState.completed;
    }
  }

  Future<void> shutdown() async {
    await _stateSub?.cancel();
    await _posSub?.cancel();
    await _durSub?.cancel();
  }
}
