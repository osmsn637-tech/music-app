import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_socket_channel/status.dart' as ws_status;
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../core/services/providers.dart';
import '../../data/database/app_database.dart';
import '../../data/database/providers.dart';
import '../player/now_playing_controller.dart';
import '../player/playback_modes.dart';
import '../player/player_service.dart';
import '../player/providers.dart';
import 'connect_models.dart';

const int _kProtocol = 1;

/// Live Connect client. Maintains the WebSocket to the handoff service,
/// mirrors local playback up when this device is the active one, and applies
/// inbound remote commands + transfers. Pure-observer outbound: it watches the
/// same playback providers the UI does, so the player code only needed one new
/// hook ([NowPlayingController.adoptRemote]).
class ConnectService extends StateNotifier<ConnectUiState> {
  ConnectService(this._ref) : super(const ConnectUiState()) {
    _init();
  }

  final Ref _ref;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _socketSub;

  String _url = '';
  String _room = '';
  String _deviceId = '';
  String _deviceName = '';

  int _seq = 0;
  bool _disposed = false;
  bool _manualClose = false;
  int _backoffMs = 1000;
  Timer? _reconnectTimer;
  Timer? _progressTimer;
  int _suppressUntilMs = 0;

  String? _pendingHandoffId;
  bool _pendingHandoffPlay = false;

  ProviderSubscription<PlaybackModes>? _modesSub;
  ProviderSubscription<SongRow?>? _nowSub;
  ProviderSubscription<AsyncValue<PlayerSnapshot>>? _playSub;
  VoidCallback? _queueListener;

