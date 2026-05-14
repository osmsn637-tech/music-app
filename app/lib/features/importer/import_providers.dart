import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database/providers.dart';
import 'import_service.dart';

final importServiceProvider = Provider<ImportService>((ref) {
  return ImportService(ref.watch(songRepositoryProvider));
});
