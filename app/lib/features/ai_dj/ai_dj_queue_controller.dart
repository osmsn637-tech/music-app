import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../../core/services/providers.dart';
import '../../data/database/app_database.dart';
import '../../data/database/providers.dart';
import '../../data/models/remote_artist.dart';
import '../lyrics/lyrics_hook_extractor.dart';
import '../player/now_playing_controller.dart';
import '../player/providers.dart';
import 'ai_dj_service.dart';
import 'dj_intent_selector.dart';
import 'dj_mode.dart';
import 'dj_speech_types.dart';
import 'dj_voice_bank.dart';
import 'dj_voice_bank_player.dart';
import 'providers.dart';
import 'request_parser.dart';
import 'user_listening_profile.dart';

class AiDjQueueState {
  const AiDjQueueState({
    this.queue = const [],
    this.currentIndex = -1,
    this.mode = DjMode.general,
    this.loading = false,
    this.error,
    this.intent,
  });

  final List<AiDjQueueEntry> queue;
  final int currentIndex;
  final DjMode mode;
  final bool loading;
  final String? error;

  /// Latest free-text request the user submitted, if any. Surfaces back
  /// to the UI as pill chips so the user can see what the parser caught.
  final RequestIntent? intent;

  AiDjQueueEntry? get current =>
      currentIndex >= 0 && currentIndex < queue.length
      ? queue[currentIndex]
      : null;

  bool get isActive => currentIndex >= 0;

  AiDjQueueState copyWith({
    List<AiDjQueueEntry>? queue,
    int? currentIndex,
    DjMode? mode,
    bool? loading,
    String? error,
    bool clearError = false,
    RequestIntent? intent,
    bool clearIntent = false,
  }) {
    return AiDjQueueState(
      queue: queue ?? this.queue,
      currentIndex: currentIndex ?? this.currentIndex,
      mode: mode ?? this.mode,
      loading: loading ?? this.loading,
      error: clearError ? null : (error ?? this.error),
      intent: clearIntent ? null : (intent ?? this.intent),
    );
  }
}

class AiDjQueueController extends StateNotifier<AiDjQueueState> {
  AiDjQueueController(this._ref) : super(const AiDjQueueState()) {
    final ps = _ref.read(playerServiceProvider);
    _stateSub = ps.playerStateStream.listen(_onPlayerState);
    _posSub = ps.positionStream.listen(_onPosition);
    _durSub = ps.durationStream.listen(_onDuration);

    // Lockscreen / Bluetooth media-button bindings: route through the
    // queue controller so a "next" press from the notification gets the
    // same negative-signal treatment as the in-app skip button.
    final handler = _ref.read(audioHandlerProvider);
    if (handler != null) {
      handler.onSkipNextRequested = () async {
        if (state.isActive && state.currentIndex + 1 < state.queue.length) {
          await skip();
        } else {
          // Fall through to the generic library/artist queue so
          // lockscreen + Bluetooth "next" works when the user started
          // playback outside the AI DJ.
          await _ref.read(nowPlayingProvider.notifier).next();
        }
      };
      handler.onSkipPreviousRequested = () async {
        if (state.isActive && state.currentIndex > 0) {
          await playAt(state.currentIndex - 1);
        } else {
          await _ref.read(nowPlayingProvider.notifier).previous();
        }
      };
    }

    _watchdog = Timer.periodic(const Duration(seconds: 1), (_) => _tick());

    // Reactive ducking: the voice-bank player emits `true` while a clip is
    // playing and `false` when it ends. We mirror that onto the music decks
    // (0.55 while DJ talks, 1.0 once it's done).
    _attachVoiceBankSpeakingListener();
  }

  void _attachVoiceBankSpeakingListener() {
    _bankSpeakingSub?.cancel();
    final player = _ref.read(djVoiceBankPlayerProvider);
    final ps = _ref.read(playerServiceProvider);
    _bankSpeakingSub = player.isSpeakingStream.listen((speaking) {
      final target = speaking ? 0.55 : 1.0;
      debugPrint(
        '[aidj] voice-bank speaking=$speaking -> duck music to $target',
      );
      unawaited(ps.duckOutgoing(target));
    });
  }

  final Ref _ref;
  StreamSubscription<PlayerState>? _stateSub;
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<Duration?>? _durSub;
  StreamSubscription<bool>? _bankSpeakingSub;
  Timer? _watchdog;
  bool _advancing = false;
  Duration? _lastDuration;
  Duration _lastPosition = Duration.zero;