  String get _platform {
    if (kIsWeb) return 'web';
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return 'ios';
      case TargetPlatform.android:
        return 'android';
      case TargetPlatform.macOS:
        return 'macos';
      case TargetPlatform.windows:
        return 'windows';
      case TargetPlatform.linux:
        return 'linux';
      default:
        return 'unknown';
    }
  }

  Future<void> _init() async {
    await _loadSettings();
    if (_url.isNotEmpty && _room.isNotEmpty) connect();
  }

  Future<void> _loadSettings() async {
    final s = await _ref.read(settingsServiceProvider.future);
    _deviceId = s.deviceId;
    _deviceName = s.deviceName;
    _url = s.connectUrl ?? '';
    _room = s.roomCode ?? '';
    if (_disposed) return;
    state = state.copyWith(
      configured: _url.isNotEmpty && _room.isNotEmpty,
      selfDeviceId: _deviceId,
      selfName: _deviceName,
    );
  }

  /// Re-read settings and reconnect — call after editing Live Connect settings.
  Future<void> applySettings() async {
    _teardownSocket();
    await _loadSettings();
    if (_url.isNotEmpty && _room.isNotEmpty) {
      _backoffMs = 1000;
      connect();
    } else {
      state = state.copyWith(status: ConnectStatus.disconnected);
    }
  }

  void connect() {
    if (_disposed || _url.isEmpty || _room.isEmpty) return;
    _manualClose = false;
    _reconnectTimer?.cancel();
    state = state.copyWith(status: ConnectStatus.connecting, error: null);
    try {
      final ch = WebSocketChannel.connect(Uri.parse(_url));
      _channel = ch;
      _socketSub = ch.stream.listen(
        _onData,
        onError: (Object e) => _onClosed('error: $e'),
        onDone: () => _onClosed('closed'),
        cancelOnError: true,
      );
      _send({
        'type': 'hello',
        'room': _room,
        'deviceId': _deviceId,
        'deviceName': _deviceName,
        'platform': _platform,
        'caps': {'canPlay': true},
        'protocol': _kProtocol,
        'resume': true,
      });
    } catch (e) {
      _onClosed('connect failed: $e');
    }
  }

  void disconnect() {
    _manualClose = true;
    _teardownSocket();
    state = state.copyWith(status: ConnectStatus.disconnected);
  }

  void _teardownSocket() {
    _reconnectTimer?.cancel();
    _progressTimer?.cancel();
    _detachObservers();
    _socketSub?.cancel();
    _socketSub = null;
    try {
      _channel?.sink.close(ws_status.normalClosure);
    } catch (_) {}
    _channel = null;
    _pendingHandoffId = null;
  }

  void _onClosed(String why) {
    _detachObservers();
    _progressTimer?.cancel();
    _channel = null;
    _socketSub = null;
    if (_disposed || _manualClose) {
      state = state.copyWith(status: ConnectStatus.disconnected);
      return;
    }
    state = state.copyWith(status: ConnectStatus.connecting, error: why);
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(milliseconds: _backoffMs), () {
      _backoffMs = (_backoffMs * 2).clamp(1000, 20000);
      connect();
    });
  }

  void _send(Map<String, dynamic> frame) {
    try {
      _channel?.sink.add(jsonEncode(frame));
    } catch (_) {}
  }

  // ── inbound ─────────────────────────────────────────────────────────────
  void _onData(dynamic raw) {
    Map<String, dynamic> m;
    try {
      m = jsonDecode(raw as String) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    switch (m['type']) {
      case 'welcome':
        _onWelcome(m);
      case 'state':
        _onState(m);
      case 'progress':
        _onProgress(m);
      case 'peer':
        _onPeer(m);
      case 'command':
        _onCommand(m);
      case 'transferBegin':
        _onTransferBegin(m);
      case 'transferCommit':
        _onTransferCommit(m);
      case 'nack':
        _onNack(m);
      case 'ping':
        _send({'type': 'pong', 't': m['t']});
      case 'error':
        state = state.copyWith(error: '${m['message']}');
    }
  }

  ConnectState _session(Map<String, dynamic> m) =>
      ConnectState.fromJson((m['session'] as Map).cast<String, dynamic>());

  void _onWelcome(Map<String, dynamic> m) {
    _backoffMs = 1000;
    final sess = _session(m);
    _seq = sess.seq;
    final peers = ((m['peers'] as List?) ?? const [])
        .map((e) => ConnectDevice.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
    state = state.copyWith(
      status: ConnectStatus.connected,
      devices: peers,
      activeDeviceId: sess.activeDeviceId,
      session: sess,
      error: null,
    );
    _attachObservers();
    _ensureProgressTimer();
    _pushState(); // claim an idle room if we boot already playing
  }

  void _onState(Map<String, dynamic> m) {
    final sess = _session(m);
    _seq = sess.seq;
    state = state.copyWith(session: sess, activeDeviceId: sess.activeDeviceId);
  }

  void _onProgress(Map<String, dynamic> m) {
    final cur = state.session;
    if (cur == null || m['activeDeviceId'] != cur.activeDeviceId) return;
    state = state.copyWith(
      session: ConnectState(
        queueIds: cur.queueIds,
        index: cur.index,
        positionMs: (m['positionMs'] as int?) ?? cur.positionMs,
        playing: (m['playing'] as bool?) ?? cur.playing,
        shuffle: cur.shuffle,
        repeat: cur.repeat,
        activeDeviceId: cur.activeDeviceId,
        seq: cur.seq,
        positionAtEpochMs: (m['atEpochMs'] as int?) ?? cur.positionAtEpochMs,
      ),
    );
  }

  void _onPeer(Map<String, dynamic> m) {
    final dev = ConnectDevice.fromJson(
      (m['device'] as Map).cast<String, dynamic>(),
    );
    final list = [...state.devices]
      ..removeWhere((d) => d.deviceId == dev.deviceId);
    if (m['event'] != 'leave') list.add(dev);
    state = state.copyWith(devices: list);
  }

  void _onNack(Map<String, dynamic> m) {
    final sess = m['session'];
    if (sess is Map) {
      final s = ConnectState.fromJson(sess.cast<String, dynamic>());
      _seq = s.seq;
      state = state.copyWith(session: s, activeDeviceId: s.activeDeviceId);
    }
  }

  /// Remote-control commands arrive here when WE are the active device.
  void _onCommand(Map<String, dynamic> m) {
    final c = _ref.read(nowPlayingProvider.notifier);
    final args = (m['args'] as Map?)?.cast<String, dynamic>() ?? const {};
    _suppress();
    switch (m['action']) {
      case 'play':
        c.resume();
      case 'pause':
        c.pause();
      case 'next':
        c.next();
      case 'prev':
        c.previous();
      case 'seek':
        c.seek(Duration(milliseconds: (args['positionMs'] as int?) ?? 0));
      case 'setShuffle':
        if (_ref.read(playbackModesProvider).shuffle !=
            (args['value'] == true)) {
          c.toggleShuffle();
        }
      case 'setRepeat':
        final target = repeatFromWire(args['value'] as String?);
        var guard = 0;
        while (_ref.read(playbackModesProvider).repeat != target &&
            guard++ < 3) {
          c.cycleRepeat();
        }
      case 'jumpTo':
        c.jumpTo((args['index'] as int?) ?? 0);
    }
  }

  Future<void> _onTransferBegin(Map<String, dynamic> m) async {
    final handoffId = m['handoffId'] as String?;
    if (m['to'] != _deviceId || handoffId == null) return; // not our target
    final sess = _session(m);
    _pendingHandoffId = handoffId;
    _pendingHandoffPlay = (m['play'] as bool?) ?? true;
    _suppress();
    await _ref
        .read(nowPlayingProvider.notifier)
        .adoptRemote(
          queueIds: sess.queueIds,
          index: sess.index,
          positionMs: (m['positionMs'] as int?) ?? sess.positionMs,
          shuffle: sess.shuffle,
          repeat: sess.repeat,
          play: false, // stage paused; commit starts it
        );
    _send({'type': 'transferReady', 'handoffId': handoffId});
  }

  void _onTransferCommit(Map<String, dynamic> m) {
    final sess = _session(m);
    _seq = sess.seq;
    final newActive = m['activeDeviceId'] as String?;
    final wasActive = state.isSelfActive;
    state = state.copyWith(session: sess, activeDeviceId: newActive);
    final c = _ref.read(nowPlayingProvider.notifier);
    if (newActive == _deviceId) {
      if (_pendingHandoffId == m['handoffId'] && _pendingHandoffPlay) {
        _suppress();
        c.resume();
      }
      _pendingHandoffId = null;
    } else if (wasActive) {
      _suppress();
      c.pause(); // we handed off — release audio, become a follower
    }
  }

  // ── outbound ────────────────────────────────────────────────────────────
  void _attachObservers() {
    _detachObservers();
    _ref
        .read(nowPlayingProvider.notifier)
        .queueView
        .addListener(_queueListener = _pushState);
    _modesSub = _ref.listen<PlaybackModes>(
      playbackModesProvider,
      (_, _) => _pushState(),
    );
    _nowSub = _ref.listen<SongRow?>(nowPlayingProvider, (_, _) => _pushState());
    _playSub = _ref.listen<AsyncValue<PlayerSnapshot>>(
      playerStateStreamProvider,
      (_, _) => _pushState(),
    );
  }

  void _detachObservers() {
    if (_queueListener != null) {
      try {
        _ref
            .read(nowPlayingProvider.notifier)
            .queueView
            .removeListener(_queueListener!);
      } catch (_) {}
      _queueListener = null;
    }
    _modesSub?.close();
    _modesSub = null;
    _nowSub?.close();
    _nowSub = null;
    _playSub?.close();
    _playSub = null;
  }

  void _ensureProgressTimer() {
    _progressTimer?.cancel();
    _progressTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _pushProgress(),
    );
  }

  bool get _suppressed =>
      DateTime.now().millisecondsSinceEpoch < _suppressUntilMs;

  void _suppress() =>
      _suppressUntilMs = DateTime.now().millisecondsSinceEpoch + 1200;

  ConnectState? _buildLocal() {
    final qv = _ref.read(nowPlayingProvider.notifier).queueView.value;
    if (qv.queue.isEmpty) return null;
    final modes = _ref.read(playbackModesProvider);
    final playing =
        _ref.read(playerStateStreamProvider).valueOrNull?.playing ?? false;
    final posMs =
        _ref.read(playerPositionProvider).valueOrNull?.inMilliseconds ?? 0;
    return ConnectState(
      queueIds: qv.queue.map((s) => s.id).toList(),
      index: qv.index,
      positionMs: posMs,
      playing: playing,
      shuffle: modes.shuffle,
      repeat: modes.repeat,
    );
  }

  /// Push the full session — only when we are (or can claim) the active device.
  void _pushState() {
    if (state.status != ConnectStatus.connected || _suppressed) return;
    final local = _buildLocal();
    if (local == null) return;
    final canClaim = state.activeDeviceId == null && local.playing;
    if (!(state.isSelfActive || canClaim)) return;
    _send({'type': 'state', 'baseSeq': _seq, 'session': local.toWireSession()});
  }

  void _pushProgress() {
    if (state.status != ConnectStatus.connected || _suppressed) return;
    if (!state.isSelfActive) return;
    final playing =
        _ref.read(playerStateStreamProvider).valueOrNull?.playing ?? false;
    final posMs =
        _ref.read(playerPositionProvider).valueOrNull?.inMilliseconds ?? 0;
    _send({
      'type': 'progress',
      'positionMs': posMs,
      'playing': playing,
      'atEpochMs': DateTime.now().millisecondsSinceEpoch,
      'seq': _seq,
    });
  }

  // ── UI actions ────────────────────────────────────────────────────────
  /// Pull the active remote session onto THIS device and continue from where
  /// it is *right now* — no need to push from the source device. Implemented
  /// as a self-targeted transfer (the server is symmetric: any device may
  /// issue a transfer), carrying the live-extrapolated position so we land on
  /// the exact spot instead of restarting the track.
  ///
  /// Returns false (without acting) when there's nothing playing remotely or
  /// the current song isn't downloaded on this device — offline-first, we can
  /// only continue a track we actually hold locally.
  Future<bool> continueHere() async {
    final sess = state.session;
    final songId = sess?.currentSongId;
    if (sess == null || songId == null) return false;
    if (state.isSelfActive) return true; // already playing here
    if (await _ref.read(songRepositoryProvider).findById(songId) == null) {
      return false; // not downloaded on this device
    }
    final posMs = sess.livePositionMs(DateTime.now().millisecondsSinceEpoch);
    _send({
      'type': 'transfer',
      'to': _deviceId, // claim ourselves
      'positionMs': posMs,
      'play': true,
      'cmdId': DateTime.now().microsecondsSinceEpoch.toString(),
    });
    return true;
  }

  /// Hand playback to [deviceId], carrying our current position.
  void transferTo(String deviceId) {
    final posMs =
        _ref.read(playerPositionProvider).valueOrNull?.inMilliseconds ??
        state.session?.positionMs ??
        0;
    _send({
      'type': 'transfer',
      'to': deviceId,
      'positionMs': posMs,
      'play': true,
      'cmdId': DateTime.now().microsecondsSinceEpoch.toString(),
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _teardownSocket();
    super.dispose();
  }
}
