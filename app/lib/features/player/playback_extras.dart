import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'now_playing_controller.dart';
import 'providers.dart';

/// Current playback speed (1.0 = normal). Setting it applies to the live
/// track and all subsequent ones via [PlayerService.setSpeed].
class SpeedController extends StateNotifier<double> {
  SpeedController(this._ref) : super(1.0);
  final Ref _ref;

  void set(double speed) {
    state = speed;
    _ref.read(playerServiceProvider).setSpeed(speed);
  }
}

final playbackSpeedProvider = StateNotifierProvider<SpeedController, double>(
  (ref) => SpeedController(ref),
);

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