  /// Recently-played voice-bank clip IDs. Passed to the bank selector so
  /// it avoids picking the same clip on consecutive transitions — the
  /// selector previously was deterministic (highest score, alphabetical
  /// tie-break) which made the DJ repeat the same line every time for
  /// any given (song, intent, position) combo.
  final Queue<String> _recentClipIds = Queue<String>();
  static const int _recentClipMemory = 12;
  final math.Random _clipRng = math.Random();

  /// Crossfade duration when enabled.
  static const Duration _crossfadeWindow = Duration(seconds: 4);

  /// Disabled because just_audio's Android plugin doesn't reliably route
  /// volume calls when two AudioPlayer instances coexist. User-initiated
  /// nav uses the hard-cut path; auto-advance now also takes that path
  /// via the natural-completion listener.
  static const bool _crossfadeEnabled = false;

  /// When the current song's position crosses this, the queue advances
  /// with a crossfade. Re-armed on each new duration. Null for songs too
  /// short for a meaningful fade (they fall back to natural completion).
  Duration? _trigger;

  /// Cached during [generate] so the host bubble can read listening
  /// signals without re-querying the DB on every transition.
  UserListeningProfile? _profile;

  /// Selector is a const, free-of-state, thread-safe instance.
  static const DjIntentSelector _selector = DjIntentSelector();

  /// Set true when [skip] runs; consumed (and cleared) by the next call to
  /// [playAt] so the bank selector can use the `recoverFromSkip` intent
  /// for that single transition.
  bool _pendingSkipFlag = false;

  /// Pulls quotable snippets out of a song's `.lrc`. Cheap and stateless;
  /// kept around so the bank selector context can still see lyric hooks
  /// (a future bank-clip filter could match on `hasLyricHook`).
  final LyricsHookExtractor _hookExtractor = LyricsHookExtractor();

  /// Generates a fresh queue for [mode] using the current library + profile,
  /// resets currentIndex, and writes the active mode globally.
  Future<void> generate(DjMode mode) async {
    return _generateInternal(mode: mode, intent: null);
  }

  /// Generates a queue shaped by a free-text request ("chill, around 90 bpm,
  /// no vocals"). The parsed [RequestIntent] is stored on state so the UI
  /// can render what the parser actually understood as pill chips.
  Future<void> generateFromRequest(String prompt, DjMode mode) async {
    final intent = const RequestParser().parse(prompt);
    return _generateInternal(
      mode: mode,
      intent: intent.isEmpty ? null : intent,
    );
  }

  Future<void> _generateInternal({
    required DjMode mode,
    required RequestIntent? intent,
  }) async {
    state = state.copyWith(loading: true, mode: mode, clearError: true);
    try {
      final db = _ref.read(appDatabaseProvider);
      final songs = await db.select(db.songs).get();
      final profile = await UserListeningProfile.load(db);
      _profile = profile;
      final service = _ref.read(aiDjServiceProvider);
      final entries = service.buildQueue(
        songs: songs,
        mode: mode,
        profile: profile,
        intent: intent,
      );
      _ref.read(activeDjModeProvider.notifier).state = mode;
      state = AiDjQueueState(
        queue: entries,
        currentIndex: -1,
        mode: mode,
        intent: intent,
      );
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
    }
  }

