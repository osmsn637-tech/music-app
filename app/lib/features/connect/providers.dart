import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database/app_database.dart';
import '../../data/database/providers.dart';
import 'connect_models.dart';
import 'connect_service.dart';

/// App-lifetime Live Connect client. Kept alive (not autoDispose) so the
/// WebSocket persists across screen changes. Instantiated lazily the first
/// time the shell / device-picker watches it.
final connectServiceProvider =
    StateNotifierProvider<ConnectService, ConnectUiState>((ref) {
      return ConnectService(ref);
    });

/// Resolves a song by id from the LOCAL library — used to label the active
/// remote's now-playing in the Connect sheet. Null when that song isn't
/// downloaded on this device.
final songByIdProvider = FutureProvider.autoDispose.family<SongRow?, String>(
  (ref, id) => ref.read(songRepositoryProvider).findById(id),
);
