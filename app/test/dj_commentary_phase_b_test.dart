import 'dart:math' as math;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_app/data/database/app_database.dart';
import 'package:music_app/features/ai_dj/dj_commentary.dart';
import 'package:music_app/features/ai_dj/dj_intent_selector.dart';
import 'package:music_app/features/ai_dj/dj_mode.dart';
import 'package:music_app/features/ai_dj/dj_speech_types.dart';
import 'package:music_app/features/ai_dj/recent_dj_lines_service.dart';
import 'package:music_app/features/ai_dj/user_listening_profile.dart';

SongRow _song({
  required String id,
  String title = 'Song',
  String? artist = 'A',
  String? album,
  String? genre,
  String? mood,
  int? bpm,
  int isFavorite = 0,
}) {
  return SongRow(
    id: id,
    title: title,
    artist: artist,
    album: album,
    genre: genre,
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
  Map<String, DateTime> lastPlayed = const {},
  List<String> topArtists = const [],
  DateTime? now,
}) {
  return UserListeningProfile(
    playCountById: playCount,
    completeCountById: const {},
    skipCountById: const {},
    replayCountById: const {},
    totalListenedMsById: const {},
    lastPlayedById: lastPlayed,
    favoriteSongIds: favorites,
    topArtists: topArtists,
    topGenres: const [],
    topMoods: const [],
    contextCompleteCountById: const {},
    contextSkipCountById: const {},
    now: now ?? DateTime(2026, 4, 29, 12),
  );
}

DjSpeechContext _ctx({
  required SongRow song,
  SongRow? previous,
  DjMode mode = DjMode.smartShuffle,
  int queueIndex = 5,
  int queueLength = 20,
  bool cameFromSkip = false,
  UserListeningProfile? profile,
  DateTime? now,
}) {
  final n = now ?? DateTime(2026, 4, 29, 12);
  return DjSpeechContext(
    song: song,
    previousSong: previous,
    nextSong: null,
    mode: mode,
    queueIndex: queueIndex,
    queueLength: queueLength,
    queuePosition: getQueuePositionType(queueIndex, queueLength),
    profile: profile ?? _profile(now: n),
    now: n,
    cameFromSkip: cameFromSkip,
  );
}

