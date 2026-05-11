enum SyncItemStatus {
  pending,
  downloading,
  success,
  skipped,
  failed,
  deleted,
  repaired,
}

class SyncItem {
  const SyncItem({
    required this.id,
    required this.title,
    required this.status,
    this.bytesReceived = 0,
    this.bytesTotal = 0,
    this.error,
  });

  final String id;
  final String title;
  final SyncItemStatus status;
  final int bytesReceived;
  final int bytesTotal;
  final String? error;

  SyncItem copyWith({
    SyncItemStatus? status,
    int? bytesReceived,
    int? bytesTotal,
    String? error,
  }) {
    return SyncItem(
      id: id,
      title: title,
      status: status ?? this.status,
      bytesReceived: bytesReceived ?? this.bytesReceived,
      bytesTotal: bytesTotal ?? this.bytesTotal,
      error: error ?? this.error,
    );
  }
}

class SyncProgress {
  const SyncProgress({
    this.running = false,
    this.message,
    this.error,
    this.items = const [],
  });

  final bool running;
  final String? message;
  final String? error;
  final List<SyncItem> items;

  int get total => items.length;
  int get done =>
      items.where((i) => i.status == SyncItemStatus.success).length;
  int get skipped =>
      items.where((i) => i.status == SyncItemStatus.skipped).length;
  int get failed =>
      items.where((i) => i.status == SyncItemStatus.failed).length;
  int get deleted =>
      items.where((i) => i.status == SyncItemStatus.deleted).length;
  int get repaired =>
      items.where((i) => i.status == SyncItemStatus.repaired).length;

  SyncProgress copyWith({
    bool? running,
    String? message,
    String? error,
    List<SyncItem>? items,
  }) {
    return SyncProgress(
      running: running ?? this.running,
      message: message ?? this.message,
      error: error,
      items: items ?? this.items,
    );
  }
}
