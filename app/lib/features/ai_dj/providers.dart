import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/providers.dart';
import '../../data/database/providers.dart';
import 'ai_dj_queue_controller.dart';
import 'ai_dj_service.dart';
import 'dj_commentary.dart';
import 'dj_mode.dart';
import 'dj_voice_bank_player.dart';
import 'recent_dj_lines_service.dart';

/// The DJ mode currently driving playback. Defaults to [DjMode.general] when
/// the user is just browsing the library; the AI DJ screen flips this when
/// the user starts a mode so listening events get tagged with the context.
final activeDjModeProvider = StateProvider<DjMode>((ref) => DjMode.general);

final aiDjServiceProvider = Provider<AiDjService>((ref) {
  return AiDjService();
});

/// Text-only commentary engine. Now used solely for the silent host-bubble
/// rotation on the AI DJ screen — TTS is gone, so per-track lines are no
/// longer generated through this path. Kept because the host bubble still
/// needs mode/time-aware idle copy.
final djCommentaryProvider = Provider<DjCommentary>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return DjCommentary(recentLines: RecentDjLinesService(db));
});

/// Local phone-only voice bank. The manifest lives at:
/// `<app_documents>/dj_voice_bank/manifest.json`
///
/// Audio files referenced by the manifest are resolved relative to that
/// folder and played directly from disk. No server, network, or runtime
/// synthesis is involved — this is the only DJ voice path the app supports.
final djVoiceBankStoreProvider = Provider<DjVoiceBankStore>((ref) {
  return DjVoiceBankStore();
});

final djVoiceBankProvider = FutureProvider<DjVoiceBank>((ref) {
  return ref.watch(djVoiceBankStoreProvider).load();
});

final djVoiceBankPlayerProvider = Provider<DjVoiceBankPlayer>((ref) {
  final player = DjVoiceBankPlayer();
  ref.onDispose(player.dispose);
  return player;
});

final aiDjQueueControllerProvider =
    StateNotifierProvider<AiDjQueueController, AiDjQueueState>((ref) {
      // Force the DJ-voice toggle to instantiate so its _hydrate() reads the
      // saved value from SharedPreferences. Without this, the toggle only
      // hydrates when Settings is opened, leaving fresh boots stuck off.
      ref.read(djVoiceProvider);
      return AiDjQueueController(ref);
    });
