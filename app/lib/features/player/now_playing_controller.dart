import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/services/audio_handler.dart';
import '../../data/database/app_database.dart';
import '../../data/database/providers.dart';
import '../../data/repositories/song_repository.dart';
import '../automix/automix_service.dart';
import '../automix/providers.dart';
import '../library/detail_providers.dart';
import 'listening_providers.dart';
import 'listening_tracker.dart';
import 'playback_modes.dart';
import 'playback_persistence.dart';
import 'player_service.dart';
import 'providers.dart';

/// Reactive snapshot of the playback queue for the Up-Next view.
typedef QueueView = ({List<SongRow> queue, int index});

class NowPlayingController extends StateNotifier<SongRow?> {
  NowPlayingController(
    this._ref,
    this._player,
    this._repo,
    this._tracker,
    this._handler,
    this._modes,
  ) : super(null) {
    _stateSub = _player.playerStateStream.listen(_onPlayerState);
    _posSub = _player.positionStream.listen(_onPosition);
    _durSub = _player.durationStream.listen(_onDuration);
  }

  final Ref _ref;
  final PlayerService _player;
  final SongRepository _repo;
  final ListeningTracker _tracker;
  final AppAudioHandler? _handler;
  final PlaybackModesController _modes;

  /// The active play order (what next/prev/auto-advance walk). When
  /// shuffle is on this is a shuffled view; [_originalQueue] keeps the
  /// untouched order so toggling shuffle off restores it.
  List<SongRow> _queue = [];
  List<SongRow> _originalQueue = [];
  int _queueIndex = -1;
  bool _autoAdvancing = false;

  /// Reactive mirror of the queue for the Up-Next sheet.
  final ValueNotifier<QueueView> queueView = ValueNotifier<QueueView>((
    queue: const [],
    index: -1,
  ));

  StreamSubscription<PlayerSnapshot>? _stateSub;
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<Duration?>? _durSub;

  // Lead time before a track ends to begin the hand-off. A real AutoMix
  // blend needs a long overlap so the incoming track plays *under* the
  // outgoing one and they cross seamlessly; the plain linear crossfade
  // (AutoMix off) stays short. Chosen per-track in [_onDuration].
  static const Duration _blendWindow = Duration(seconds: 10);
  static const Duration _crossfadeWindow = Duration(seconds: 4);
  Duration get _autoMixWindow =>
      _ref.read(autoMixEnabledProvider) ? _blendWindow : _crossfadeWindow;

  Duration? _autoMixAt;
  bool _autoMixFired = false;
  Duration _lastPos = Duration.zero;

  final PlaybackStateStore _store = PlaybackStateStore();
  int _lastPersistMs = 0;

  bool _notificationPermissionRequested = false;

  bool get hasNext => _queueIndex >= 0 && _queueIndex + 1 < _queue.length;
  bool get hasPrev => _queueIndex > 0;

  void _publishQueue() {
    queueView.value = (queue: List.unmodifiable(_queue), index: _queueIndex);
    _persist();
  }

  void _persist() {
    if (_queue.isEmpty) {
      _store.clear();
      return;
    }
    _store.save(
      PlaybackSnapshot(
        queueIds: _queue.map((s) => s.id).toList(),
        index: _queueIndex,
        positionMs: _lastPos.inMilliseconds,
        shuffle: _modes.state.shuffle,
        repeat: _modes.state.repeat,
      ),
    );
  }

  /// Restore the previous session (queue + current song + position +
  /// modes), staged PAUSED so the app comes up where the user left off
  /// without auto-blasting audio. No-op once anything is already loaded.
  Future<void> restoreSession() async {
    if (state != null || _queue.isNotEmpty) return;
    final snap = await _store.load();
    if (snap == null || snap.queueIds.isEmpty) return;
    final rows = <SongRow>[];
    for (final id in snap.queueIds) {
      final r = await _repo.findById(id);
      if (r != null) rows.add(r);
    }
    if (rows.isEmpty) return;
    _modes.restore(shuffle: snap.shuffle, repeat: snap.repeat);
    _queue = rows;
    _originalQueue = List.of(rows);
    _queueIndex = snap.index.clamp(0, rows.length - 1);
    final song = _queue[_queueIndex];
    state = song;
    _handler?.announceSong(song);
    queueView.value = (queue: List.unmodifiable(_queue), index: _queueIndex);
    try {
      await _player.prepare(song, at: Duration(milliseconds: snap.positionMs));
    } catch (_) {
      // File missing / engine not ready — leave it staged; the user can
      // re-tap to start it.
    }
  }

