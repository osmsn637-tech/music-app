import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_soloud/flutter_soloud.dart';

import '../../player/player_service.dart';
import '../model/automation.dart';
import '../model/automix_enums.dart';
import '../model/transition_plan.dart';

/// Executes a [TransitionPlan] on the live audio engine. Takes the two deck
/// refs from [PlayerService.beginAutoMix] and, on a ~25 ms ticker, samples
/// the plan's automation curves and pushes them into SoLoud:
///   - per-deck master volume (gain curves + LUFS trim),
///   - incoming tempo (relative play speed) + pitch correction/harmonic
///     shift (pitch-shift filter) — i.e. time-stretch without changing pitch,
///   - dynamic EQ ducking (8-band equalizer per source),
///   - reverb / echo sends on the outgoing tail,
///   - a master-bus limiter while the two mixes overlap.
///
/// Stem-level playback (separate drum/bass/vocal voices) activates only when
/// a plan carries stem curves; current plans run the mixed-file path, with
/// stem swaps expressed through the EQ + gain automation.
class AutoMixEngine {
  AutoMixEngine(this._player);

  final PlayerService _player;
  SoLoud get _soloud => _player.soloud;

  Timer? _ticker;
  Completer<bool>? _done;
  AutoMixDecks? _decks;
  TransitionPlan? _plan;
  bool _running = false;

  bool get isRunning => _running;

  /// Maps the spec's 7 mix-console bands onto SoLoud's 8-band equalizer.
  static const Map<EqBand, int> _bandIndex = {
    EqBand.subBass: 1,
    EqBand.bass: 2,
    EqBand.lowMid: 3,
    EqBand.mid: 4,
    EqBand.highMid: 5,
    EqBand.presence: 6,
    EqBand.brilliance: 7,
  };

  static const _tickMs = 25;

  // Beat-match state. We only stretch the incoming tempo when the change is
  // gentle (a large stretch sounds worse than an honest unmatched blend), and
  // we RELEASE the match back to native tempo by the end of the transition so
  // the next track never plays its whole length at an altered tempo.
  double _incomingRatio = 1.0;
  bool _tempoActive = false;
  static const _maxStretch = 0.06; // ±6% — DJ-comfortable beat-match range

  /// Run [plan] over [decks]. Completes true when the transition finishes
  /// cleanly (outgoing unloaded, incoming left playing), false if aborted.
  Future<bool> run(TransitionPlan plan, AutoMixDecks decks) async {
    await stop(); // never overlap two transitions
    _plan = plan;
    _decks = decks;
    _running = true;
    final done = _done = Completer<bool>();

    _prime(plan, decks);

    final totalMs = (plan.durationSec * 1000).round().clamp(200, 600000);
    final start = DateTime.now();
    _ticker = Timer.periodic(const Duration(milliseconds: _tickMs), (t) {
      final elapsedMs = DateTime.now().difference(start).inMilliseconds;
      final tSec = elapsedMs / 1000.0;
      _applyAt(plan, decks, math.min(tSec, plan.durationSec));
      if (elapsedMs >= totalMs) {
        _finish(commit: true);
      }
    });
    return done.future;
  }

  /// One-time filter setup + constant params (tempo, pitch, limiter).
  void _prime(TransitionPlan plan, AutoMixDecks decks) {
    // Beat-match the incoming tempo ONLY when the stretch is gentle; a large
    // stretch is more distracting than an unmatched blend. When applied, the
    // matched tempo glides back to native over the back half of the blend
    // (see _applyTempo) so the change lasts only for the transition — never
    // the whole next track.
    final r = plan.incoming.playSpeedRatio;
    _incomingRatio = (r - 1.0).abs() <= _maxStretch ? r : 1.0;
    _tempoActive = _incomingRatio != 1.0;
    if (_tempoActive) {
      _trySet(() =>
          _soloud.setRelativePlaySpeed(decks.incomingHandle, _incomingRatio));
      // pitch-shift ONLY to cancel the resampling side-effect (preserve
      // pitch). We deliberately skip the harmonic ±semitone shift — SoLoud's
      // pitch filter isn't clean enough to justify it on a full mix.
      _activatePitch(decks.incomingSource, decks.incomingHandle,
          -_semitonesFor(_incomingRatio));
    }

    // EQ filters (only if the deck has moves).
    if (plan.outgoing.eq.isNotEmpty) _activateEq(decks.outgoingSource);
    if (plan.incoming.eq.isNotEmpty) _activateEq(decks.incomingSource);

    // Reverb / echo live on the outgoing tail.
    if (_usesSend(plan.outgoing.reverbWet)) {
      _trySet(() {
        final f = decks.outgoingSource.filters.freeverbFilter;
        if (!f.isActive) f.activate();
      });
    }
    if (_usesSend(plan.outgoing.echoWet)) {
      _trySet(() {
        final f = decks.outgoingSource.filters.echoFilter;
        if (!f.isActive) f.activate();
      });
    }

    // Master-bus protection while two mixes stack.
    if (plan.masterLimiter) {
      // ignore: experimental_member_use
      _trySet(() => _soloud.filters.limiterFilter.activate());
    }
  }

