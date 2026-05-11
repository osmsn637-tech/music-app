import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_app/features/ai_dj/dj_voice_bank_player.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('dj_voice_bank_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('DjVoiceBankStore', () {
    test('returns an empty bank when no manifest exists', () async {
      final bank = await DjVoiceBankStore.loadFromDirectory(tempDir);

      expect(bank.isEmpty, isTrue);
      expect(bank.manifest.clips, isEmpty);
    });

    test(
      'resolves relative clip paths against the manifest directory',
      () async {
        await File(p.join(tempDir.path, 'manifest.json')).writeAsString('''
{
  "version": 1,
  "voiceId": "midnight_host",
  "clips": [
    {
      "id": "opener",
      "path": "generic/opener.opus",
      "position": "opener"
    }
  ]
}
''');

        final bank = await DjVoiceBankStore.loadFromDirectory(tempDir);
        final clip = bank.manifest.clips.single;

        expect(
          bank.resolvePath(clip),
          p.normalize(p.join(tempDir.path, 'generic', 'opener.opus')),
        );
      },
    );

    test('returns an empty bank for invalid manifest json', () async {
      await File(
        p.join(tempDir.path, 'manifest.json'),
      ).writeAsString('{ definitely not json');

      final bank = await DjVoiceBankStore.loadFromDirectory(tempDir);

      expect(bank.isEmpty, isTrue);
      expect(bank.manifest.clips, isEmpty);
    });
  });
}