  /// Adopt a playback session handed off from another device via Live
  /// Connect. Resolves the queue by id against the local library, restores
  /// shuffle/repeat (no reshuffle — the incoming order already encodes it),
  /// then either starts playing at [positionMs] or stages it paused. Songs
  /// not present locally are skipped; the current track is located by id so a
  /// missing earlier song doesn't shift the index.
  Future<void> adoptRemote({
    required List<String> queueIds,
    required int index,
    required int positionMs,
    required bool shuffle,
    required QueueRepeatMode repeat,
    required bool play,
  }) async {
    final rows = <SongRow>[];
    for (final id in queueIds) {
      final r = await _repo.findById(id);
      if (r != null) rows.add(r);
    }
    if (rows.isEmpty) return;
    _modes.restore(shuffle: shuffle, repeat: repeat);
    _queue = rows;
    _originalQueue = List.of(rows);
    final curId = (index >= 0 && index < queueIds.length)
        ? queueIds[index]
        : null;
    _queueIndex = curId == null ? 0 : rows.indexWhere((r) => r.id == curId);
    if (_queueIndex < 0) _queueIndex = index.clamp(0, rows.length - 1);
    final song = _queue[_queueIndex];
    state = song;
    _handler?.announceSong(song);
    queueView.value = (queue: List.unmodifiable(_queue), index: _queueIndex);
    final at = Duration(milliseconds: positionMs);
    if (play) {
      await _playInternal(song);
      await _player.seek(at);
    } else {
      try {
        await _player.prepare(song, at: at);
      } catch (_) {
        // File missing / engine not ready — leave staged; commit can retry.
      }
    }
  }

  Future<void> _ensureNotificationPermission() async {
    if (_notificationPermissionRequested) return;
    _notificationPermissionRequested = true;
    try {
      final status = await Permission.notification.status;
      if (status.isDenied) {
        await Permission.notification.request();
      }
    } catch (_) {
      // Ignore — a permission failure shouldn't block playback.
    }
  }

  /// Plays a single song with no surrounding queue (e.g. AI DJ, which
  /// manages its own queue).
  Future<void> playSong(
    SongRow song, {
    Duration crossfade = Duration.zero,
  }) async {
    _queue = [];
    _originalQueue = [];
    _queueIndex = -1;
    _publishQueue();
    await _playInternal(song, crossfade: crossfade);
  }

  /// Plays from a list of songs starting at [startIndex]. Honours the
  /// current shuffle mode — when shuffle is on the tapped song plays
  /// first and the rest are shuffled behind it.
  Future<void> playFromQueue(
    List<SongRow> queue,
    int startIndex, {
    Duration crossfade = Duration.zero,
  }) async {
    if (queue.isEmpty) return;
    final i = startIndex.clamp(0, queue.length - 1);
    _originalQueue = List.of(queue);
    if (_modes.state.shuffle) {
      final current = queue[i];
      final rest = [...queue]..removeAt(i);
      rest.shuffle();
      _queue = [current, ...rest];
      _queueIndex = 0;
    } else {
      _queue = List.of(queue);
      _queueIndex = i;
    }
    _publishQueue();
    await _playInternal(_queue[_queueIndex], crossfade: crossfade);
  }

  /// Advance to the next song. At the end, wraps when repeat-all is on,
  /// otherwise stops. User-initiated → hard cut.
  Future<bool> next() async {
    _autoMixAt = null;
    _autoMixFired = true;
    if (hasNext) {
      _queueIndex += 1;
    } else if (_modes.state.repeat == QueueRepeatMode.all &&
        _queue.isNotEmpty) {
      _queueIndex = 0;
    } else if (_modes.state.endless && _maybeExtendQueue()) {
      // _maybeExtendQueue already moved _queueIndex onto the next track.
    } else {
      return false;
    }
    _publishQueue();
    await _playInternal(_queue[_queueIndex]);
    return true;
  }

