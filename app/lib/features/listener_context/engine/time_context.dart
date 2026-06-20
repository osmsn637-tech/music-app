import '../model/context_enums.dart';
import '../model/results.dart';

/// Time Context Engine (spec). Maps the clock onto a [TimeOfDay] bucket and a
/// set of adaptation biases: mornings lean uplifting, nights lean lower-energy
/// with smoother transitions.
class TimeContextEngine {
  const TimeContextEngine();

  TimeOfDay resolve(DateTime now) => TimeOfDay.from(now);

  TimeAdaptation adaptationFor(TimeOfDay tod) => switch (tod) {
        TimeOfDay.morning => const TimeAdaptation(
            energyBias: 0.10,
            valenceBias: 0.12,
            transitionSmoothness: 0.4,
            note: 'Morning — uplifting, building energy',
          ),
        TimeOfDay.afternoon => const TimeAdaptation(
            energyBias: 0.05,
            valenceBias: 0.04,
            transitionSmoothness: 0.45,
            note: 'Afternoon — steady, neutral energy',
          ),
        TimeOfDay.evening => const TimeAdaptation(
            energyBias: -0.02,
            valenceBias: 0.0,
            transitionSmoothness: 0.6,
            note: 'Evening — winding down, smoother blends',
          ),
        TimeOfDay.night => const TimeAdaptation(
            energyBias: -0.18,
            valenceBias: -0.02,
            transitionSmoothness: 0.85,
            note: 'Night — low energy, long smooth transitions',
          ),
      };

  /// Time-context match (spec Queue Optimization term): how well a track's
  /// energy fits the time of day, 0..1.
  double matchScore({
    required double trackEnergy,
    required TimeOfDay tod,
    required double preferredCenter,
  }) {
    final target = (preferredCenter + adaptationFor(tod).energyBias)
        .clamp(0.0, 1.0);
    return (1 - (trackEnergy - target).abs()).clamp(0.0, 1.0);
  }
}
