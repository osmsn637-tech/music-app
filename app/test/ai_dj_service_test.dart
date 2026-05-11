import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:music_app/data/database/app_database.dart';
import 'package:music_app/features/ai_dj/ai_dj_service.dart';
import 'package:music_app/features/ai_dj/dj_mode.dart';
import 'package:music_app/features/ai_dj/user_listening_profile.dart';

SongRow _song({
  required String id,
  String title = 'Song',
  String? artist = 'A',
  String? mood,
  int? bpm,
  int isFavorite = 0,
}) {
  return SongRow(
    id: id,
    title: title,
    artist: artist,
    album: null,
    genre: null,
    mood: mood,
    bpm: bpm,
    durationMs: 200000,
    fileName: '$id.mp3',
    localFilePath: '/dev/null/$id.mp3',
    localLyricsPath: null,
    localArtworkPath: null,
    searchText: null,
    addedAt: null,
    lastPlayedAt: null,
    isFavorite: isFavorite,
  );
}

UserListeningProfile _profile({
  Set<String> favorites = const {},
  Map<String, int> playCount = const {},
  Map<String, int> completeCount = const {},
  Map<String, int> skipCount = const {},
  Map<String, int> replayCount = const {},
  Map<String, DateTime> lastPlayed = const {},
  List<String> topArtists = const [],
  Map<String, Map<String, int>> contextComplete = const {},
  DateTime? now,
}) {
  return UserListeningProfile(
    playCountById: playCount,
    completeCountById: completeCount,
    skipCountById: skipCount,
    replayCountById: replayCount,
    totalListenedMsById: const {},
    lastPlayedById: lastPlayed,
    favoriteSongIds: favorites,
    topArtists: topArtists,
    topGenres: const [],
    topMoods: const [],
    contextCompleteCountById: contextComplete,
    contextSkipCountById: const {},
    now: now ?? DateTime(2026, 4, 27, 12),
  );
}

