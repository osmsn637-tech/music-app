/// Normalised in-session interaction events the context engine reasons over
/// (spec: Real-Time Session Analysis monitors). A superset of the persisted
/// `ListeningEventType` strings plus the live UI signals (volume, search,
/// queue edits, rewind, interruptions) that aren't worth persisting but
/// matter for real-time state/fatigue inference.
enum SessionEventType {
  play,
  complete,
  skip,
  replay,
  pause,
  resume,
  rewind, // seek backward / replay-from-start gesture
  seekForward,
  volumeUp,
  volumeDown,
  search,
  queueAdd,
  queueRemove,
  queueReorder,
  manualSelect, // user hand-picked a track (vs auto-advance)
  favorite,
  unfavorite,
  addToPlaylist,
  interruption; // audio focus lost (call, other app, headphones out)

  /// Maps a persisted `listening_events.event_type` string (see
  /// [ListeningTracker]'s ListeningEventType) onto a session event type, so a
  /// session can be bootstrapped from the DB log. Returns null for unknown.
  static SessionEventType? fromPersisted(String s) => switch (s) {
        'play' => SessionEventType.play,
        'pause' => SessionEventType.pause,
        'complete' => SessionEventType.complete,
        'skip' => SessionEventType.skip,
        'replay' => SessionEventType.replay,
        'favorite' => SessionEventType.favorite,
        'unfavorite' => SessionEventType.unfavorite,
        'add_to_playlist' => SessionEventType.addToPlaylist,
        _ => null,
      };

  /// Events that signal *active* engagement (the user is touching the app).
  bool get isInteraction => switch (this) {
        SessionEventType.skip ||
        SessionEventType.rewind ||
        SessionEventType.seekForward ||
        SessionEventType.volumeUp ||
        SessionEventType.volumeDown ||
        SessionEventType.search ||
        SessionEventType.queueAdd ||
        SessionEventType.queueRemove ||
        SessionEventType.queueReorder ||
        SessionEventType.manualSelect ||
        SessionEventType.favorite ||
        SessionEventType.addToPlaylist =>
          true,
        _ => false,
      };

  /// Events that signal *churn* — restlessness with what's playing.
  bool get isChurn => switch (this) {
        SessionEventType.skip ||
        SessionEventType.search ||
        SessionEventType.queueRemove ||
        SessionEventType.queueReorder ||
        SessionEventType.rewind =>
          true,
        _ => false,
      };
}

/// One timestamped interaction. [songId] is the track in focus (nullable for
/// app-level events like search). [value] carries a magnitude where relevant
/// (e.g. volume delta, listened fraction at skip).
class SessionEvent {
  const SessionEvent({
    required this.type,
    required this.at,
    this.songId,
    this.value,
  });

  final SessionEventType type;
  final DateTime at;
  final String? songId;
  final double? value;

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'at': at.toIso8601String(),
        if (songId != null) 'songId': songId,
        if (value != null) 'value': value,
      };
}
