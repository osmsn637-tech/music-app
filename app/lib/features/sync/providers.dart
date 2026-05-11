import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database/providers.dart';
import '../../data/sources/file_downloader.dart';
import '../../data/sources/manifest_api.dart';
import 'sync_models.dart';
import 'sync_service.dart';

final dioProvider = Provider<Dio>((ref) {
  final dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 5),
      receiveTimeout: const Duration(seconds: 30),
    ),
  );
  ref.onDispose(dio.close);
  return dio;
});

final manifestApiProvider = Provider<ManifestApi>((ref) {
  return ManifestApi(ref.watch(dioProvider));
});

final fileDownloaderProvider = Provider<FileDownloader>((ref) {
  return FileDownloader(ref.watch(dioProvider));
});

final syncServiceProvider = Provider<SyncService>((ref) {
  return SyncService(
    api: ref.watch(manifestApiProvider),
    downloader: ref.watch(fileDownloaderProvider),
    repo: ref.watch(songRepositoryProvider),
    db: ref.watch(appDatabaseProvider),
  );
});

class SyncController extends StateNotifier<SyncProgress> {
  SyncController(this._service) : super(const SyncProgress());

  final SyncService _service;

  Future<void> run(String baseUrl) async {
    if (state.running) return;
    await _service.sync(baseUrl: baseUrl, onProgress: (p) => state = p);
  }
}

final syncControllerProvider =
    StateNotifierProvider<SyncController, SyncProgress>((ref) {
  return SyncController(ref.watch(syncServiceProvider));
});
