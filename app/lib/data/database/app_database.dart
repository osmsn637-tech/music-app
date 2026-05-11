import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'tables.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [
    Songs,
    SongStats,
    ListeningEvents,
    ContextStats,
    Playlists,
    PlaylistSongs,
    PronunciationFixes,
    RecentDjLines,
    DjSpeechCache,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_songs_search_text '
            'ON songs(search_text)',
          );
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_listening_events_song_id '
            'ON listening_events(song_id)',
          );
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_listening_events_created_at '
            'ON listening_events(created_at)',
          );
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_context_stats_song_context '
            'ON context_stats(song_id, context)',
          );
          await customStatement(
            'CREATE UNIQUE INDEX IF NOT EXISTS '
            'idx_pronunciation_fixes_original '
            'ON pronunciation_fixes(original_text)',
          );
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_recent_dj_lines_created_at '
            'ON recent_dj_lines(created_at)',
          );
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_dj_speech_cache_song_id '
            'ON dj_speech_cache(song_id)',
          );
        },
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.createTable(pronunciationFixes);
            await customStatement(
              'CREATE UNIQUE INDEX IF NOT EXISTS '
              'idx_pronunciation_fixes_original '
              'ON pronunciation_fixes(original_text)',
            );
          }
          if (from < 3) {
            await m.createTable(recentDjLines);
            await customStatement(
              'CREATE INDEX IF NOT EXISTS idx_recent_dj_lines_created_at '
              'ON recent_dj_lines(created_at)',
            );
          }
          if (from < 4) {
            await m.createTable(djSpeechCache);
            await customStatement(
              'CREATE INDEX IF NOT EXISTS idx_dj_speech_cache_song_id '
              'ON dj_speech_cache(song_id)',
            );
          }
        },
      );
}

QueryExecutor _openConnection() {
  return driftDatabase(name: 'music_app');
}
