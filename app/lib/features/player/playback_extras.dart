import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'now_playing_controller.dart';

/// Sleep timer. State is the remaining [Duration], or null when inactive.
/// Pauses playback when it reaches zero.
class SleepTimerController extends StateNotifier<Duration?> {
  SleepTimerController(this._ref) : super(null);
  final Ref _ref;
  Timer? _ticker;

  void start(Duration total) {
    cancel();
    state = total;
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      final next = (state ?? Duration.zero) - const Duration(seconds: 1);
      if (next <= Duration.zero) {
        _ref.read(nowPlayingProvider.notifier).pause();
        cancel();
      } else {
        state = next;
      }
    });
  }

  void cancel() {
    _ticker?.cancel();
    _ticker = null;
    state = null;
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }
}

final sleepTimerProvider =
    StateNotifierProvider<SleepTimerController, Duration?>(
      (ref) => SleepTimerController(ref),
    );
