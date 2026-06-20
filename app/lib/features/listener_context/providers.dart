import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database/providers.dart';
import '../automix/providers.dart';
import 'listener_context_service.dart';
import 'runtime/session_monitor.dart';

/// App-wide live session monitor. The player/UI feed it interaction events via
/// `record(...)`; the context service reads `recent`. Single instance so the
/// session window survives across screens.
final sessionMonitorProvider = Provider<SessionMonitor>((ref) {
  return SessionMonitor();
});

/// The Listener Context Engine entry point. `await ref.read(
/// listenerContextServiceProvider.future)` then call `evaluate(...)` with the
/// candidate pool to get the full context snapshot (mood, session state,
/// fatigue, target energy, queue ranking, AutoMix directives, profile).
final listenerContextServiceProvider =
    FutureProvider<ListenerContextService>((ref) async {
  final db = ref.watch(appDatabaseProvider);
  final analysis = await ref.watch(analysisStoreProvider.future);
  return ListenerContextService(db: db, analysis: analysis);
});