  /// Per-tick automation push.
  void _applyAt(TransitionPlan plan, AutoMixDecks decks, double tSec) {
    _applyDeck(plan.outgoing, decks.outgoingSource, decks.outgoingHandle, tSec);
    _applyDeck(plan.incoming, decks.incomingSource, decks.incomingHandle, tSec);
    _applyTempo(plan, decks, tSec);
  }

  /// Glide the incoming tempo from matched → native across the back half of
  /// the blend, so by commit it plays at its own speed (pitch tracks along so
  /// it stays pitch-correct the whole way).
  void _applyTempo(TransitionPlan plan, AutoMixDecks decks, double tSec) {
    if (!_tempoActive) return;
    final p =
        plan.durationSec <= 0 ? 1.0 : (tSec / plan.durationSec).clamp(0.0, 1.0);
    final sp = _incomingSpeedAt(p);
    _trySet(() => _soloud.setRelativePlaySpeed(decks.incomingHandle, sp));
    final semis = -_semitonesFor(sp);
    _trySet(() {
      // ignore: experimental_member_use
      decks.incomingSource.filters.pitchShiftFilter
          .semitones(soundHandle: decks.incomingHandle)
          .value = semis;
    });
  }

  double _incomingSpeedAt(double p) {
    const releaseStart = 0.55; // beat-locked for the first ~55%, then glide
    if (p <= releaseStart) return _incomingRatio;
    final r = ((p - releaseStart) / (1 - releaseStart)).clamp(0.0, 1.0);
    return _incomingRatio + (1.0 - _incomingRatio) * r;
  }

  double _semitonesFor(double ratio) =>
      ratio <= 0 ? 0 : 12 * (math.log(ratio) / math.ln2);

  void _applyDeck(
      DeckPlan deck, AudioSource source, SoundHandle handle, double tSec) {
    // master volume = curve × LUFS-trim, clamped to a safe ceiling
    final base = _dbToLinear(deck.baseGainDb);
    final vol = (deck.volume.valueAt(tSec) * base).clamp(0.0, 1.5);
    _trySet(() => _soloud.setVolume(handle, vol));

    // dynamic EQ
    for (final move in deck.eq) {
      final idx = _bandIndex[move.band];
      if (idx == null) continue;
      final lin = _dbToLinear(move.gainDb.valueAt(tSec)).clamp(0.0, 4.0);
      _setEqBand(source, handle, idx, lin);
    }

    // sends
    if (_usesSend(deck.reverbWet)) {
      final w = deck.reverbWet.valueAt(tSec).clamp(0.0, 1.0);
      _trySet(() =>
          source.filters.freeverbFilter.wet(soundHandle: handle).value = w);
    }
    if (_usesSend(deck.echoWet)) {
      final w = deck.echoWet.valueAt(tSec).clamp(0.0, 1.0);
      _trySet(
          () => source.filters.echoFilter.wet(soundHandle: handle).value = w);
    }
  }

