import '../player/playback_modes.dart';

/// Live Connect wire models — must stay byte-compatible with the FastAPI
/// service (`server/connect/app.py`, `protocol: 1`).

enum ConnectStatus { disconnected, connecting, connected }

QueueRepeatMode repeatFromWire(String? s) => switch (s) {
  'all' => QueueRepeatMode.all,
  'one' => QueueRepeatMode.one,
  _ => QueueRepeatMode.off,
};

/// The shared authoritative playback session. Outbound we only send the six
/// fields the server reads from a `state` push; inbound we parse the full
/// snapshot the server fans out.
class ConnectState {
  const ConnectState({
    required this.queueIds,
    required this.index,
    required this.positionMs,
    required this.playing,
    required this.shuffle,
    required this.repeat,
    this.activeDeviceId,
    this.seq = 0,
    this.positionAtEpochMs = 0,
  });

  final List<String> queueIds;
  final int index;
  final int positionMs;
  final bool playing;
  final bool shuffle;
  final QueueRepeatMode repeat;
  final String? activeDeviceId;
  final int seq;
  final int positionAtEpochMs;

  String? get currentSongId =>
      (index >= 0 && index < queueIds.length) ? queueIds[index] : null;

  /// Position extrapolated to [nowEpochMs]. The active device only re-pushes
  /// on events + a ~5s heartbeat, so [positionMs] is a checkpoint — while
  /// playing, add the wall-clock elapsed since [positionAtEpochMs] so a
  /// follower's progress bar (and a pulled handoff) lands on the live spot.
  int livePositionMs(int nowEpochMs) {
    if (!playing) return positionMs;
    final elapsed = nowEpochMs - positionAtEpochMs;
    final p = positionMs + (elapsed > 0 ? elapsed : 0);
    return p < 0 ? 0 : p;
  }

  factory ConnectState.fromJson(Map<String, dynamic> m) => ConnectState(
    queueIds: (m['queueIds'] as List?)?.map((e) => '$e').toList() ?? const [],
    index: (m['index'] as int?) ?? -1,
    positionMs: (m['positionMs'] as int?) ?? 0,
    playing: (m['playing'] as bool?) ?? false,
    shuffle: (m['shuffle'] as bool?) ?? false,
    repeat: repeatFromWire(m['repeat'] as String?),
    activeDeviceId: m['activeDeviceId'] as String?,
    seq: (m['seq'] as int?) ?? 0,
    positionAtEpochMs: (m['positionAtEpochMs'] as int?) ?? 0,
  );

  /// The subset the server reads from an inbound `state` push.
  Map<String, dynamic> toWireSession() => {
    'queueIds': queueIds,
    'index': index,
    'positionMs': positionMs,
    'playing': playing,
    'shuffle': shuffle,
    'repeat': repeat.name,
  };
}

/// A device in the room (roster entry).
class ConnectDevice {
  const ConnectDevice({
    required this.deviceId,
    required this.name,
    required this.platform,
    required this.canPlay,
    this.online = true,
  });

  final String deviceId;
  final String name;
  final String platform;
  final bool canPlay;
  final bool online;

  factory ConnectDevice.fromJson(Map<String, dynamic> m) => ConnectDevice(
    deviceId: m['deviceId'] as String? ?? '',
    name: m['deviceName'] as String? ?? 'Device',
    platform: m['platform'] as String? ?? 'unknown',
    canPlay: m['canPlay'] as bool? ?? true,
    online: m['online'] as bool? ?? true,
  );
}

/// Immutable snapshot the Connect UI watches.
class ConnectUiState {
  const ConnectUiState({
    this.status = ConnectStatus.disconnected,
    this.configured = false,
    this.selfDeviceId = '',
    this.selfName = '',
    this.devices = const [],
    this.activeDeviceId,
    this.session,
    this.error,
  });

  final ConnectStatus status;
  final bool configured; // a URL + room code are set in settings
  final String selfDeviceId;
  final String selfName;
  final List<ConnectDevice> devices; // peers (never includes self)
  final String? activeDeviceId;
  final ConnectState? session;
  final String? error;

  bool get connected => status == ConnectStatus.connected;
  bool get isSelfActive =>
      activeDeviceId != null && activeDeviceId == selfDeviceId;

  /// The active device when it's *another* device (null if it's us or idle).
  ConnectDevice? get activeRemote {
    final id = activeDeviceId;
    if (id == null || id == selfDeviceId) return null;
    for (final d in devices) {
      if (d.deviceId == id) return d;
    }
    return ConnectDevice(
      deviceId: id,
      name: 'Another device',
      platform: 'unknown',
      canPlay: true,
    );
  }

  ConnectUiState copyWith({
    ConnectStatus? status,
    bool? configured,
    String? selfDeviceId,
    String? selfName,
    List<ConnectDevice>? devices,
    Object? activeDeviceId = _sentinel,
    Object? session = _sentinel,
    Object? error = _sentinel,
  }) {
    return ConnectUiState(
      status: status ?? this.status,
      configured: configured ?? this.configured,
      selfDeviceId: selfDeviceId ?? this.selfDeviceId,
      selfName: selfName ?? this.selfName,
      devices: devices ?? this.devices,
      activeDeviceId: activeDeviceId == _sentinel
          ? this.activeDeviceId
          : activeDeviceId as String?,
      session: session == _sentinel ? this.session : session as ConnectState?,
      error: error == _sentinel ? this.error : error as String?,
    );
  }
}

const Object _sentinel = Object();
