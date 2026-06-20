import '../model/session_event.dart';

/// In-memory rolling buffer of live session events (spec: Real-Time Session
/// Analysis monitors). The player/UI feeds it interaction signals; the
/// context engine reads [recent]. A >30 min idle gap starts a fresh session.
///
/// This is additive: the player page (owned elsewhere) can call [record] from
/// its existing event hooks, but the engine also works off DB-bootstrapped
/// events if the monitor is never wired.
class SessionMonitor {
  SessionMonitor({
    this.retention = const Duration(hours: 2),
    this.sessionGap = const Duration(minutes: 30),
    DateTime Function() now = DateTime.now,
  }) : _now = now;

  final Duration retention;
  final Duration sessionGap;
  final DateTime Function() _now;

  final List<SessionEvent> _events = [];
  DateTime? _sessionStart;
  DateTime? _lastAt;

  /// Start of the current session (resets after an idle gap).
  DateTime? get sessionStart => _sessionStart;

  /// Record one interaction. Prunes anything older than [retention] and rolls
  /// the session start if the listener was idle longer than [sessionGap].
  void record(SessionEventType type, {String? songId, double? value}) {
    final at = _now();
    if (_sessionStart == null ||
        (_lastAt != null && at.difference(_lastAt!) > sessionGap)) {
      _sessionStart = at;
    }
    _lastAt = at;
    _events.add(SessionEvent(type: type, at: at, songId: songId, value: value));
    _prune(at);
  }

  /// Seed the buffer from persisted listening events (e.g. on app launch) so
  /// the very first evaluation isn't blind. [persisted] is `(eventType,
  /// createdAt, songId)` rows.
  void bootstrap(Iterable<({String type, DateTime at, String? songId})> rows) {
    for (final r in rows) {
      final t = SessionEventType.fromPersisted(r.type);
      if (t == null) continue;
      _events.add(SessionEvent(type: t, at: r.at, songId: r.songId));
      if (_sessionStart == null || r.at.isBefore(_sessionStart!)) {
        _sessionStart = r.at;
      }
      if (_lastAt == null || r.at.isAfter(_lastAt!)) _lastAt = r.at;
    }
    _events.sort((a, b) => a.at.compareTo(b.at));
    _prune(_now());
  }

  List<SessionEvent> get recent => List.unmodifiable(_events);

  void clear() {
    _events.clear();
    _sessionStart = null;
    _lastAt = null;
  }

  void _prune(DateTime now) {
    final cutoff = now.subtract(retention);
    _events.removeWhere((e) => e.at.isBefore(cutoff));
  }
}
