import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/audio_handler.dart';
import '../../main.dart' show globalPlayerService, globalAudioHandler;
import 'player_service.dart';

/// The single PlayerService instance for the app, created in `main.dart`
/// before `runApp` so the audio_service handler can wrap it. Falls back
/// to constructing a fresh one if main hasn't run yet (e.g., test harness).
final playerServiceProvider = Provider<PlayerService>((ref) {
  final existing = globalPlayerService;
  if (existing != null) return existing;
  final fallback = PlayerService();
  ref.onDispose(fallback.dispose);
  return fallback;
});

/// The audio_service handler. Null on platforms where AudioService.init
/// was skipped (web/desktop) or where init failed. Callers that want to
/// publish MediaItems or register skip callbacks should null-check.
final audioHandlerProvider = Provider<AppAudioHandler?>((ref) {
  return globalAudioHandler;
});

final playerStateStreamProvider = StreamProvider<PlayerSnapshot>((ref) {
  return ref.watch(playerServiceProvider).playerStateStream;
});

final playerPositionProvider = StreamProvider<Duration>((ref) {
  return ref.watch(playerServiceProvider).positionStream;
});

final playerDurationProvider = StreamProvider<Duration?>((ref) {
  return ref.watch(playerServiceProvider).durationStream;
});
