import '../../data/database/app_database.dart';
import '../ai_dj/user_listening_profile.dart';
import '../automix/runtime/analysis_store.dart';
import 'listener_context_engine.dart';
import 'model/context_enums.dart';
import 'model/listener_context.dart';
import 'model/session_event.dart';
import 'model/track_features.dart';

/// Public entry point for the Listener Context Engine. Assembles the engine's
/// inputs — the durable [UserListeningProfile] from the DB, per-track
/// [TrackFeatures] from the AutoMix analysis sidecars, and the live session
/// events — then runs the pure engine and returns a [ListenerContext].
///
/// This is the surface the queue/recommendation layer and the AutoMix trigger
/// call. It does not mutate playback or the DB.
class ListenerContextService {
  ListenerContextService({
    required AppDatabase db,
    required AnalysisStore analysis,
    ListenerContextEngine engine = const ListenerContextEngine(),
  })  : _db = db,
        _analysis = analysis,
        _engine = engine;

  final AppDatabase _db;
  final AnalysisStore _analysis;
  final ListenerContextEngine _engine;

  /// Evaluate the current listener context.
  ///
  /// [candidates] are the songs eligible for the next slot(s). [recentlyPlayed]
  /// is the session's play order (last element = now playing). [profileSongs]
  /// optionally widens the taste centroid (pass the user's completed/library
  /// songs for best fidelity); defaults to candidates + recently played.
  Future<ListenerContext> evaluate({
    required List<SongRow> candidates,
    List<SongRow> recentlyPlayed = const [],
    List<SongRow> profileSongs = const [],
    List<SessionEvent> sessionEvents = const [],
    LocationContext location = LocationContext.unknown,
    DateTime? now,
  }) async {
    final history = await UserListeningProfile.load(_db);

    // Build features once per distinct song across all the inputs.
    final byId = <String, SongRow>{};
    for (final s in [...candidates, ...recentlyPlayed, ...profileSongs]) {
      byId[s.id] = s;
    }
    final featuresById = <String, TrackFeatures>{};
    for (final song in byId.values) {
      final analysis = await _analysis.forSong(song);
      featuresById[song.id] = TrackFeatures.fromSong(song, analysis);
    }

    return _engine.evaluate(
      history: history,
      featuresById: featuresById,
      sessionEvents: sessionEvents,
      recentlyPlayedIds: recentlyPlayed.map((s) => s.id).toList(),
      candidates: candidates
          .map((s) => featuresById[s.id])
          .whereType<TrackFeatures>()
          .toList(),
      location: location,
      now: now,
    );
  }
}
