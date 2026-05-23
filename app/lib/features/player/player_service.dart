import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_soloud/flutter_soloud.dart';

import '../../data/database/app_database.dart';
import '../../main.dart' show audioBackgroundReady, audioBackgroundInitError;

/// Lightweight player-state enum the rest of the app uses in place of
/// `just_audio`'s `ProcessingState`. Kept here so swapping the underlying
/// engine never leaks past this file.
enum PlayerProcessingState { idle, loading, ready, completed }

/// Snapshot of the active deck's state. Mirrors the shape of just_audio's
/// `PlayerState` (a `playing` bool + a processing enum) so call sites
/// migrated cleanly.
class PlayerSnapshot {
  const PlayerSnapshot({required this.playing, required this.processingState});

  final bool playing;
  final PlayerProcessingState processingState;

  PlayerSnapshot copyWith({
    bool? playing,
    PlayerProcessingState? processingState,
  }) {
    return PlayerSnapshot(
      playing: playing ?? this.playing,
      processingState: processingState ?? this.processingState,
    );
  }
}

/// Two-source audio engine on top of `flutter_soloud`. Mirrors the shape
/// of the previous `just_audio`-backed PlayerService — one "active" deck
/// drives UI streams, an "idle" deck preloads for crossfades — but uses
/// soloud's mixer (any number of sounds can play in parallel, each with
/// its own handle and volume) instead of two `AudioPlayer` instances.
///
/// Why soloud:
/// 1. Exposes a live FFT off the mix without a Visualizer-API permission
///    dance, so the fluid background can react to actual bass.
/// 2. Cleaner overlapping playback for the AI-DJ crossfade.
class PlayerService {
  PlayerService({SoLoud? soloud}) : _soloud = soloud ?? SoLoud.instance {
    // SoLoud exposes audio analysis through an AudioData buffer the
    // consumer owns and ticks. We initialise it in `linear` mode so a
    // single getAudioData() call returns 256 FFT bins followed by 256
    // waveform samples, which is what readBassLevel() consumes.
    _audioData = AudioData(GetSamplesKind.linear);
  }

  final SoLoud _soloud;
  late final AudioData _audioData;

  // Two deck slots. Each can hold an AudioSource (the loaded file) and a
  // SoundHandle (a currently-playing voice on that source).
  AudioSource? _sourceA;
  AudioSource? _sourceB;
  SoundHandle? _handleA;
  SoundHandle? _handleB;
  Duration? _durationA;
  Duration? _durationB;

  // Subscription to the AudioSource's `allInstancesFinished` event, used
  // to flip processing state → completed for the active deck.
  StreamSubscription<void>? _finishedSubA;
  StreamSubscription<void>? _finishedSubB;

  bool _aActive = true;
  bool _sessionConfigured = false;

  SoundHandle? get _activeHandle => _aActive ? _handleA : _handleB;
  AudioSource? get _activeSource => _aActive ? _sourceA : _sourceB;
  Duration? get _activeDuration => _aActive ? _durationA : _durationB;

  // --- Outward streams -------------------------------------------------
  // We synthesise these ourselves: soloud doesn't broadcast position
  // changes, and its play/pause is a flag we maintain locally.

  final _stateCtrl = StreamController<PlayerSnapshot>.broadcast();
  final _posCtrl = StreamController<Duration>.broadcast();
  final _durCtrl = StreamController<Duration?>.broadcast();

  Timer? _posPoll;
  PlayerSnapshot _state = const PlayerSnapshot(
    playing: false,
    processingState: PlayerProcessingState.idle,
  );

  Stream<PlayerSnapshot> get playerStateStream => _stateCtrl.stream;
  Stream<Duration> get positionStream => _posCtrl.stream;
  Stream<Duration?> get durationStream => _durCtrl.stream;
  PlayerSnapshot get state => _state;

  void _emitState(PlayerSnapshot next) {
    _state = next;
    _stateCtrl.add(next);
  }

  void _startPositionPolling() {
    _posPoll?.cancel();
    _posPoll = Timer.periodic(const Duration(milliseconds: 60), (_) {
      final h = _activeHandle;
      if (h == null) return;
      try {
        if (!_soloud.getIsValidVoiceHandle(h)) return;
        final pos = _soloud.getPosition(h);
        _posCtrl.add(pos);
      } catch (_) {
        // Handle was invalidated mid-poll (rare); next tick recovers.
      }
    });
  }

  void _stopPositionPolling() {
    _posPoll?.cancel();
    _posPoll = null;
  }

