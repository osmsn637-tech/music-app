import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart' as ja;
import 'package:permission_handler/permission_handler.dart';

import '../../core/services/audio_handler.dart';
import '../../data/database/app_database.dart';
import '../../data/database/providers.dart';
import '../../data/repositories/song_repository.dart';
import 'listening_providers.dart';
import 'listening_tracker.dart';
import 'player_service.dart';
import 'providers.dart';

class NowPlayingController extends StateNotifier<SongRow?> {
  NowPlayingController(this._player, this._repo, this._tracker, this._handler)
      : super(null) {
    // Listen for song completion so we can auto-advance through the
    // generic playback queue (library, artist page, etc.). The AI DJ
    // controller handles its own auto-advance against its own queue and
    // suppresses ours by clearing/setting the queue back to a single
    // song when the AI DJ takes over.
    _stateSub = _player.playerStateStream.listen(_onPlayerState);
  }

  final PlayerService _player;
  final SongRepository _repo;
  final ListeningTracker _tracker;
  final AppAudioHandler? _handler;

  /// Generic playback queue populated when the user taps a song in the
  /// library, artist page, playlist detail, etc. Empty when the AI DJ
  /// owns the playhead — the DJ has its own queue + advance loop.
  List<SongRow> _queue = const [];
  int _queueIndex = -1;
  bool _autoAdvancing = false;
  StreamSubscription<ja.PlayerState>? _stateSub;

  bool _notificationPermissionRequested = false;

  bool get hasNext => _queueIndex >= 0 && _queueIndex + 1 < _queue.length;
  bool get hasPrev => _queueIndex > 0;

  /// On Android 13+ the playback notification (and therefore the lockscreen
  /// widget) is gated behind `POST_NOTIFICATIONS`. Ask once on first play.
  Future<void> _ensureNotificationPermission() async {
    if (_notificationPermissionRequested) return;
    _notificationPermissionRequested = true;
    try {
      final status = await Permission.notification.status;
      if (status.isDenied) {
        await Permission.notification.request();
      }
    } catch (_) {
      // Ignore — we don't want a permission failure to block playback.
    }
  }

  /// Plays a single song with no surrounding queue. Used for one-shot
  /// playback (e.g., AI DJ which manages its own queue).
  Future<void> playSong(
    SongRow song, {
    Duration crossfade = Duration.zero,
  }) async {
    _queue = const [];
    _queueIndex = -1;
    await _playInternal(song, crossfade: crossfade);
  }

  /// Plays from a list of songs starting at [startIndex]. Subsequent
  /// next/previous calls — and natural song completion — walk this list.
  Future<void> playFromQueue(
    List<SongRow> queue,
    int startIndex, {
    Duration crossfade = Duration.zero,
  }) async {
    if (queue.isEmpty) return;
    final i = startIndex.clamp(0, queue.length - 1);
    _queue = List.unmodifiable(queue);
    _queueIndex = i;
    await _playInternal(queue[i], crossfade: crossfade);
  }

  /// Advance to the next song in the queue. Returns false when there's
  /// nothing further or no queue is active.
  Future<bool> next() async {
    if (!hasNext) return false;
    _queueIndex += 1;
    await _playInternal(_queue[_queueIndex]);
    return true;
  }

  /// Step back to the previous song in the queue. Returns false when
  /// there's no earlier song or no queue is active.
  Future<bool> previous() async {
    if (!hasPrev) return false;
    _queueIndex -= 1;
    await _playInternal(_queue[_queueIndex]);
    return true;
  }

  Future<void> _playInternal(
    SongRow song, {
    Duration crossfade = Duration.zero,
  }) async {
    await _ensureNotificationPermission();
    state = song;
    // Publish the new MediaItem BEFORE _player.playSong starts. Otherwise
    // the OS notification briefly receives state changes for the new song
    // (loading -> ready -> position resets) while still showing the
    // previous song's metadata, which manifests as the notification being
    // "stuck" on the previous track when one ends and the next begins.
    _handler?.announceSong(song);
    await _tracker.onSongChanged(song);
    await _player.playSong(song, crossfade: crossfade);
    // Re-announce after load so the OS picks up the real duration if the
    // metadata row had it as null.
    _handler?.announceSong(song);
    await _repo.stampPlayed(song.id);
  }

  void _onPlayerState(ja.PlayerState ps) {
    if (ps.processingState != ja.ProcessingState.completed) return;
    if (_queue.isEmpty) return; // No queue → nothing to advance to.
    if (_autoAdvancing) return;
    _autoAdvancing = true;
    next().whenComplete(() => _autoAdvancing = false);
  }

  Future<void> stop() async {
    state = null;
    _queue = const [];
    _queueIndex = -1;
    await _tracker.onSongChanged(null);
    await _player.stop();
  }

  Future<void> resume() => _player.resume();
  Future<void> pause() => _player.pause();
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  void dispose() {
    _stateSub?.cancel();
    super.dispose();
  }
}

final nowPlayingProvider =
    StateNotifierProvider<NowPlayingController, SongRow?>((ref) {
  return NowPlayingController(
    ref.watch(playerServiceProvider),
    ref.watch(songRepositoryProvider),
    ref.watch(listeningTrackerProvider),
    ref.watch(audioHandlerProvider),
  );
});
