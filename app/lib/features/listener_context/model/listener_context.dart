import 'context_enums.dart';
import 'results.dart';

/// The Listener Context Engine's single output object (spec: OUTPUT). One
/// snapshot of *who is listening, how, and what to do next* — consumed by the
/// queue/recommendation layer and the AutoMix engine.
class ListenerContext {
  const ListenerContext({
    required this.mood,
    required this.session,
    required this.fatigue,
    required this.discovery,
    required this.energy,
    required this.timeOfDay,
    required this.location,
    required this.automix,
    required this.queueRanking,
    required this.profile,
    required this.generatedAt,
  });

  final MoodResult mood;
  final SessionAnalysis session;
  final FatigueResult fatigue;
  final DiscoveryResult discovery;
  final EnergyPlan energy;
  final TimeOfDay timeOfDay;
  final LocationContext location;
  final AutoMixDirectives automix;

  /// Candidates re-ranked by the spec's Queue Optimization score, best first.
  final List<RankedTrack> queueRanking;

  final ListenerProfile profile;
  final DateTime generatedAt;

  /// The top N candidate song ids (spec: nextTrackCandidates).
  List<String> nextTrackCandidates([int n = 10]) =>
      queueRanking.take(n).map((r) => r.songId).toList();

  /// The exact spec OUTPUT shape.
  Map<String, dynamic> toJson() => {
        'currentMood': mood.mood.name,
        'moodConfidence': mood.confidence100,
        'sessionState': session.state.name,
        'sessionConfidence': session.confidence100,
        'fatigueScore': fatigue.score100,
        'discoveryScore': discovery.score100,
        'targetEnergy': energy.targetEnergy100,
        'recommendedTransitionType': automix.transitionStyle.name,
        'recommendedTransitionDuration':
            automix.transitionDuration.inMilliseconds / 1000.0,
        'timeOfDay': timeOfDay.name,
        'location': location.name,
        'nextTrackCandidates': nextTrackCandidates(),
        'queueRanking': queueRanking.map((r) => r.toJson()).toList(),
        'listenerProfile': profile.toJson(),
        'generatedAt': generatedAt.toIso8601String(),
      };
}
