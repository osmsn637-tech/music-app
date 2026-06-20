import '../ai_dj/user_listening_profile.dart';
import 'engine/automix_bridge.dart';
import 'engine/discovery_engine.dart';
import 'engine/energy_manager.dart';
import 'engine/fatigue_detector.dart';
import 'engine/mood_detector.dart';
import 'engine/profile_builder.dart';
import 'engine/queue_optimizer.dart';
import 'engine/session_analyzer.dart';
import 'engine/time_context.dart';
import 'model/context_enums.dart';
import 'model/listener_context.dart';
import 'model/results.dart';
import 'model/session_event.dart';
import 'model/track_features.dart';

/// The Listener Context Engine (spec top level). A pure, deterministic
/// function from *history + live session + candidate pool* to a single
/// [ListenerContext] snapshot that drives recommendations, queue ordering and
/// AutoMix. No I/O — the runtime layer loads the inputs and persists nothing
/// here, so it's cheap to re-run every time the queue changes.
class ListenerContextEngine {
  const ListenerContextEngine();

  static const _profile = ProfileBuilder();
  static const _time = TimeContextEngine();
  static const _session = SessionAnalyzer();
  static const _mood = MoodDetector();
  static const _energy = EnergyManager();
  static const _fatigue = FatigueDetector();
  static const _discovery = DiscoveryEngine();
  static const _queue = QueueOptimizer();
  static const _automix = AutoMixBridge();

  ListenerContext evaluate({
    required UserListeningProfile history,
    required Map<String, TrackFeatures> featuresById,
    required List<SessionEvent> sessionEvents,
    required List<String> recentlyPlayedIds,
    required List<TrackFeatures> candidates,
    LocationContext location = LocationContext.unknown,
    DateTime? now,
    DateTime? sessionStart,
  }) {
    final t = now ?? DateTime.now();
    final tod = _time.resolve(t);

    final profile = _profile.build(
      history: history,
      featuresById: featuresById,
      recentEvents: sessionEvents,
      now: t,
    );

    final recentlyPlayed = recentlyPlayedIds
        .map((id) => featuresById[id])
        .whereType<TrackFeatures>()
        .toList(growable: false);
    final currentTrack =
        recentlyPlayed.isNotEmpty ? recentlyPlayed.last : null;
    final avgEnergy = recentlyPlayed.isEmpty
        ? profile.energyPreference.overall.center
        : recentlyPlayed.map((f) => f.energy).reduce((a, b) => a + b) /
            recentlyPlayed.length;

    final start = sessionStart ??
        (sessionEvents.isNotEmpty
            ? sessionEvents
                .map((e) => e.at)
                .reduce((a, b) => a.isBefore(b) ? a : b)
            : t);
    final window = SessionWindow(events: sessionEvents, now: t, start: start);

    final session = _session.analyze(
      window: window,
      tod: tod,
      location: location,
      avgEnergy: avgEnergy,
    );

    final mood = _mood.detect(
      recentlyPlayed: recentlyPlayed,
      baseline: profile.baselineMood,
      sessionState: session.state,
      tod: tod,
    );

    final energyPlan = _energy.plan(
      sessionTracks: recentlyPlayed,
      mood: mood.mood,
      state: session.state,
      tod: tod,
      preferredCenter: profile.energyPreference.overall.center,
    );

    final fatigue = _fatigue.detect(window: window);

    final discovery = _discovery.compute(
      session: session,
      fatigue: fatigue,
      exploration: profile.exploration,
    );

    final familiar = history.playCountById.entries
        .where((e) => e.value > 0)
        .map((e) => e.key)
        .toSet();

    final ranking = _queue.rank(
      candidates: candidates,
      profile: profile,
      mood: mood.mood,
      targetEnergy: energyPlan.targetEnergy,
      tod: tod,
      explorationTarget: discovery.explorationTarget,
      familiarSongIds: familiar,
      currentTrack: currentTrack,
    );

    final automix = _automix.toDirectives(
      energy: energyPlan,
      mood: mood.mood,
      fatigue: fatigue,
      session: session,
      tod: tod,
      location: location,
      preferred: profile.preferredTransitionStyle,
    );

    return ListenerContext(
      mood: mood,
      session: session,
      fatigue: fatigue,
      discovery: discovery,
      energy: energyPlan,
      timeOfDay: tod,
      location: location,
      automix: automix,
      queueRanking: ranking,
      profile: profile,
      generatedAt: t,
    );
  }
}
