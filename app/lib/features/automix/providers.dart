import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../data/database/providers.dart';
import '../player/providers.dart';
import 'automix_service.dart';
import 'runtime/analysis_store.dart';
import 'runtime/sidecar_seeder.dart';

/// On-device directory that holds the `*.automix.json` sidecars. Seeded from
/// the bundled `assets/automix_analysis/` on first launch (see
/// [analysisStoreProvider]); a future server sync step could also drop newer
/// ones in here. Created if missing so the store can index an empty dir
/// without throwing.
final analysisDirProvider = FutureProvider<String>((ref) async {
  final base = await getApplicationSupportDirectory();
  final dir = Directory(p.join(base.path, 'automix_analysis'));
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
  return dir.path;
});

final analysisStoreProvider = FutureProvider<AnalysisStore>((ref) async {
  final dir = await ref.watch(analysisDirProvider.future);
  // Populate the dir from the bundled sidecars before indexing (no-op once
  // seeded). Without this, iOS/release builds would index an empty dir.
  await seedAutoMixSidecars(dir);
  return AnalysisStore(dir);
});

/// One-time backfill: copies each track's analyzed BPM from its AutoMix
/// sidecar into `songs.bpm`, so the per-song Tempo control can show and target
/// BPM. Idempotent — only fills songs that don't already have a BPM, so it's a
/// no-op on every launch after the first. Returns how many rows it filled.
final bpmBackfillProvider = FutureProvider<int>((ref) async {
  final store = await ref.watch(analysisStoreProvider.future);
  final repo = ref.read(songRepositoryProvider);
  final songs = await repo.getAll();
  final fills = <String, int>{};
  for (final s in songs) {
    if ((s.bpm ?? 0) > 0) continue; // already has a BPM
    final a = await store.forSong(s);
    final bpm = a?.bpm ?? 0;
    if (bpm > 0) fills[s.id] = bpm.round();
  }
  await repo.backfillBpm(fills);
  return fills.length;
});

/// The AutoMix engine entry point. `await ref.read(autoMixServiceProvider
/// .future)` from the player-page button; call `mixToNext(...)` and fall
/// back to a plain `playSong` when the outcome isn't [AutoMixOutcome.mixed].
final autoMixServiceProvider = FutureProvider<AutoMixService>((ref) async {
  final store = await ref.watch(analysisStoreProvider.future);
  final player = ref.watch(playerServiceProvider);
  return AutoMixService(player: player, analysis: store);
});

/// Whether auto-advance transitions use the AutoMix engine (beat-matched,
/// harmonic, stem/EQ-aware) instead of the simple linear crossfade. Toggled
/// by the player's Automix button; read in NowPlayingController._playInternal.
final autoMixEnabledProvider = StateProvider<bool>((ref) => false);

/// True while the engine is actively blending the outgoing + incoming tracks.
/// Set by [NowPlayingController] around `mixToNext`; drives the player's
/// "Mixing" glow + label on the progress bar.
final autoMixMixingProvider = StateProvider<bool>((ref) => false);