void main() {
  final service = AiDjService(random: math.Random(42));

  group('AiDjService.scoreSong', () {
    test('favorite + completed sums to 75', () {
      final song = _song(id: 'a');
      final p = _profile(
        favorites: {'a'},
        completeCount: {'a': 3},
      );
      final scored = service.scoreSong(
        song: song, mode: DjMode.smartShuffle, profile: p);
      expect(scored.total, 75);
      expect(scored.components.map((c) => c.key),
          containsAll(['favorite', 'completed']));
    });

    test('skipped subtracts 35', () {
      final song = _song(id: 'a');
      final p = _profile(skipCount: {'a': 3});
      final scored = service.scoreSong(
        song: song, mode: DjMode.smartShuffle, profile: p);
      expect(scored.total, -35);
    });

    test('played recently subtracts 25', () {
      final song = _song(id: 'a');
      final now = DateTime(2026, 4, 27, 12);
      final p = _profile(
        lastPlayed: {'a': now.subtract(const Duration(minutes: 30))},
        now: now,
      );
      final scored = service.scoreSong(
        song: song, mode: DjMode.smartShuffle, profile: p);
      expect(scored.total, -25);
    });

    test('Workout mode awards +20 for high BPM', () {
      final song = _song(id: 'a', bpm: 140);
      final p = _profile();
      final scored = service.scoreSong(
        song: song, mode: DjMode.workout, profile: p);
      expect(scored.components.any((c) => c.key == 'workout_high_bpm'), isTrue);
      expect(scored.total, 20);
    });

    test('Study mode awards +20 for calm mood and penalizes high BPM', () {
      final calm = _song(id: 'a', mood: 'study', bpm: 80);
      final loud = _song(id: 'b', mood: 'workout', bpm: 150);
      final p = _profile();
      final calmScore = service
          .scoreSong(song: calm, mode: DjMode.study, profile: p)
          .total;
      final loudScore = service
          .scoreSong(song: loud, mode: DjMode.study, profile: p)
          .total;
      expect(calmScore, greaterThan(loudScore));
    });

    test('Discover mode awards +30 for never-played', () {
      final song = _song(id: 'a');
      final p = _profile(); // empty playCount → never played
      final scored = service.scoreSong(
        song: song, mode: DjMode.discover, profile: p);
      expect(scored.components.any((c) => c.key == 'discover_new'), isTrue);
      expect(scored.total >= 30, isTrue);
    });

    test('mood_match awards +25 when song.mood matches DJ mode', () {
      final song = _song(id: 'a', mood: 'workout');
      final p = _profile();
      final scored = service.scoreSong(
        song: song, mode: DjMode.workout, profile: p);
      expect(scored.components.any((c) => c.key == 'mood_match'), isTrue);
    });

    test('favorite_artist awards +15 only when artist is top-3', () {
      final byTop = _song(id: 'a', artist: 'Top');
      final byOther = _song(id: 'b', artist: 'Other');
      final p = _profile(topArtists: ['Top', 'Two', 'Three', 'Four']);
      final topScore = service
          .scoreSong(song: byTop, mode: DjMode.smartShuffle, profile: p)
          .total;
      final otherScore = service
          .scoreSong(song: byOther, mode: DjMode.smartShuffle, profile: p)
          .total;
      expect(topScore, 15);
      expect(otherScore, 0);
    });
  });

  group('AiDjService.buildQueue', () {
    test('Favorites mode only includes favorited songs', () {
      final songs = [
        _song(id: 'a', isFavorite: 1),
        _song(id: 'b', isFavorite: 0),
        _song(id: 'c', isFavorite: 1),
      ];
      final p = _profile(favorites: {'a', 'c'});
      final queue = service.buildQueue(
        songs: songs, mode: DjMode.favorites, profile: p);
      expect(queue.map((q) => q.song.id).toSet(), {'a', 'c'});
    });

    test('Discover mode excludes skipped songs', () {
      final songs = [
        _song(id: 'a'),
        _song(id: 'b'),
      ];
      final p = _profile(skipCount: {'a': 5});
      final queue = service.buildQueue(
        songs: songs, mode: DjMode.discover, profile: p);
      expect(queue.map((q) => q.song.id), ['b']);
    });

    test('Limit caps the queue length', () {
      final songs =
          List.generate(50, (i) => _song(id: '$i', isFavorite: 1));
      final p = _profile(favorites: songs.map((s) => s.id).toSet());
      final queue = service.buildQueue(
        songs: songs,
        mode: DjMode.favorites,
        profile: p,
        limit: 10,
      );
      expect(queue, hasLength(10));
    });

    test('Sorts by score descending', () {
      final songs = [
        _song(id: 'high', mood: 'workout', bpm: 140), // workout match + bpm
        _song(id: 'mid', mood: 'workout'),            // mood match only
      ];
      final p = _profile();
      final queue = service.buildQueue(
          songs: songs, mode: DjMode.workout, profile: p);
      expect(queue.first.song.id, 'high');
      expect(queue.last.song.id, 'mid');
    });

    test('Smart Shuffle keeps zero-score songs (so library is exhaustible)',
        () {
      final songs = [
        _song(id: 'a'),
        _song(id: 'b'),
        _song(id: 'c'),
      ];
      final p = _profile();
      final queue = service.buildQueue(
          songs: songs, mode: DjMode.smartShuffle, profile: p);
      expect(queue.map((q) => q.song.id).toSet(), {'a', 'b', 'c'});
    });
  });

  group('AiDjService.explainChoice', () {
    test('produces a non-empty reason for every common case', () {
      final cases = <ScoredSong>[
        ScoredSong(
          song: _song(id: 'a'),
          components: const [
            ScoreComponent(key: 'discover_new', label: '', points: 30),
          ],
        ),
        ScoredSong(
          song: _song(id: 'b'),
          components: const [
            ScoreComponent(key: 'favorite', label: '', points: 50),
            ScoreComponent(key: 'mood_match', label: '', points: 25),
          ],
        ),
        ScoredSong(
          song: _song(id: 'c'),
          components: const [
            ScoreComponent(key: 'workout_high_bpm', label: '', points: 20),
            ScoreComponent(key: 'completed', label: '', points: 25),
          ],
        ),
        ScoredSong(
          song: _song(id: 'd'),
          components: const [
            ScoreComponent(key: 'mood_match', label: '', points: 25),
          ],
        ),
        ScoredSong(
          song: _song(id: 'e'),
          components: const [
            ScoreComponent(key: 'favorite', label: '', points: 50),
          ],
        ),
        ScoredSong(
          song: _song(id: 'f'),
          components: const [
            ScoreComponent(key: 'high_play_count', label: '', points: 10),
          ],
        ),
      ];
      for (final s in cases) {
        final r = service.explainChoice(scored: s, mode: DjMode.smartShuffle);
        expect(r.isNotEmpty, isTrue, reason: 'case ${s.song.id}');
      }
    });

    test('falls back to a generic reason when no positive components', () {
      final s = ScoredSong(song: _song(id: 'a'), components: const []);
      final r = service.explainChoice(scored: s, mode: DjMode.smartShuffle);
      expect(r, isNotEmpty);
    });
  });
}