  /// Plays the queued entry at [index] and marks the queue as active. If the
  /// DJ voice toggle is on and a matching bank clip exists, plays the clip
  /// before the song. No clip → silent transition.
  Future<void> playAt(int index, {bool crossfade = false}) async {
    if (index < 0 || index >= state.queue.length) return;
    final previousEntry = state.isActive
        ? state.queue[state.currentIndex]
        : null;
    final nextEntry = index + 1 < state.queue.length
        ? state.queue[index + 1]
        : null;
    state = state.copyWith(currentIndex: index);
    final entry = state.queue[index];
    final voiceEnabled = _ref.read(djVoiceProvider);

    final cameFromSkip = _pendingSkipFlag;
    _pendingSkipFlag = false;

    // On any non-opener transition, stop the current deck *before* the DJ
    // speaks. Otherwise the skipped (or pre-cued) song keeps playing for
    // the 3–5s the DJ clip lasts, which the user hears as "DJ talking
    // over the next song". Natural completion is a no-op here (the deck
    // is already stopped); pre-trigger advance trims ~400ms of tail; user
    // skip becomes immediate, which is exactly what skip should feel like.
    if (previousEntry != null) {
      try {
        await _ref.read(playerServiceProvider).stop();
      } catch (e) {
        debugPrint('[aidj] pre-DJ stop failed (non-fatal): $e');
      }
    }

    if (voiceEnabled) {
      final hook = await _hookExtractor.extract(entry.song.localLyricsPath);

      var ctx = DjSpeechContext(
        song: entry.song,
        previousSong: previousEntry?.song,
        nextSong: nextEntry?.song,
        mode: state.mode,
        queueIndex: index,
        queueLength: state.queue.length,
        queuePosition: getQueuePositionType(index, state.queue.length),
        profile: _profile ?? UserListeningProfile.empty(),
        now: DateTime.now(),
        cameFromSkip: cameFromSkip,
        firstLyricLine: hook.firstLine,
        hookLyricLine: hook.hookLine,
        hookConfidence: hook.confidence,
      );
      final reason = _selector.select(ctx);
      ctx = ctx.withIntent(reason.intent, reason);

      final bankedLine = await _selectBankedLine(ctx);
      if (bankedLine != null) {
        // Always wait for the DJ clip to finish before starting the next
        // song. Previously we fire-and-forgot on mid-queue transitions,
        // which made the DJ talk *over* the next song's intro.
        final played = await _playBankedLine(
          bankedLine,
          awaitCompletion: true,
          crossfade: crossfade,
        );
        // Bail if the user triggered a different playAt while we awaited
        // the clip (set-start, lockscreen skip, etc.).
        if (played && state.currentIndex != index) {
          debugPrint(
            '[aidj] playAt($index) superseded by ${state.currentIndex}, bailing',
          );
          return;
        }
      }
    }

    await _ref
        .read(nowPlayingProvider.notifier)
        .playSong(
          entry.song,
          crossfade: crossfade ? _crossfadeWindow : Duration.zero,
        );
    if (state.currentIndex != index) {
      debugPrint('[aidj] playAt($index) post-playSong stale, returning');
      return;
    }
  }

  /// Returns a host-bubble line for the AI DJ screen's idle rotation.
  /// Pure read; safe to call from build() any number of times.
  String hostBubbleNow() {
    return _ref.read(djCommentaryProvider).hostBubble(
      mode: state.mode,
      profile: _profile ?? UserListeningProfile.empty(),
      now: DateTime.now(),
    );
  }

  Future<_BankedDjLine?> _selectBankedLine(DjSpeechContext ctx) async {
    try {
      final bank = await _ref.read(djVoiceBankProvider.future);
      if (bank.isEmpty) return null;
      final clip = bank.selector.selectForContext(
        ctx,
        excludeIds: _recentClipIds.toSet(),
        random: _clipRng,
      );
      if (clip == null) return null;

      final file = File(bank.resolvePath(clip));
      if (!await file.exists() || await file.length() == 0) {
        debugPrint('[aidj] voice-bank clip unavailable: ${clip.id}');
        return null;
      }
      return _BankedDjLine(bank: bank, clip: clip);
    } catch (e, st) {
      debugPrint('[aidj] voice-bank lookup failed (non-fatal): $e\n$st');
      return null;
    }
  }

  Future<bool> _playBankedLine(
    _BankedDjLine line, {
    required bool awaitCompletion,
    required bool crossfade,
  }) async {
    final player = _ref.read(djVoiceBankPlayerProvider);
    final ps = _ref.read(playerServiceProvider);

    if (crossfade) {
      // Duck the outgoing track so the bank clip rides over its tail.
      // Reactive duck listener will restore volume when the clip ends.
      await ps.duckOutgoing(0.3);
    }

    if (awaitCompletion) {
      try {
        final played = await player
            .play(line.bank, line.clip)
            .timeout(const Duration(seconds: 12));
        if (played) {
          _rememberClip(line.clip.id);
          debugPrint('[aidj] played local voice-bank clip ${line.clip.id}');
        }
        return played;
      } on TimeoutException {
        debugPrint('[aidj] local voice-bank clip timed out: ${line.clip.id}');
        return false;
      }
    }

    unawaited(() async {
      final played = await player.play(line.bank, line.clip);
      if (played) {
        _rememberClip(line.clip.id);
        debugPrint('[aidj] played local voice-bank clip ${line.clip.id}');
      }
    }());
    return true;
  }

  void _rememberClip(String id) {
    _recentClipIds.addLast(id);
    while (_recentClipIds.length > _recentClipMemory) {
      _recentClipIds.removeFirst();
    }
  }

  /// Advances to the next queued song, if any. Returns false when past end.
  Future<bool> next({bool crossfade = false}) async {
    final nextIndex = state.currentIndex + 1;
    if (nextIndex >= state.queue.length) {
      state = state.copyWith(currentIndex: -1);
      return false;
    }
    await playAt(nextIndex, crossfade: crossfade);
    return true;
  }

