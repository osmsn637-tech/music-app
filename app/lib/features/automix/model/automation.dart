import 'dart:math' as math;

import 'automix_enums.dart';

/// A single point on an automation curve: [t] seconds **from the start of
/// the transition** (not absolute track time), and the target [value].
class Keyframe {
  const Keyframe(this.t, this.value);
  final double t;
  final double value;

  Map<String, dynamic> toJson() => {'t': t, 'v': value};
}

/// A piecewise-linear automation curve sampled by the runtime executor on
/// its ~20 ms ticker. Values before the first / after the last keyframe are
/// held flat (clamped), so a curve is well-defined for any [t].
///
/// Curves are the engine's universal output unit — gain, EQ gain, stem
/// volume, send levels are all expressed as one of these.
class AutomationCurve {
  AutomationCurve(List<Keyframe> keyframes)
      : keyframes = (List.of(keyframes)..sort((a, b) => a.t.compareTo(b.t)));

  final List<Keyframe> keyframes;

  /// Flat curve at [v] for the whole transition.
  factory AutomationCurve.constant(double v) =>
      AutomationCurve([Keyframe(0, v)]);

  /// Linear ramp from [from] to [to] across [0, durationSec].
  factory AutomationCurve.ramp(double from, double to, double durationSec) =>
      AutomationCurve([Keyframe(0, from), Keyframe(durationSec, to)]);

  /// Equal-power fade in 0→1 (constant-power crossfade leg). Uses the
  /// sin/cos law so a paired fade-in + fade-out hold perceived loudness
  /// flat through the middle instead of dipping (the classic linear-xfade
  /// "hole in the mix").
  factory AutomationCurve.equalPowerIn(double durationSec, {int steps = 16}) {
    final ks = <Keyframe>[];
    for (var i = 0; i <= steps; i++) {
      final p = i / steps;
      ks.add(Keyframe(p * durationSec, _sinHalf(p)));
    }
    return AutomationCurve(ks);
  }

  /// Equal-power fade out 1→0.
  factory AutomationCurve.equalPowerOut(double durationSec, {int steps = 16}) {
    final ks = <Keyframe>[];
    for (var i = 0; i <= steps; i++) {
      final p = i / steps;
      ks.add(Keyframe(p * durationSec, _sinHalf(1.0 - p)));
    }
    return AutomationCurve(ks);
  }

  /// Sample the curve at [t] seconds, clamping outside the keyframe range.
  double valueAt(double t) {
    if (keyframes.isEmpty) return 0;
    if (t <= keyframes.first.t) return keyframes.first.value;
    if (t >= keyframes.last.t) return keyframes.last.value;
    // linear search is fine — curves have a handful of keyframes
    for (var i = 0; i < keyframes.length - 1; i++) {
      final a = keyframes[i];
      final b = keyframes[i + 1];
      if (t >= a.t && t <= b.t) {
        final span = (b.t - a.t);
        if (span <= 0) return b.value;
        final f = (t - a.t) / span;
        return a.value + (b.value - a.value) * f;
      }
    }
    return keyframes.last.value;
  }

  double get lastValue => keyframes.isEmpty ? 0 : keyframes.last.value;
  double get firstValue => keyframes.isEmpty ? 0 : keyframes.first.value;

  List<Map<String, dynamic>> toJson() =>
      keyframes.map((k) => k.toJson()).toList();
}

/// A dynamic-EQ move on one [band]: a gain-in-dB curve over the transition.
/// Negative values duck the band (e.g. −6 dB on bass to clear headroom for
/// the incoming low end); 0 dB is flat. This is *dynamic* EQ — the value
/// changes across the transition, not a single static cut.
class EqMove {
  EqMove({required this.band, required this.gainDb});
  final EqBand band;
  final AutomationCurve gainDb;

  Map<String, dynamic> toJson() => {
        'band': band.name,
        'centerHz': band.centerHz,
        'gainDb': gainDb.toJson(),
      };
}

// sin(p · π/2): the equal-power crossfade leg.
double _sinHalf(double p) => math.sin(p.clamp(0.0, 1.0) * math.pi / 2);