  /// Toggle "infinity": an endless queue that auto-continues with another
  /// album by the same artist when it runs out. Turning it ON while sitting
  /// at the tail tops the queue up immediately so the Up-Next list fills.
  void toggleEndless() {
    _modes.toggleEndless();
    if (_modes.state.endless && !hasNext && _queue.isNotEmpty) {
      final idx = _queueIndex.clamp(0, _queue.length - 1);
      final artist = _queue[idx].artist?.trim() ?? '';
      if (artist.isNotEmpty && _appendSameArtistAlbum(artist) > 0) {
        _publishQueue();
      }
    }
  }

  /// Endless continuation at end-of-queue: append the next same-artist album
  /// (moving the index onto its first track), or — if none is left — wrap to
  /// the start so playback genuinely never ends. Returns true when it left
  /// [_queueIndex] on a playable track. Only acts when infinity is on.
  bool _maybeExtendQueue() {
    if (!_modes.state.endless || _queue.isEmpty) return false;
    final idx = _queueIndex.clamp(0, _queue.length - 1);
    final artist = _queue[idx].artist?.trim() ?? '';
    final n = artist.isEmpty ? 0 : _appendSameArtistAlbum(artist);
    if (n > 0) {
      _queueIndex = _queue.length - n; // first of the freshly-appended album
    } else {
      _queueIndex = 0; // no fresh album → wrap so it never stops
    }
    _publishQueue();
    return true;
  }

  /// Appends the first album by [artist] that isn't already in the queue
  /// (de-duped by album key + song id). Returns the number of songs added.
  /// Reads the in-memory library (no DB round-trip), so it's synchronous.
  int _appendSameArtistAlbum(String artist) {
    final songs =
        _ref.read(songsByArtistProvider(artist)).valueOrNull ??
        const <SongRow>[];
    if (songs.isEmpty) return 0;
    final usedAlbums = <String>{
      for (final s in _queue)
        if (s.album != null && s.album!.trim().isNotEmpty)
          normalizeAlbumKey(s.album!),
    };
    final existingIds = _queue.map((s) => s.id).toSet();
    final byAlbum = <String, List<SongRow>>{};
    for (final s in songs) {
      if (s.album == null || s.album!.trim().isEmpty) continue;
      byAlbum.putIfAbsent(normalizeAlbumKey(s.album!), () => []).add(s);
    }
    for (final entry in byAlbum.entries) {
      if (usedAlbums.contains(entry.key)) continue;
      final picked = entry.value
          .where((s) => !existingIds.contains(s.id))
          .toList();
      if (picked.isEmpty) continue;
      _queue.addAll(picked);
      _originalQueue.addAll(picked);
      return picked.length;
    }
    return 0;
  }

  /// Previous: restart the current track if we're more than 3s in (the
  /// universal "double-tap to go back" behaviour), otherwise step back.
  Future<bool> previous() async {
    _autoMixAt = null;
    _autoMixFired = true;
    if (_lastPos > const Duration(seconds: 3) || !hasPrev) {
      await _player.seek(Duration.zero);
      return true;
    }
    _queueIndex -= 1;
    _publishQueue();
    await _playInternal(_queue[_queueIndex]);
    return true;
  }

  /// Jump straight to a queue entry (tap in the Up-Next list).
  Future<void> jumpTo(int index) async {
    if (index < 0 || index >= _queue.length) return;
    _autoMixAt = null;
    _autoMixFired = true;
    _queueIndex = index;
    _publishQueue();
    await _playInternal(_queue[index]);
  }

  // ─── Queue editing ──────────────────────────────────────────────────

  /// Insert [song] right after the current track.
  void playNext(SongRow song) {
    if (_queue.isEmpty) {
      final cur = state;
      if (cur == null) {
        playSong(song);
        return;
      }
      _queue = [cur, song];
      _originalQueue = [cur, song];
      _queueIndex = 0;
    } else {
      _queue.insert(_queueIndex + 1, song);
      final curId = _queue[_queueIndex].id;
      final oi = _originalQueue.indexWhere((s) => s.id == curId);
      _originalQueue.insert(oi < 0 ? _originalQueue.length : oi + 1, song);
    }
    _publishQueue();
  }