  /// User-initiated skip during an active queue. Re-scores everything past
  /// the immediate-next entry against the song being skipped (negative
  /// signal: same artist/album/bpm/mood get pushed down) before advancing.
  Future<bool> skip() async {
    _pendingSkipFlag = true;
    if (!state.isActive) return next();
    final currentIdx = state.currentIndex;
    if (currentIdx < 0 || currentIdx >= state.queue.length) {
      return next();
    }
    final skipped = state.queue[currentIdx].song;
    final reorderFrom = currentIdx + 2;
    if (reorderFrom < state.queue.length) {
      final preserved = state.queue.sublist(0, reorderFrom);
      final tail = [...state.queue.sublist(reorderFrom)]
        ..sort((a, b) {
          final aEff = a.score + _signalDemerit(a.song, skipped);
          final bEff = b.score + _signalDemerit(b.song, skipped);
          return bEff.compareTo(aEff);
        });
      state = state.copyWith(queue: [...preserved, ...tail]);
    }
    return next();
  }

  /// Stops queue playback without clearing the queue.
  void deactivate() {
    state = state.copyWith(currentIndex: -1);
  }

  /// Negative-signal overlay applied to a candidate when the user just
  /// skipped [skipped]. Multi-artist fields are split so a "Drake, 21
  /// Savage" skip also demerits Drake-solo and 21-Savage-solo candidates.
  static int _signalDemerit(SongRow candidate, SongRow skipped) {
    var demerit = 0;
    final candidateArtists = splitMultiArtist(candidate.artist).toSet();
    final skippedArtists = splitMultiArtist(skipped.artist);
    if (candidateArtists.isNotEmpty &&
        skippedArtists.any(candidateArtists.contains)) {
      demerit -= 40;
    }
    final cAlb = candidate.album;
    final sAlb = skipped.album;
    if (cAlb != null && cAlb.isNotEmpty && cAlb == sAlb) demerit -= 20;
    final cBpm = candidate.bpm;
    final sBpm = skipped.bpm;
    if (cBpm != null && sBpm != null && (cBpm - sBpm).abs() <= 10) {
      demerit -= 15;
    }
    final cm = candidate.mood;
    final sm = skipped.mood;
    if (cm != null && cm.isNotEmpty && cm == sm) demerit -= 10;
    return demerit;
  }

  void _onPlayerState(PlayerState ps) {
    if (ps.processingState != ProcessingState.completed) return;
    debugPrint(
      '[aidj] completed event '
      'isActive=${state.isActive} advancing=$_advancing '
      'idx=${state.currentIndex}/${state.queue.length}',
    );
    if (!state.isActive) return;
    if (_advancing) return;
    _advancing = true;
    next(crossfade: false).whenComplete(() => _advancing = false);
  }

  /// Watchdog tick. Trips when the song has clearly finished (position
  /// at or past duration) but neither completion nor the position trigger
  /// advanced the queue.
  void _tick() {
    if (!state.isActive) return;
    if (_advancing) return;
    final d = _lastDuration;
    if (d == null || d == Duration.zero) return;
    if (_lastPosition + const Duration(milliseconds: 250) < d) return;
    if (state.currentIndex + 1 >= state.queue.length) return;
    debugPrint(
      '[aidj] watchdog firing advance — pos=${_lastPosition.inMilliseconds}ms '
      'duration=${d.inMilliseconds}ms idx=${state.currentIndex}',
    );
    _advancing = true;
    next(crossfade: false).whenComplete(() => _advancing = false);
  }

  void _onDuration(Duration? d) {
    _trigger = null;
    _lastDuration = d;
    if (d == null || d == Duration.zero) return;
    if (_crossfadeEnabled && d > _crossfadeWindow * 2) {
      _trigger = d - _crossfadeWindow;
      return;
    }
    if (d > const Duration(seconds: 1)) {
      _trigger = d - const Duration(milliseconds: 400);
    }
  }

  void _onPosition(Duration pos) {
    _lastPosition = pos;
    if (!state.isActive) return;
    if (_advancing) return;
    final t = _trigger;
    if (t == null) return;
    if (pos < t) return;
    final hasNext = state.currentIndex + 1 < state.queue.length;
    if (!hasNext) {
      _trigger = null;
      return;
    }
    _advancing = true;
    _trigger = null;
    final useFade = _crossfadeEnabled;
    next(crossfade: useFade).whenComplete(() => _advancing = false);
  }

  @override
  void dispose() {
    _watchdog?.cancel();
    _stateSub?.cancel();
    _posSub?.cancel();
    _durSub?.cancel();
    _bankSpeakingSub?.cancel();
    super.dispose();
  }
}

class _BankedDjLine {
  const _BankedDjLine({required this.bank, required this.clip});

  final DjVoiceBank bank;
  final DjVoiceClip clip;
}