  // --- AI-DJ crossfade --------------------------------------------------

  Timer? _fadeTimer;

  Future<void> _ensureSession() async {
    if (_sessionConfigured) return;
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());
      _sessionConfigured = true;
    } catch (e) {
      debugPrint('[player] AudioSession configure failed: $e');
    }
  }

  /// Play [song]. With [crossfade] = 0, hard-cuts: stop everything, load
  /// on the active deck, start playback. With [crossfade] > 0, preload
  /// on the idle deck, swap activeness, then ramp volumes over the fade
  /// duration so the outgoing track tails off while the new one rises.
  Future<void> playSong(
    SongRow song, {
    Duration crossfade = Duration.zero,
  }) async {
    if (!audioBackgroundReady) {
      throw StateError(
        'Audio engine not initialised'
        '${audioBackgroundInitError == null ? '' : ': $audioBackgroundInitError'}'
        '. Restart the app; if it persists, check flutter logs for '
        '"[audio] SoLoud.init FAILED".',
      );
    }
    await _ensureSession();

    final file = File(song.localFilePath);
    if (!await file.exists()) {
      debugPrint(
        '[player] file missing for "${song.title}" at ${song.localFilePath}',
      );
      throw StateError('Song file missing: ${song.localFilePath}');
    }
    final size = await file.length();
    if (size == 0) {
      throw StateError('Song file is empty: ${song.localFilePath}');
    }

    debugPrint(
      '[player] playSong "${song.title}" crossfade=${crossfade.inMilliseconds}ms '
      'aActive=$_aActive',
    );

    // Show loading state immediately so the UI's spinner appears even
    // before soloud finishes loading the file.
    _emitState(_state.copyWith(processingState: PlayerProcessingState.loading));

    if (crossfade <= Duration.zero) {
      _fadeTimer?.cancel();
      await _stopAndUnloadAll();
      final loaded = await _loadAndPlay(file.path, onActive: true, volume: 1.0);
      _startPositionPolling();
      _durCtrl.add(loaded);
      _emitState(const PlayerSnapshot(
        playing: true,
        processingState: PlayerProcessingState.ready,
      ));
      return;
    }

    // Crossfade path. Load on the idle deck, then swap activeness so
    // outward streams immediately reflect the incoming track.
    _fadeTimer?.cancel();
    final outgoingHandle = _activeHandle;
    final loaded = await _loadAndPlay(
      file.path,
      onActive: false, // load onto idle deck
      volume: 0.0,
    );
    _aActive = !_aActive; // incoming is now "active"
    _startPositionPolling();
    _durCtrl.add(loaded);
    _emitState(const PlayerSnapshot(
      playing: true,
      processingState: PlayerProcessingState.ready,
    ));

    const stepMs = 50;
    final totalMs = crossfade.inMilliseconds;
    final stepCount = (totalMs / stepMs).round().clamp(1, 1000);
    var step = 0;
    final incoming = _activeHandle;
    if (incoming == null) return;

    final outgoingStartVol = (outgoingHandle != null
        ? _safeGetVolume(outgoingHandle)
        : 1.0);
    _fadeTimer = Timer.periodic(const Duration(milliseconds: stepMs), (t) {
      step += 1;
      final p = (step / stepCount).clamp(0.0, 1.0);
      try {
        _soloud.setVolume(incoming, p);
        if (outgoingHandle != null) {
          _soloud.setVolume(outgoingHandle, outgoingStartVol * (1.0 - p));
        }
      } catch (_) {
        t.cancel();
        return;
      }
      if (p >= 1.0) {
        t.cancel();
        // Stop + unload the outgoing handle/source now that the fade
        // is complete. The slot stays free for the next preload.
        if (outgoingHandle != null) {
          _safeStop(outgoingHandle);
        }
        _unloadIdleSource();
      }
    });
  }

  /// Duck both decks to [level]. Used by AI-DJ talkover so commentary
  /// rides over the outgoing track's tail. Both decks are set because in
  /// practice volume calls have raced deck swaps; setting both is
  /// idempotent for the silent deck and harmless for the active one.
  Future<void> duckOutgoing(double level) async {
    final clamped = level.clamp(0.0, 1.0);
    debugPrint('[player] duckOutgoing → $clamped (aActive=$_aActive)');
    final hA = _handleA;
    final hB = _handleB;
    try {
      if (hA != null) _soloud.setVolume(hA, clamped);
      if (hB != null) _soloud.setVolume(hB, clamped);
    } catch (e) {
      debugPrint('[player] duckOutgoing failed: $e');
    }
  }

  Future<void> resume() async {
    final h = _activeHandle;
    if (h == null) return;
    _soloud.setPause(h, false);
    _emitState(_state.copyWith(playing: true));
  }

  Future<void> pause() async {
    final h = _activeHandle;
    if (h == null) return;
    _soloud.setPause(h, true);
    _emitState(_state.copyWith(playing: false));
  }

  Future<void> stop() async {
    _fadeTimer?.cancel();
    _stopPositionPolling();
    await _stopAndUnloadAll();
    _emitState(const PlayerSnapshot(
      playing: false,
      processingState: PlayerProcessingState.idle,
    ));
  }

  Future<void> seek(Duration position) async {
    final h = _activeHandle;
    if (h == null) return;
    _soloud.seek(h, position);
    _posCtrl.add(position);
  }

  // --- Helpers ---------------------------------------------------------

  Future<Duration?> _loadAndPlay(
    String path, {
    required bool onActive,
    required double volume,
  }) async {
    final source = await _soloud.loadFile(path);
    final duration = _soloud.getLength(source);
    final handle = await _soloud.play(source, volume: volume);

    final finishedSub = source.allInstancesFinished.listen((_) {
      // Only flip to completed if THIS handle was still the active one
      // when its source finished. Otherwise it's the outgoing-from-
      // crossfade handle and shouldn't change UI state.
      final stillActive = onActive == _aActive
          ? (onActive ? handle == _handleA : handle == _handleB)
          : false;
      if (stillActive) {
        _emitState(_state.copyWith(
          playing: false,
          processingState: PlayerProcessingState.completed,
        ));
      }
    });

    if (onActive == true) {
      if (_aActive) {
        await _disposeDeckA();
        _sourceA = source;
        _handleA = handle;
        _durationA = duration;
        _finishedSubA = finishedSub;
      } else {
        await _disposeDeckB();
        _sourceB = source;
        _handleB = handle;
        _durationB = duration;
        _finishedSubB = finishedSub;
      }
    } else {
      // Load onto the idle deck (about to be swapped active).
      if (_aActive) {
        await _disposeDeckB();
        _sourceB = source;
        _handleB = handle;
        _durationB = duration;
        _finishedSubB = finishedSub;
      } else {
        await _disposeDeckA();
        _sourceA = source;
        _handleA = handle;
        _durationA = duration;
        _finishedSubA = finishedSub;
      }
    }
    return duration;
  }

  Future<void> _disposeDeckA() async {
    final h = _handleA;
    final s = _sourceA;
    await _finishedSubA?.cancel();
    _finishedSubA = null;
    if (h != null) _safeStop(h);
    if (s != null) {
      try {
        await _soloud.disposeSource(s);
      } catch (_) {}
    }
    _handleA = null;
    _sourceA = null;
    _durationA = null;
  }

  Future<void> _disposeDeckB() async {
    final h = _handleB;
    final s = _sourceB;
    await _finishedSubB?.cancel();
    _finishedSubB = null;
    if (h != null) _safeStop(h);
    if (s != null) {
      try {
        await _soloud.disposeSource(s);
      } catch (_) {}
    }
    _handleB = null;
    _sourceB = null;
    _durationB = null;
  }

  Future<void> _stopAndUnloadAll() async {
    await _disposeDeckA();
    await _disposeDeckB();
    _durCtrl.add(null);
  }

  Future<void> _unloadIdleSource() async {
    if (_aActive) {
      await _disposeDeckB();
    } else {
      await _disposeDeckA();
    }
  }

  double _safeGetVolume(SoundHandle h) {
    try {
      return _soloud.getVolume(h);
    } catch (_) {
      return 1.0;
    }
  }

  void _safeStop(SoundHandle h) {
    try {
      _soloud.stop(h);
    } catch (_) {}
  }

  Future<void> dispose() async {
    _fadeTimer?.cancel();
    _stopPositionPolling();
    await _disposeDeckA();
    await _disposeDeckB();
    try {
      _audioData.dispose();
    } catch (_) {}
    await _stateCtrl.close();
    await _posCtrl.close();
    await _durCtrl.close();
  }

  // --- Audio analysis --------------------------------------------------

  /// Enable the live FFT visualization buffer on the soloud engine.
  /// Also lowers SoLoud's built-in FFT smoothing so transients (kick
  /// drum attacks etc.) aren't averaged out before we see them — the
  /// fluid is reading the *onset* not the steady-state level. Idempotent.
  void enableVisualization() {
    try {
      _soloud.setVisualizationEnabled(true);
      // 0 = no smoothing, 1 = full lag. The default is high, which
      // flattens kick transients into a slow swell — exactly what
      // makes the fluid feel "out of sync" with the music. Light
      // smoothing (~0.2) keeps frame-to-frame jitter manageable
      // without burying the attacks.
      _soloud.setFftSmoothing(0.2);
    } catch (e) {
      debugPrint('[player] enableVisualization failed: $e');
    }
  }

  // Onset-detection state. The kick-detection signal is "how much did
  // bass-band energy *rise* this frame" (spectral flux), not the
  // absolute level — that's what makes the fluid feel locked to the
  // beat instead of vaguely bobbing.
  double _prevBassMag = 0;
  double _rollingFluxPeak = 1e-3;

  /// Read a 0..1 bass-onset signal off the live mix. Implements
  /// spectral flux on FFT bins 1..8 (~86-690 Hz at 44.1 kHz, covering
  /// sub-bass kick fundamentals through the punch/body of the attack):
  ///
  ///   1. Sum bass-band magnitudes for the current frame.
  ///   2. Compute the *positive* differential vs the last frame's sum
  ///      (with a soft decay on the last value, so sustained bass
  ///      partially counts as ongoing energy but new attacks dominate).
  ///   3. Auto-normalise against a rolling peak of the flux signal so
  ///      quiet tracks still drive the full 0..1 range, and a gamma
  ///      curve (pow 0.6) lifts the quieter kicks while letting hard
  ///      hits hit ceiling.
  ///
  /// Result: near-zero between kicks, hard spikes on each one — the
  /// fluid's lurch threshold inside [_FluidSim] actually fires now.
  double readBassLevel() {
    try {
      _audioData.updateSamples();
      final samples = _audioData.getAudioData();
      if (samples.length < 10) return 0.0;

      // Wider bass window than before. Bin 0 is DC (skip); bins 1..8
      // run from ~86 Hz up through ~690 Hz, which captures sub-bass
      // and the kick's body in one read.
      const lo = 1, hi = 8;
      var mag = 0.0;
      for (var i = lo; i <= hi; i++) {
        mag += samples[i].abs();
      }
      mag /= (hi - lo + 1);

      // Spectral flux: only positive rises count. Multiplying prev by
      // 0.85 allows ~15% of sustained bass through, so a long drone
      // doesn't read flat-zero, but transient kicks still dominate.
      final flux = math.max(0.0, mag - _prevBassMag * 0.85);
      _prevBassMag = mag;

      // Rolling peak adapts faster than the magnitude version (0.985
      // half-life vs the old 0.995) so quiet bridges don't stay locked
      // out by a loud chorus's leftover peak.
      if (flux > _rollingFluxPeak) _rollingFluxPeak = flux;
      _rollingFluxPeak *= 0.985;
      if (_rollingFluxPeak < 1e-3) _rollingFluxPeak = 1e-3;

      final norm = (flux / _rollingFluxPeak).clamp(0.0, 1.0);
      // Gamma 0.6 lifts the long tail of small flux values so subtle
      // kicks still register — without it the signal sits near 0 most
      // of the time and only fires on the very biggest hits.
      return math.pow(norm, 0.6).toDouble();
    } catch (_) {
      return 0.0;
    }
  }

  /// Returns a snapshot of the 256 FFT magnitudes (one per bin,
  /// covering ~0 Hz to Nyquist) from SoLoud's visualisation buffer.
  /// Callers must NOT mutate the returned list; it's the live backing
  /// store and changes each tick. Returns null if the engine isn't
  /// reporting visualisation data yet.
  ///
  /// Used by the spectrum-fluid background to drive its waterfall —
  /// raw bins so the bg can do its own perceptual / log grouping.
  Float32List? readFftSnapshot() {
    try {
      _audioData.updateSamples();
      final samples = _audioData.getAudioData();
      if (samples.length < 256) return null;
      // Linear-mode buffer: floats 0..255 are FFT, 256..511 are wave.
      // We only need the FFT half for spectrum visualisation.
      return Float32List.sublistView(samples, 0, 256);
    } catch (_) {
      return null;
    }
  }

  /// The currently-active deck's known duration. Useful for UI defaults.
  Duration? get currentDuration => _activeDuration;

  /// Whether the active deck currently has a loaded source. Pure
  /// convenience for callers (e.g., a Hero shuttle gating on song != null).
  bool get hasActiveSource => _activeSource != null;
}
