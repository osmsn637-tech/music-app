import 'dart:async';
import 'dart:io';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../../data/database/app_database.dart';
import '../../main.dart' show audioBackgroundReady, audioBackgroundInitError;

/// Two-deck audio engine supporting hard cuts (Library / Search direct
/// plays) and crossfaded transitions (AI DJ queue). The "active" deck is
/// the one user-facing controls (pause / resume / seek) operate on, and
/// the one whose streams (position, duration, state) propagate outward.
/// During a crossfade, both decks play simultaneously; activeness flips
/// at the start of the fade so the UI immediately reflects the new song.
class PlayerService {
  PlayerService(this._playerA, this._playerB) {
    _bindStreamsToActive();
  }

  final AudioPlayer _playerA;
  final AudioPlayer _playerB;
  bool _aActive = true;
  bool _sessionConfigured = false;

  AudioPlayer get _active => _aActive ? _playerA : _playerB;
  AudioPlayer get _idle => _aActive ? _playerB : _playerA;

  /// The active player exposed for direct access (used by tests + a few
  /// places that subscribe to specific streams).
  AudioPlayer get raw => _active;

  // --- proxy streams (always emit from the active deck) -----------------

  final _stateCtrl = StreamController<PlayerState>.broadcast();
  final _posCtrl = StreamController<Duration>.broadcast();
  final _durCtrl = StreamController<Duration?>.broadcast();

  StreamSubscription<PlayerState>? _stateSub;
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<Duration?>? _durSub;

  Stream<PlayerState> get playerStateStream => _stateCtrl.stream;
  Stream<Duration> get positionStream => _posCtrl.stream;
  Stream<Duration?> get durationStream => _durCtrl.stream;

  void _bindStreamsToActive() {
    _stateSub?.cancel();
    _posSub?.cancel();
    _durSub?.cancel();
    final a = _active;
    _stateSub = a.playerStateStream.listen(_stateCtrl.add);
    _posSub = a.positionStream.listen(_posCtrl.add);
    _durSub = a.durationStream.listen(_durCtrl.add);
  }

  // --- crossfade state --------------------------------------------------

  Timer? _fadeTimer;

  Future<void> _ensureSession() async {
    if (_sessionConfigured) return;
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
    _sessionConfigured = true;
  }

