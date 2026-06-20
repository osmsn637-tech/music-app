import '../model/track_analysis.dart';

/// Chosen, beat-aligned mix points for one transition.
class CueSelection {
  const CueSelection({
    required this.outMixOutSec,
    required this.inMixInSec,
    required this.outBeatPeriod,
    required this.inBeatPeriod,
  });

  /// Downbeat-aligned position on the outgoing track where the mix starts.
  final double outMixOutSec;

  /// Downbeat-aligned position on the incoming track where it's brought in.
  final double inMixInSec;

  final double outBeatPeriod;
  final double inBeatPeriod;
}

/// Pick where the two tracks meet, snapping both to downbeats so bars line
/// up (§3). [playheadSec] is where the outgoing track currently is.
///
/// If the analyzer's natural mix-out (near the outro) is comfortably ahead
/// of the playhead we use it; otherwise — e.g. the user hit "mix now"
/// mid-song — we pick the next downbeat a short lead beyond the playhead so
/// the blend still starts on a bar line.
CueSelection selectCues({
  required TrackAnalysis out,
  required TrackAnalysis incoming,
  required double playheadSec,
  double minLeadSec = 4.0,
  double? requestedMixOutSec,
}) {
  final outGrid = out.beatGrid;
  final inGrid = incoming.beatGrid;

  // ----- outgoing mix-out -----
  double targetOut;
  final natural = out.cuePoints.mixOutSec;
  if (requestedMixOutSec != null) {
    targetOut = requestedMixOutSec;
  } else if (natural >= playheadSec + minLeadSec &&
      natural < out.durationSec - 1) {
    targetOut = natural;
  } else {
    // Auto-advance "mix now": the natural outro cue is already behind the
    // playhead, so begin the blend *at the playhead* — NOT playhead+lead,
    // which would shove the mix-out to the track's final second and leave
    // no room (the whole transition would collapse into a hard cut). The
    // downbeat snap below nudges it forward by <1 beat to land on a bar.
    targetOut = playheadSec;
  }
  // never schedule into the past or off the end
  targetOut = targetOut.clamp(
    playheadSec + 0.5,
    (out.durationSec - 1).clamp(0.0, double.infinity),
  );
  // Clamp the chosen downbeat to durationSec-1: nextDownbeatAtOrAfter can
  // return a trailing downbeat inside the last bar, which would leave no
  // room for the transition and overrun the track end.
  final outMixOut = (outGrid.hasGrid
          ? outGrid.nextDownbeatAtOrAfter(targetOut)
          : targetOut)
      .clamp(0.0, (out.durationSec - 1).clamp(0.0, double.infinity));

  // ----- incoming mix-in -----
  final targetIn = incoming.cuePoints.mixInSec;
  final inMixIn = inGrid.hasGrid
      ? inGrid.nextDownbeatAtOrAfter(targetIn)
      : targetIn;

  return CueSelection(
    outMixOutSec: outMixOut,
    inMixInSec: inMixIn,
    outBeatPeriod: outGrid.beatPeriodSec,
    inBeatPeriod: inGrid.beatPeriodSec,
  );
}

/// Convert a desired transition length in *beats* to seconds on the
/// outgoing track's grid, and clamp it so it neither overruns the track end
/// nor undershoots a musically sensible minimum.
double beatsToDurationSec({
  required int beats,
  required double beatPeriod,
  required double mixOutSec,
  required double trackDurationSec,
  double minSec = 1.5,
}) {
  var dur = beats * beatPeriod;
  final room = trackDurationSec - mixOutSec - 0.2;
  if (dur > room) dur = room; // always cap to remaining audio
  if (room < minSec) {
    dur = room > 0 ? room : 0; // no musical room left: collapse, never overrun
  } else if (dur < minSec) {
    dur = minSec;
  }
  return dur;
}
