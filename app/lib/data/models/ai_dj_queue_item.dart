import '../database/app_database.dart';

class AiDjQueueItem {
  const AiDjQueueItem({
    required this.song,
    required this.score,
    required this.reason,
  });

  final SongRow song;
  final int score;
  final String reason;
}
