import 'package:flutter/foundation.dart';

import '../../data/database/app_database.dart';
import '../player/player_service.dart';
import 'engine/automix_planner.dart';
import 'model/automix_enums.dart';
import 'model/track_analysis.dart';
import 'model/transition_plan.dart';
import 'runtime/analysis_store.dart';
import 'runtime/automix_engine.dart';

/// Result of asking the engine to mix into the next track.
enum AutoMixOutcome {
  mixed, // a real beat-matched transition ran
  noAnalysis, // one/both tracks lack a sidecar — caller should hard-cut
  notPlaying, // nothing to mix out of
  busy, // a transition is already running
  failed,
}

/// Public entry point for the AutoMix engine — the one surface the player UI
/// (the in-progress player-page button) will call. It ties together the
/// analysis store, the deterministic planner, and the live executor.
///
/// Typical use:
/// ```dart
/// final outcome = await autoMix.mixToNext(current: a, next: b);
/// if (outcome != AutoMixOutcome.mixed) await player.playSong(b); // fallback
/// ```
class AutoMixService {
  AutoMixService({
    required PlayerService player,
    required AnalysisStore analysis,
    AutoMixPlanner planner = const AutoMixPlanner(),
  })  : _player = player,
        _analysis = analysis,
        _planner = planner,
        _engine = AutoMixEngine(player);

  final PlayerService _player;
  final AnalysisStore _analysis;
  final AutoMixPlanner _planner;
  final AutoMixEngine _engine;

  bool get isMixing => _engine.isRunning;

  /// Whether both tracks can be auto-mixed (both have analysis sidecars).
  Future<bool> canMix(SongRow current, SongRow next) async {
    final a = await _analysis.forSong(current);
    final b = await _analysis.forSong(next);
    return a != null && b != null;
  }

  /// Plan — but don't run — the transition. Useful for a preview/timeline UI
  /// or to inspect the score before committing. Returns null if either track
  /// lacks analysis.
  Future<TransitionPlan?> planTransition({
    required SongRow current,
    required SongRow next,
    double? playheadSec,
    TransitionType type = TransitionType.aiSelected,
  }) async {
    final out = await _analysis.forSong(current);
    final inc = await _analysis.forSong(next);
    if (out == null || inc == null) return null;
    return _planner.plan(
      out: out,
      incoming: inc,
      playheadSec: playheadSec ?? _playheadSec(out),
      requestedType: type,
    );
  }

  /// Score every transition type for this pair (debug / "why this mix" UI).
  Future<List<TransitionPlan>> rankTransitions({
    required SongRow current,
    required SongRow next,
    double? playheadSec,
  }) async {
    final out = await _analysis.forSong(current);
    final inc = await _analysis.forSong(next);
    if (out == null || inc == null) return const [];
    return _planner.rankAll(
      out: out,
      incoming: inc,
      playheadSec: playheadSec ?? _playheadSec(out),
    );
  }

  /// Plan + perform a transition from the currently-playing [current] into
  /// [next]. Returns how it went so the caller can fall back to a plain cut.
  Future<AutoMixOutcome> mixToNext({
    required SongRow current,
    required SongRow next,
    TransitionType type = TransitionType.aiSelected,
  }) async {
    if (_engine.isRunning) return AutoMixOutcome.busy;

    final plan = await planTransition(current: current, next: next, type: type);
    if (plan == null) return AutoMixOutcome.noAnalysis;

    try {
      final decks = await _player.beginAutoMix(
        next.localFilePath,
        incomingStartSec: plan.incomingStartSec,
      );
      if (decks == null) return AutoMixOutcome.notPlaying;
      if (kDebugMode) {
        debugPrint('[automix] ${plan.type.label} '
            'score=${(plan.score.total * 100).round()}% '
            'dur=${plan.durationSec.toStringAsFixed(1)}s');
      }
      final ok = await _engine.run(plan, decks);
      return ok ? AutoMixOutcome.mixed : AutoMixOutcome.failed;
    } catch (e) {
      if (kDebugMode) debugPrint('[automix] mixToNext failed: $e');
      return AutoMixOutcome.failed;
    }
  }

  /// Abort an in-progress mix. [keepIncoming] leaves the new track playing.
  Future<void> cancel({bool keepIncoming = true}) =>
      _engine.stop(keepIncoming: keepIncoming);

  double _playheadSec(TrackAnalysis out) {
    final pos = _player.activePosition;
    if (pos == null) return out.cuePoints.mixOutSec;
    return pos.inMicroseconds / 1e6;
  }
}
