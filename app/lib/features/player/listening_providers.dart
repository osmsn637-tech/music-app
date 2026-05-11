import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database/providers.dart';
import '../../data/repositories/listening_repository.dart';
import '../ai_dj/dj_mode.dart';
import '../ai_dj/providers.dart';
import 'listening_tracker.dart';
import 'providers.dart';

final listeningRepositoryProvider = Provider<ListeningRepository>((ref) {
  return ListeningRepository(ref.watch(appDatabaseProvider));
});

final listeningTrackerProvider = Provider<ListeningTracker>((ref) {
  final tracker = ListeningTracker(
    repo: ref.watch(listeningRepositoryProvider),
    contextResolver: () => ref.read(activeDjModeProvider).id,
  );

  // Wire to the player's position + state streams. We do this in the
  // provider body so the tracker stays alive for the app lifetime via the
  // provider container.
  final player = ref.watch(playerServiceProvider);
  final posSub = player.positionStream.listen((pos) {
    final dur = player.raw.duration;
    tracker.onPosition(pos, dur);
  });
  final stateSub = player.playerStateStream.listen((state) {
    if (state.playing) {
      tracker.onResumed();
    } else {
      tracker.onPaused();
    }
  });

  ref.onDispose(() {
    posSub.cancel();
    stateSub.cancel();
    tracker.flush();
  });

  return tracker;
});
