import 'package:flutter_test/flutter_test.dart';
import 'package:music_app/data/database/app_database.dart';
import 'package:music_app/features/ai_dj/dj_mode.dart';
import 'package:music_app/features/ai_dj/dj_speech_types.dart';
import 'package:music_app/features/ai_dj/dj_voice_bank.dart';
import 'package:music_app/features/ai_dj/user_listening_profile.dart';

void main() {
  group('DjVoiceBankManifest', () {
    test('parses generic and song-specific clips from json', () {
      final bank = DjVoiceBankManifest.fromJson({
        'version': 1,
        'voiceId': 'midnight_host',
        'clips': [
          {
            'id': 'generic_opener_01',
            'path': 'generic/opener_01.opus',
            'intent': 'intro_set',
            'position': 'opener',
          },
          {
            'id': 'song_42_middle',
            'path': 'songs/song_42/middle.opus',
            'songId': 'song_42',
            'position': 'middle',
            'mode': 'chill',
          },
        ],
      });

      expect(bank.voiceId, 'midnight_host');
      expect(bank.clips, hasLength(2));
      expect(bank.clips.first.intent, DjIntent.introSet);
      expect(bank.clips.first.position, QueuePositionType.opener);
      expect(bank.clips.last.songId, 'song_42');
      expect(bank.clips.last.mode, DjMode.chill);
    });
  });

  group('DjVoiceBankSelector', () {
    test('prefers song-specific clip over generic clip', () {
      final selector = DjVoiceBankSelector(
        DjVoiceBankManifest(
          voiceId: 'midnight_host',
          clips: const [
            DjVoiceClip(
              id: 'generic_middle',
              path: 'generic/middle.opus',
              position: QueuePositionType.middle,
            ),
            DjVoiceClip(
              id: 'song_middle',
              path: 'songs/song_42/middle.opus',
              songId: 'song_42',
              position: QueuePositionType.middle,
            ),
          ],
        ),
      );

      final clip = selector.select(
        const DjVoiceBankRequest(
          songId: 'song_42',
          mode: DjMode.chill,
          intent: DjIntent.keepVibe,
          position: QueuePositionType.middle,
        ),
      );

      expect(clip?.id, 'song_middle');
    });

    test('prefers exact queue position over position-agnostic clip', () {
      final selector = DjVoiceBankSelector(
        DjVoiceBankManifest(
          voiceId: 'midnight_host',
          clips: const [
            DjVoiceClip(
              id: 'song_anywhere',
              path: 'songs/song_42/anywhere.opus',
              songId: 'song_42',
            ),
            DjVoiceClip(
              id: 'song_closer',
              path: 'songs/song_42/closer.opus',
              songId: 'song_42',
              position: QueuePositionType.closer,
            ),
          ],
        ),
      );

      final clip = selector.select(
        const DjVoiceBankRequest(
          songId: 'song_42',
          mode: DjMode.chill,
          intent: DjIntent.setCloser,
          position: QueuePositionType.closer,
        ),
      );

      expect(clip?.id, 'song_closer');
    });

    test('returns null when every candidate conflicts with request', () {
      final selector = DjVoiceBankSelector(
        DjVoiceBankManifest(
          voiceId: 'midnight_host',
          clips: const [
            DjVoiceClip(
              id: 'wrong_song',
              path: 'songs/song_99/opener.opus',
              songId: 'song_99',
              position: QueuePositionType.opener,
            ),
            DjVoiceClip(
              id: 'wrong_intent',
              path: 'generic/closer.opus',
              intent: DjIntent.setCloser,
            ),
          ],
        ),
      );

      final clip = selector.select(
        const DjVoiceBankRequest(
          songId: 'song_42',
          mode: DjMode.chill,
          intent: DjIntent.keepVibe,
          position: QueuePositionType.middle,
        ),
      );

      expect(clip, isNull);
    });

    test('can select directly from a DJ speech context', () {
      final selector = DjVoiceBankSelector(
        DjVoiceBankManifest(
          voiceId: 'midnight_host',
          clips: const [
            DjVoiceClip(
              id: 'song_opener',
              path: 'songs/song_42/opener.opus',
              songId: 'song_42',
              intent: DjIntent.introSet,
              position: QueuePositionType.opener,
              mode: DjMode.chill,
            ),
          ],
        ),
      );

      final clip = selector.selectForContext(
        DjSpeechContext(
          song: const SongRow(
            id: 'song_42',
            title: 'Time Flies',
            artist: 'Drake',
            localFilePath: 'song.mp3',
            isFavorite: 0,
          ),
          previousSong: null,
          nextSong: null,
          mode: DjMode.chill,
          queueIndex: 0,
          queueLength: 10,
          queuePosition: QueuePositionType.opener,
          profile: UserListeningProfile.empty(),
          now: DateTime(2026, 5, 1),
          intent: DjIntent.introSet,
        ),
      );

      expect(clip?.id, 'song_opener');
    });
  });
}