  /// Append [song] to the end of the queue.
  void addToQueue(SongRow song) {
    if (_queue.isEmpty) {
      final cur = state;
      if (cur == null) {
        playSong(song);
        return;
      }
      _queue = [cur, song];
      _originalQueue = [cur, song];
      _queueIndex = 0;
    } else {
      _queue.add(song);
      _originalQueue.add(song);
    }
    _publishQueue();
  }

  void removeFromQueue(int index) {
    if (index < 0 || index >= _queue.length) return;
    if (index == _queueIndex) return; // don't yank the playing track
    final removed = _queue.removeAt(index);
    _originalQueue.removeWhere((s) => s.id == removed.id);
    if (index < _queueIndex) _queueIndex -= 1;
    _publishQueue();
  }

  void reorderQueue(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= _queue.length) return;
    final curId = (_queueIndex >= 0 && _queueIndex < _queue.length)
        ? _queue[_queueIndex].id
        : null;
    // ReorderableListView reports newIndex as the slot *after* removal.
    var target = newIndex;
    if (target > oldIndex) target -= 1;
    final item = _queue.removeAt(oldIndex);
    _queue.insert(target.clamp(0, _queue.length), item);
    if (curId != null) {
      final ni = _queue.indexWhere((s) => s.id == curId);
      if (ni >= 0) _queueIndex = ni;
    }
    // Shuffle order is throwaway; only keep the canonical order in sync
    // when not shuffled.
    if (!_modes.state.shuffle) _originalQueue = List.of(_queue);
    _publishQueue();
  }

  // ─── Modes ──────────────────────────────────────────────────────────

  void toggleShuffle() {
    _modes.toggleShuffle();
    _reshuffle();
  }

  void cycleRepeat() => _modes.cycleRepeat();

  void _reshuffle() {
    if (_queue.isEmpty) return;
    final current = (_queueIndex >= 0 && _queueIndex < _queue.length)
        ? _queue[_queueIndex]
        : null;
    if (_modes.state.shuffle) {
      final rest = [..._originalQueue];
      if (current != null) rest.removeWhere((s) => s.id == current.id);
      rest.shuffle();
      _queue = [?current, ...rest];
      _queueIndex = 0;
    } else {
      _queue = List.of(_originalQueue);
      _queueIndex = current == null
          ? 0
          : _queue.indexWhere((s) => s.id == current.id);
      if (_queueIndex < 0) _queueIndex = 0;
    }
    _publishQueue();
  }

  // ─── Auto-mix / auto-advance ────────────────────────────────────────

  void _onPosition(Duration pos) {
    _lastPos = pos;
    // Persist position roughly every 5s so a relaunch resumes near the
    // spot without thrashing prefs on every 60ms tick.
    final ms = pos.inMilliseconds;
    if ((ms - _lastPersistMs).abs() >= 5000) {
      _lastPersistMs = ms;
      _persist();
    }
    if (_autoMixFired) return;
    if (_autoAdvancing) return;
    if (_queue.isEmpty) return;
    if (_modes.state.repeat == QueueRepeatMode.one) return;
    if (!hasNext) return;
    final t = _autoMixAt;
    if (t == null) return;
    if (pos < t) return;
    _autoMixFired = true;
    _autoAdvancing = true;
    _queueIndex += 1;
    _publishQueue();
    _playInternal(
      _queue[_queueIndex],
      crossfade: _autoMixWindow,
    ).whenComplete(() => _autoAdvancing = false);
  }

  void _onDuration(Duration? d) {
    _autoMixAt = null;
    _autoMixFired = false;
    if (d == null || d == Duration.zero) return;
    if (d <= _autoMixWindow * 2) return;
    _autoMixAt = d - _autoMixWindow;
    // When AutoMix is on, move the trigger earlier — to the outgoing's natural
    // outro — so the blend starts as soon as the music allows ("whenever
    // possible") rather than a fixed window before the end.
    unawaited(_refineAutoMixStart(d));
  }

  Future<void> _refineAutoMixStart(Duration d) async {
    if (!_ref.read(autoMixEnabledProvider)) return;
    final current = state;
    if (current == null || !hasNext) return;
    final next = _queue[_queueIndex + 1];
    try {
      final svc = await _ref.read(autoMixServiceProvider.future);
      final mixOut = await svc.plannedMixOutSec(current: current, next: next);
      if (mixOut == null) return;
      // bail if the track changed under us or the mix already fired
      if (state?.id != current.id || _autoMixFired) return;
      final at = Duration(milliseconds: (mixOut * 1000).round());
      // only ever move the trigger EARLIER, and never behind the playhead
      if (at < (_autoMixAt ?? d) && at > _lastPos) {
        _autoMixAt = at;
      }
    } catch (_) {
      // analysis missing / engine not ready — keep the fixed-window trigger
    }
  }

  Future<void> _playInternal(
    SongRow song, {
    Duration crossfade = Duration.zero,
  }) async {
    await _ensureNotificationPermission();
    final outgoing = state; // capture BEFORE we flip to the incoming track
    state = song;
    _handler?.announceSong(song);
    await _tracker.onSongChanged(song);
    try {
      // On the pre-emptive auto-advance path (crossfade > 0), when Automix is
      // enabled and both tracks have analysis, run the beat-matched AutoMix
      // transition instead of the simple linear crossfade. mixToNext() loads
      // and starts the incoming deck itself, so we skip playSong when it took
      // over. Any other outcome (no sidecar / disabled / failed) falls back to
      // the original crossfade — seamless degradation.
      var mixed = false;
      if (crossfade > Duration.zero &&
          outgoing != null &&
          _ref.read(autoMixEnabledProvider)) {
        final svc = await _ref.read(autoMixServiceProvider.future);
        // Flag the live blend so the UI can glow the progress bar + say
        // "Mixing" for exactly the transition's duration.
        _ref.read(autoMixMixingProvider.notifier).state = true;
        try {
          final outcome = await svc.mixToNext(current: outgoing, next: song);
          mixed = outcome == AutoMixOutcome.mixed;
        } finally {
          _ref.read(autoMixMixingProvider.notifier).state = false;
        }
      }
      if (!mixed) {
        await _player.playSong(song, crossfade: crossfade);
      }
    } catch (_) {
      // Missing / unplayable file — skip past it instead of dying so a
      // single bad track doesn't stall the whole queue.
      if (hasNext) unawaited(Future.microtask(next));
      return;
    }
    _handler?.announceSong(song);
    await _repo.stampPlayed(song.id);
  }

  void _onPlayerState(PlayerSnapshot ps) {
    if (ps.processingState != PlayerProcessingState.completed) return;
    if (_queue.isEmpty) return;
    if (_autoAdvancing) return;
    if (_autoMixFired) return;
    _autoAdvancing = true;
    _advanceOnComplete().whenComplete(() => _autoAdvancing = false);
  }

  Future<void> _advanceOnComplete() async {
    final repeat = _modes.state.repeat;
    if (repeat == QueueRepeatMode.one) {
      await _playInternal(_queue[_queueIndex]);
      return;
    }
    if (hasNext) {
      _queueIndex += 1;
      _publishQueue();
      await _playInternal(_queue[_queueIndex]);
      return;
    }
    if (repeat == QueueRepeatMode.all && _queue.isNotEmpty) {
      _queueIndex = 0;
      _publishQueue();
      await _playInternal(_queue[_queueIndex]);
      return;
    }
    if (_modes.state.endless && _maybeExtendQueue()) {
      // Infinity: continued with another same-artist album (or wrapped). The
      // first cross into a freshly-appended album is a hard cut, not gapless
      // (the append is lazy at end-of-track) — acceptable for v1.
      await _playInternal(_queue[_queueIndex]);
      return;
    }
    // repeat off + queue ended (and not endless) → stop advancing.
  }

  Future<void> stop() async {
    state = null;
    _queue = [];
    _originalQueue = [];
    _queueIndex = -1;
    _publishQueue();
    await _tracker.onSongChanged(null);
    await _player.stop();
  }

  Future<void> resume() => _player.resume();
  Future<void> pause() => _player.pause();
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  void dispose() {
    _stateSub?.cancel();
    _posSub?.cancel();
    _durSub?.cancel();
    queueView.dispose();
    super.dispose();
  }
}

final nowPlayingProvider =
    StateNotifierProvider<NowPlayingController, SongRow?>((ref) {
      return NowPlayingController(
        ref,
        ref.watch(playerServiceProvider),
        ref.watch(songRepositoryProvider),
        ref.watch(listeningTrackerProvider),
        ref.watch(audioHandlerProvider),
        ref.watch(playbackModesProvider.notifier),
      );
    });