  /// Plays [song]. With [crossfade] zero (default), behaves like the
  /// classic single-player playback: stops everything, loads on the
  /// active deck, plays. With [crossfade] > 0, loads on the idle deck,
  /// flips activeness, ramps volumes for [crossfade] duration so the
  /// outgoing song fades out as the new one fades in.
  Future<void> playSong(
    SongRow song, {
    Duration crossfade = Duration.zero,
  }) async {
    if (!audioBackgroundReady) {
      throw StateError(
        'Audio background plugin failed to initialize'
        '${audioBackgroundInitError == null ? '' : ': $audioBackgroundInitError'}'
        '. Restart the app; if it persists, check flutter logs for '
        '"[audio] JustAudioBackground.init FAILED".',
      );
    }
    await _ensureSession();
    final file = File(song.localFilePath);
    if (!await file.exists()) {
      debugPrint(
        'PlayerService: file missing for "${song.title}" at '
        '${song.localFilePath}',
      );
      throw StateError('Song file missing: ${song.localFilePath}');
    }
    final size = await file.length();
    if (size == 0) {
      debugPrint(
        'PlayerService: zero-byte file for "${song.title}" at '
        '${song.localFilePath}',
      );
      throw StateError('Song file is empty: ${song.localFilePath}');
    }
    debugPrint(
      '[player] playSong "${song.title}" crossfade=${crossfade.inMilliseconds}ms '
      'aActive=$_aActive',
    );
    if (crossfade <= Duration.zero) {
      _fadeTimer?.cancel();
      // Stop the idle deck if it's tailing from a prior fade, but DON'T
      // setVolume on it — touching the idle deck's volume before its
      // AudioTrack exists confuses just_audio's Android plugin and the
      // wrong track ends up muted.
      await _idle.stop();
      await _active.stop();
      await _setSourceOn(_active, file, size);
      // Setting volume must come AFTER setAudioSource creates the platform
      // AudioTrack. Otherwise the call lands in nowhere and the track is
      // born at whatever default volume — which has been observed to be 0.
      await _active.setVolume(1.0);
      await _active.play();
      debugPrint('[player] hard-cut: active volume set to 1.0, play() called');
      return;
    }

    // Crossfade path: prep idle deck, swap activeness, ramp.
    // Same rule as above: setVolume must come after setAudioSource so
    // the AudioTrack exists when the volume is dialed in.
    final outgoing = _active;
    final incoming = _idle;
    _fadeTimer?.cancel();
    await _setSourceOn(incoming, file, size);
    await incoming.setVolume(0.0);
    await incoming.play();
    _aActive = !_aActive; // incoming is now "active"
    _bindStreamsToActive();
    debugPrint('[player] crossfade: incoming source loaded, ramping up over '
        '${crossfade.inMilliseconds}ms');

    final stepMs = 50;
    final totalMs = crossfade.inMilliseconds;
    final stepCount = (totalMs / stepMs).round().clamp(1, 1000);
    var step = 0;
    final outgoingStartingVol = outgoing.volume.clamp(0.0, 1.0);
    _fadeTimer = Timer.periodic(Duration(milliseconds: stepMs), (t) async {
      step += 1;
      final p = (step / stepCount).clamp(0.0, 1.0);
      try {
        await incoming.setVolume(p);
        await outgoing.setVolume(outgoingStartingVol * (1.0 - p));
      } catch (_) {
        // setVolume can throw if the player was disposed mid-fade.
        t.cancel();
        return;
      }
      if (p >= 1.0) {
        t.cancel();
        try {
          await outgoing.stop();
          await outgoing.setVolume(1.0);
        } catch (_) {}
      }
    });
  }

  /// Ducks the currently-outgoing deck to [level] (0..1) immediately. Used
  /// for DJ talkover so spoken commentary rides over the previous track's
  /// tail without competing at full volume. The next [playSong] call
  /// resumes from this volume during its crossfade ramp.
  ///
  /// Sets volume on BOTH decks because we've seen Android cases where a
  /// just_audio AudioPlayer's setVolume call lands on the platform side
  /// after a deck swap, leaving the wrong track audible. Setting both is
  /// idempotent for the silent deck and harmless for the active one.
  Future<void> duckOutgoing(double level) async {
    final clamped = level.clamp(0.0, 1.0);
    debugPrint('[player] duckOutgoing → $clamped (aActive=$_aActive)');
    try {
      await _playerA.setVolume(clamped);
      await _playerB.setVolume(clamped);
    } catch (e) {
      debugPrint('[player] duckOutgoing failed: $e');
    }
  }

  Future<void> _setSourceOn(AudioPlayer p, File file, int size) async {
    try {
      await p.setAudioSource(AudioSource.uri(file.uri));
    } catch (e, st) {
      debugPrint(
        'PlayerService: setAudioSource failed '
        '(${size}B at ${file.path}): $e\n$st',
      );
      rethrow;
    }
  }

  Future<void> resume() => _active.play();
  Future<void> pause() => _active.pause();
  Future<void> stop() async {
    _fadeTimer?.cancel();
    await _idle.stop();
    await _active.stop();
  }

  Future<void> seek(Duration position) => _active.seek(position);

  Future<void> dispose() async {
    _fadeTimer?.cancel();
    await _stateSub?.cancel();
    await _posSub?.cancel();
    await _durSub?.cancel();
    await _stateCtrl.close();
    await _posCtrl.close();
    await _durCtrl.close();
    await _playerA.dispose();
    await _playerB.dispose();
  }
}
