import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Repeat behaviour for the generic playback queue.
enum QueueRepeatMode { off, all, one }

/// Shuffle + repeat state, kept separate from [nowPlayingProvider] (which
/// is just the current `SongRow?`) so the transport toggles can rebuild
/// without the whole player reacting to every song change.
class PlaybackModes {
  const PlaybackModes({
    this.shuffle = false,
    this.repeat = QueueRepeatMode.off,
    this.endless = false,
  });

  final bool shuffle;
  final QueueRepeatMode repeat;

  /// "Infinity": the queue never ends — when it runs out, it auto-continues
  /// with another album by the same artist (see [NowPlayingController]).
  final bool endless;

  PlaybackModes copyWith({bool? shuffle, QueueRepeatMode? repeat, bool? endless}) =>
      PlaybackModes(
        shuffle: shuffle ?? this.shuffle,
        repeat: repeat ?? this.repeat,
        endless: endless ?? this.endless,
      );
}

class PlaybackModesController extends StateNotifier<PlaybackModes> {
  PlaybackModesController() : super(const PlaybackModes());

  void toggleShuffle() => state = state.copyWith(shuffle: !state.shuffle);

  void toggleEndless() => state = state.copyWith(endless: !state.endless);

  void cycleRepeat() {
    final next = switch (state.repeat) {
      QueueRepeatMode.off => QueueRepeatMode.all,
      QueueRepeatMode.all => QueueRepeatMode.one,
      QueueRepeatMode.one => QueueRepeatMode.off,
    };
    state = state.copyWith(repeat: next);
  }

  /// Restore persisted modes on launch (no reshuffle — the saved queue
  /// order already reflects the shuffle state).
  void restore({
    required bool shuffle,
    required QueueRepeatMode repeat,
    bool endless = false,
  }) {
    state = PlaybackModes(shuffle: shuffle, repeat: repeat, endless: endless);
  }
}

final playbackModesProvider =
    StateNotifierProvider<PlaybackModesController, PlaybackModes>(
      (ref) => PlaybackModesController(),
    );
