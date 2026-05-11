import 'dart:io';

import '../../data/database/app_database.dart';
import '../../data/models/lyric_line.dart';
import 'lrc_parser.dart';

class LyricsResult {
  const LyricsResult.synced(this.lines)
      : plainText = null,
        kind = LyricsKind.synced;

  const LyricsResult.plain(String text)
      : lines = const [],
        plainText = text,
        kind = LyricsKind.plain;

  const LyricsResult.none()
      : lines = const [],
        plainText = null,
        kind = LyricsKind.none;

  final LyricsKind kind;
  final List<LyricLine> lines;
  final String? plainText;
}

enum LyricsKind { synced, plain, none }

class LyricsLoader {
  /// Reads [SongRow.localLyricsPath] and returns parsed lyrics. Falls back
  /// to plain text if the file isn't an LRC, and finally to "no lyrics".
  Future<LyricsResult> loadFor(SongRow song) async {
    final path = song.localLyricsPath;
    if (path == null) return const LyricsResult.none();

    final file = File(path);
    if (!await file.exists()) return const LyricsResult.none();

    final content = await file.readAsString();
    if (content.trim().isEmpty) return const LyricsResult.none();

    if (path.toLowerCase().endsWith('.lrc')) {
      final lines = LrcParser.parse(content);
      if (lines.isNotEmpty) return LyricsResult.synced(lines);
      // .lrc file without any timestamps — treat the body as plain text.
      return LyricsResult.plain(content.trim());
    }

    // Any other extension (.txt, etc.) — show as plain text.
    return LyricsResult.plain(content.trim());
  }
}
