import 'package:flutter_test/flutter_test.dart';
import 'package:music_app/data/database/app_database.dart';
import 'package:music_app/data/repositories/listening_repository.dart';
import 'package:music_app/features/player/listening_tracker.dart';

class _RecordedEvent {
  _RecordedEvent({
    required this.songId,
    required this.type,
    required this.context,
    this.positionMs,
    this.listenedMs,
  });
  final String songId;
  final String type;
  final String? context;
  final int? positionMs;
  final int? listenedMs;
}

class _FakeListeningRepository implements ListeningRepository {
  final events = <_RecordedEvent>[];

  @override
  Future<int> insertEvent({
    required String songId,
    required String eventType,
    String? context,
    int? positionMs,
    int? listenedMs,
  }) async {
    events.add(_RecordedEvent(
      songId: songId,
      type: eventType,
      context: context,
      positionMs: positionMs,
      listenedMs: listenedMs,
    ));
    return events.length;
  }

  @override
  Future<void> applyEventToStats({
    required String songId,
    required String eventType,
    String? context,
    int listenedMs = 0,
  }) async {}

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

SongRow _song({
  String id = 's1',
  String title = 'Song',
  int? durationMs = 200000, // 3:20
}) {
  return SongRow(
    id: id,
    title: title,
    artist: 'A',
    album: null,
    genre: null,
    mood: null,
    bpm: null,
    durationMs: durationMs,
    fileName: '$id.mp3',
    localFilePath: '/dev/null/$id.mp3',
    localLyricsPath: null,
    localArtworkPath: null,
    searchText: null,
    addedAt: null,
    lastPlayedAt: null,
    isFavorite: 0,
  );
}

ListeningTracker _make({
  required _FakeListeningRepository repo,
  required DateTime Function() now,
  String context = 'general',
}) {
  return ListeningTracker(
    repo: repo,
    contextResolver: () => context,
    now: now,
  );
}

void main() {
  group('ListeningTracker', () {
    test('emits "play" when a song starts', () async {
      final repo = _FakeListeningRepository();
      final tracker = _make(repo: repo, now: DateTime.now);
      await tracker.onSongChanged(_song(id: 'a'));
      expect(repo.events.single.type, 'play');
      expect(repo.events.single.songId, 'a');
      expect(repo.events.single.context, 'general');
    });

    test('"complete" fires once when position crosses 98%', () async {
      final repo = _FakeListeningRepository();
      final tracker = _make(repo: repo, now: DateTime.now);
      final song = _song(durationMs: 100000);
      await tracker.onSongChanged(song);
      // 50% — no complete yet
      await tracker.onPosition(
        const Duration(milliseconds: 50000),
        const Duration(milliseconds: 100000),
      );
      // 99% — complete fires
      await tracker.onPosition(
        const Duration(milliseconds: 99000),
        const Duration(milliseconds: 100000),
      );
      // Another tick after — should NOT fire again
      await tracker.onPosition(
        const Duration(milliseconds: 99500),
        const Duration(milliseconds: 100000),
      );
      final completes =
          repo.events.where((e) => e.type == 'complete').toList();
      expect(completes, hasLength(1));
    });

    test('"skip" fires when next song starts before 30s AND under 50%',
        () async {
      final repo = _FakeListeningRepository();
      final tracker = _make(repo: repo, now: DateTime.now);
      final a = _song(id: 'a', durationMs: 300000);
      final b = _song(id: 'b');

      await tracker.onSongChanged(a);
      await tracker.onPosition(
        const Duration(seconds: 10),
        const Duration(milliseconds: 300000),
      );
      await tracker.onSongChanged(b);

      final skips = repo.events
          .where((e) => e.type == 'skip' && e.songId == 'a')
          .toList();
      expect(skips, hasLength(1));
      expect(skips.single.positionMs, 10000);
    });

    test('skip does NOT fire if position passed 50%', () async {
      final repo = _FakeListeningRepository();
      final tracker = _make(repo: repo, now: DateTime.now);
      final short = _song(id: 'a', durationMs: 30000); // 30s song
      final next = _song(id: 'b');

      await tracker.onSongChanged(short);
      // 20s into a 30s song = 66%. Under 30s but over 50% → not a skip.
      await tracker.onPosition(
        const Duration(seconds: 20),
        const Duration(milliseconds: 30000),
      );
      await tracker.onSongChanged(next);

      expect(
        repo.events.where((e) => e.type == 'skip'),
        isEmpty,
      );
    });

    test('skip does NOT fire if completed first', () async {
      final repo = _FakeListeningRepository();
      final tracker = _make(repo: repo, now: DateTime.now);
      final a = _song(id: 'a', durationMs: 100000);
      final b = _song(id: 'b');

      await tracker.onSongChanged(a);
      await tracker.onPosition(
        const Duration(milliseconds: 99000),
        const Duration(milliseconds: 100000),
      );
      await tracker.onSongChanged(b);

      expect(
        repo.events.where((e) => e.type == 'skip'),
        isEmpty,
      );
      expect(
        repo.events.where((e) => e.type == 'complete'),
        hasLength(1),
      );
    });

    test('"replay" fires when same song restarts within 10s of complete',
        () async {
      final repo = _FakeListeningRepository();
      var clock = DateTime(2026, 1, 1);
      final tracker = _make(repo: repo, now: () => clock);

      final a = _song(id: 'a', durationMs: 100000);
      await tracker.onSongChanged(a);
      await tracker.onPosition(
        const Duration(milliseconds: 99000),
        const Duration(milliseconds: 100000),
      );
      // 5s later, replay
      clock = clock.add(const Duration(seconds: 5));
      await tracker.onSongChanged(a);

      final replays = repo.events.where((e) => e.type == 'replay').toList();
      expect(replays, hasLength(1));
      expect(replays.single.songId, 'a');
    });

    test('"replay" does NOT fire after the 10s window', () async {
      final repo = _FakeListeningRepository();
      var clock = DateTime(2026, 1, 1);
      final tracker = _make(repo: repo, now: () => clock);

      final a = _song(id: 'a', durationMs: 100000);
      await tracker.onSongChanged(a);
      await tracker.onPosition(
        const Duration(milliseconds: 99000),
        const Duration(milliseconds: 100000),
      );
      // 30s later → no longer a replay, just a normal play
      clock = clock.add(const Duration(seconds: 30));
      await tracker.onSongChanged(a);

      expect(
        repo.events.where((e) => e.type == 'replay'),
        isEmpty,
      );
      // Two plays (the original + the second start)
      expect(
        repo.events.where((e) => e.type == 'play'),
        hasLength(2),
      );
    });

    test('pause + resume only emit pause once per session', () async {
      final repo = _FakeListeningRepository();
      final tracker = _make(repo: repo, now: DateTime.now);
      final a = _song(id: 'a');
      await tracker.onSongChanged(a);
      await tracker.onPaused();
      await tracker.onPaused(); // second consecutive pause — ignored
      tracker.onResumed();
      await tracker.onPaused(); // new pause after resume — emits

      expect(
        repo.events.where((e) => e.type == 'pause').toList(),
        hasLength(2),
      );
    });

    test('favorite + add_to_playlist emit explicit events', () async {
      final repo = _FakeListeningRepository();
      final tracker = _make(repo: repo, now: DateTime.now);

      await tracker.onFavoriteToggled(songId: 's', nowFavorite: true);
      await tracker.onFavoriteToggled(songId: 's', nowFavorite: false);
      await tracker.onAddedToPlaylist('s');

      expect(
        repo.events.map((e) => e.type),
        ['favorite', 'unfavorite', 'add_to_playlist'],
      );
    });

    test('events carry the active context', () async {
      final repo = _FakeListeningRepository();
      final tracker = _make(repo: repo, now: DateTime.now, context: 'study');
      await tracker.onSongChanged(_song(id: 'a'));
      expect(repo.events.single.context, 'study');
    });
  });
}