  Future<void> _finish({required bool commit}) async {
    if (!_running) return;
    _ticker?.cancel();
    _ticker = null;
    _running = false;
    final decks = _decks;
    final plan = _plan;

    if (decks != null && plan != null) {
      if (commit) {
        // Land the incoming deck at unity gain (× any kept LUFS trim), flat
        // EQ, and — crucially — NATIVE tempo/pitch, so the next track plays
        // itself for the rest of the song instead of staying time-stretched.
        final base = _dbToLinear(plan.incoming.baseGainDb);
        _trySet(
            () => _soloud.setVolume(decks.incomingHandle, base.clamp(0.0, 1.5)));
        _resetEq(decks.incomingSource, decks.incomingHandle);
        _deactivateSends(decks.incomingSource);
        if (_tempoActive) {
          _trySet(
              () => _soloud.setRelativePlaySpeed(decks.incomingHandle, 1.0));
          _deactivatePitch(decks.incomingSource);
        }
      } else {
        // Aborting: the incoming deck is about to be discarded and the
        // OUTGOING track survives as the fallback — so clean *its* mix
        // filters (EQ ducks, pitch shift, reverb/echo) or it resumes
        // distorted. The outgoing source is still loaded here.
        _resetEq(decks.outgoingSource, decks.outgoingHandle);
        _deactivateSends(decks.outgoingSource);
        _deactivatePitch(decks.outgoingSource);
        _trySet(() => _soloud.setVolume(decks.outgoingHandle, 1.0));
      }
    }

    try {
      if (commit) {
        await _player.commitAutoMix(); // stop + unload the outgoing deck
      } else if (decks != null) {
        await _player.abortAutoMix(decks);
      }

      // Drop the transient master limiter.
      // ignore: experimental_member_use
      _trySet(() => _soloud.filters.limiterFilter.deactivate());
    } finally {
      // ALWAYS complete the run() future — if commit/abort threw, leaving it
      // pending would hang mixToNext (and the whole queue) forever.
      _done?.complete(commit);
      _done = null;
      _decks = null;
      _plan = null;
      _tempoActive = false;
      _incomingRatio = 1.0;
    }
  }

  /// Cancel an in-progress transition. [keepIncoming] commits (incoming plays
  /// on), otherwise aborts back to the outgoing track.
  Future<void> stop({bool keepIncoming = true}) async {
    if (!_running) return;
    await _finish(commit: keepIncoming);
  }

  // --- filter helpers ----------------------------------------------------

  void _activatePitch(AudioSource source, SoundHandle handle, double semis) {
    _trySet(() {
      // ignore: experimental_member_use
      final f = source.filters.pitchShiftFilter;
      if (!f.isActive) f.activate();
      // ignore: experimental_member_use
      f.semitones(soundHandle: handle).value = semis;
    });
  }

  void _activateEq(AudioSource source) {
    _trySet(() {
      final f = source.filters.equalizerFilter;
      if (!f.isActive) f.activate();
      f.wet().value = 1.0;
    });
  }

  void _setEqBand(
      AudioSource source, SoundHandle handle, int band, double linear) {
    _trySet(() {
      final eq = source.filters.equalizerFilter;
      switch (band) {
        case 1:
          eq.band1(soundHandle: handle).value = linear;
        case 2:
          eq.band2(soundHandle: handle).value = linear;
        case 3:
          eq.band3(soundHandle: handle).value = linear;
        case 4:
          eq.band4(soundHandle: handle).value = linear;
        case 5:
          eq.band5(soundHandle: handle).value = linear;
        case 6:
          eq.band6(soundHandle: handle).value = linear;
        case 7:
          eq.band7(soundHandle: handle).value = linear;
        case 8:
          eq.band8(soundHandle: handle).value = linear;
      }
    });
  }

  void _resetEq(AudioSource source, SoundHandle handle) {
    for (var b = 1; b <= 8; b++) {
      _setEqBand(source, handle, b, 1.0);
    }
  }

  void _deactivatePitch(AudioSource source) {
    _trySet(() {
      // ignore: experimental_member_use
      final f = source.filters.pitchShiftFilter;
      if (f.isActive) f.deactivate();
    });
  }

  void _deactivateSends(AudioSource source) {
    _trySet(() {
      final r = source.filters.freeverbFilter;
      if (r.isActive) r.deactivate();
    });
    _trySet(() {
      final e = source.filters.echoFilter;
      if (e.isActive) e.deactivate();
    });
  }

  bool _usesSend(AutomationCurve c) =>
      c.keyframes.any((k) => k.value > 0.001);

  double _dbToLinear(double db) =>
      db == 0 ? 1.0 : math.pow(10, db / 20).toDouble();

  void _trySet(void Function() fn) {
    try {
      fn();
    } catch (e) {
      if (kDebugMode) debugPrint('[automix] filter op failed: $e');
    }
  }
}