void main() {
  group('getQueuePositionType', () {
    test('index 0 is opener', () {
      expect(getQueuePositionType(0, 10), QueuePositionType.opener);
    });
    test('last index is closer', () {
      expect(getQueuePositionType(9, 10), QueuePositionType.closer);
    });
    test('first quarter is early', () {
      expect(getQueuePositionType(1, 20), QueuePositionType.early);
      expect(getQueuePositionType(4, 20), QueuePositionType.early);
    });
    test('middle half is middle', () {
      expect(getQueuePositionType(10, 20), QueuePositionType.middle);
      expect(getQueuePositionType(14, 20), QueuePositionType.middle);
    });
    test('last quarter (excluding closer) is late', () {
      expect(getQueuePositionType(15, 20), QueuePositionType.late);
      expect(getQueuePositionType(18, 20), QueuePositionType.late);
    });
    test('zero-length returns opener', () {
      expect(getQueuePositionType(0, 0), QueuePositionType.opener);
    });
  });

  group('DjIntentSelector', () {
    const selector = DjIntentSelector();

    test('opener position picks introSet', () {
      final r = selector.select(_ctx(
        song: _song(id: 'a'),
        queueIndex: 0,
        queueLength: 10,
      ));
      expect(r.intent, DjIntent.introSet);
      expect(r.code, 'queue_opener');
    });

    test('closer position picks setCloser', () {
      final r = selector.select(_ctx(
        song: _song(id: 'a'),
        queueIndex: 9,
        queueLength: 10,
      ));
      expect(r.intent, DjIntent.setCloser);
    });

    test('cameFromSkip beats history signals', () {
      // Without skip flag, a never-played track should pick discovery.
      final base = _ctx(song: _song(id: 'a'));
      expect(selector.select(base).intent, DjIntent.discovery);
      // With skip flag, recoverFromSkip wins.
      final withSkip = _ctx(song: _song(id: 'a'), cameFromSkip: true);
      expect(selector.select(withSkip).intent, DjIntent.recoverFromSkip);
    });

    test('opener beats cameFromSkip (structural override)', () {
      final r = selector.select(_ctx(
        song: _song(id: 'a'),
        queueIndex: 0,
        queueLength: 10,
        cameFromSkip: true,
      ));
      expect(r.intent, DjIntent.introSet);
    });

    test('favorite track picks favoriteReturn over default', () {
      final r = selector.select(_ctx(
        song: _song(id: 'a'),
        profile: _profile(
          favorites: const {'a'},
          // Mark as previously played so discovery (weight 70) doesn't fire.
          playCount: const {'a': 5},
          now: DateTime(2026, 4, 29, 12),
        ),
      ));
      expect(r.intent, DjIntent.favoriteReturn);
    });

    test('throwback fires when lastPlayed > 30 days ago', () {
      final now = DateTime(2026, 4, 29);
      final r = selector.select(_ctx(
        song: _song(id: 'a'),
        now: now,
        profile: _profile(
          playCount: const {'a': 1},
          lastPlayed: {'a': now.subtract(const Duration(days: 60))},
          now: now,
        ),
      ));
      expect(r.intent, DjIntent.throwback);
    });

    test('workout mode high-BPM picks workoutBoost', () {
      // Avoid favorites / discovery so the workout signal wins on weight.
      final r = selector.select(_ctx(
        song: _song(id: 'a', bpm: 140),
        mode: DjMode.workout,
        profile: _profile(playCount: const {'a': 5}, now: DateTime(2026, 4, 29, 12)),
      ));
      expect(r.intent, DjIntent.workoutBoost);
    });

    test('study mode + calm mood picks studyFocus', () {
      final r = selector.select(_ctx(
        song: _song(id: 'a', mood: 'lofi'),
        mode: DjMode.study,
        profile: _profile(playCount: const {'a': 5}, now: DateTime(2026, 4, 29, 12)),
      ));
      expect(r.intent, DjIntent.studyFocus);
    });

    test('previous-to-current BPM jump picks energyUp', () {
      // Mid-set, no other strong signals; tempo jump should win.
      final r = selector.select(_ctx(
        song: _song(id: 'b', bpm: 140),
        previous: _song(id: 'a', bpm: 90),
        profile: _profile(playCount: const {'b': 5}, now: DateTime(2026, 4, 29, 12)),
      ));
      expect(r.intent, DjIntent.energyUp);
    });

    test('default fallback is keepVibe', () {
      final r = selector.select(_ctx(
        song: _song(id: 'a'),
        profile: _profile(playCount: const {'a': 5}, now: DateTime(2026, 4, 29, 12)),
      ));
      expect(r.intent, DjIntent.keepVibe);
    });
  });

  group('DjCommentary.announce', () {
    test('produces a non-empty string and never says "AI" or "algorithm"', () async {
      final commentary = DjCommentary(random: math.Random(0));
      const selector = DjIntentSelector();
      final ctx = _ctx(song: _song(id: 'a', title: 'Test', artist: 'Tester'));
      final r = selector.select(ctx);
      final line = await commentary.announce(ctx.withIntent(r.intent, r));
      expect(line, isNotEmpty);
      final lower = line.toLowerCase();
      expect(lower.contains('algorithm'), isFalse);
      expect(lower.contains('as an ai'), isFalse);
      expect(lower.contains('listening history'), isFalse);
      expect(lower.contains('high score'), isFalse);
    });

    test('opener line mentions opening or starting', () async {
      // Force introSet at the opener — the first phrasing in that bucket
      // should be one of the spec opener variants.
      final commentary = DjCommentary(random: math.Random(0));
      const selector = DjIntentSelector();
      final ctx = _ctx(
        song: _song(id: 'a', title: 'First', artist: 'Tester'),
        queueIndex: 0,
        queueLength: 10,
      );
      final r = selector.select(ctx);
      expect(r.intent, DjIntent.introSet);
      final line = await commentary.announce(ctx.withIntent(r.intent, r));
      // The corpus uses words like "starting", "first", "alright", "lock in",
      // "scene". At least one should appear.
      final lower = line.toLowerCase();
      expect(
        lower.contains('start') ||
            lower.contains('first') ||
            lower.contains('alright') ||
            lower.contains('lock in') ||
            lower.contains('scene'),
        isTrue,
        reason: 'opener line should sound like an opener: "$line"',
      );
    });

    test('closer line mentions closing or ending', () async {
      final commentary = DjCommentary(random: math.Random(0));
      const selector = DjIntentSelector();
      final ctx = _ctx(
        song: _song(id: 'z', title: 'Last'),
        queueIndex: 9,
        queueLength: 10,
      );
      final r = selector.select(ctx);
      final line = await commentary.announce(ctx.withIntent(r.intent, r));
      final lower = line.toLowerCase();
      expect(
        lower.contains('clos') ||
            lower.contains('end') ||
            lower.contains('last') ||
            lower.contains('one more'),
        isTrue,
        reason: 'closer line should sound like a closer: "$line"',
      );
    });

    test('in-memory ring blocks repeats within a session', () async {
      final commentary = DjCommentary(random: math.Random(0));
      const selector = DjIntentSelector();
      final lines = <String>{};
      for (var i = 0; i < 5; i++) {
        final ctx = _ctx(
          song: _song(id: 's$i', title: 'T$i'),
          queueIndex: 5 + i,
          queueLength: 30,
        );
        final r = selector.select(ctx);
        final line = await commentary.announce(ctx.withIntent(r.intent, r));
        lines.add(line);
      }
      // Five consecutive lines under the same intent (keepVibe in this
      // setup, since profile is empty and position is mid) should produce
      // multiple distinct phrasings — we have 5 phrasings in that bucket
      // and the ring suppresses repeats.
      expect(lines.length, greaterThanOrEqualTo(2));
    });
  });

  group('RecentDjLinesService', () {
    late AppDatabase db;
    late RecentDjLinesService svc;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      svc = RecentDjLinesService(db);
    });

    tearDown(() async {
      await db.close();
    });

    test('record + recentTexts round-trips', () async {
      await svc.record(lineText: 'one', intent: 'keep_vibe');
      await svc.record(lineText: 'two', intent: 'keep_vibe');
      final recent = await svc.recentTexts();
      expect(recent, containsAll(<String>['one', 'two']));
    });

    test('clear empties the table', () async {
      await svc.record(lineText: 'one');
      await svc.clear();
      final recent = await svc.recentTexts();
      expect(recent, isEmpty);
    });
  });
}
