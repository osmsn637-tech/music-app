import 'package:flutter_test/flutter_test.dart';
import 'package:music_app/features/automix/runtime/analysis_store.dart';

void main() {
  // These expected values are produced by tools/automix/analyze.py's
  // slugify() — the two MUST agree byte-for-byte or sidecars won't join to
  // songs. If you change one, change the other and update this table.
  group('AnalysisStore.slugify matches the Python analyzer', () {
    const cases = {
      'Jhené Aiko - Sativa (Official Audio)(MP3_320K).mp3':
          'jhen_aiko_sativa_official_audio',
      '21 Savage - A Lot (Official Audio)(MP3_320K).mp3':
          '21_savage_a_lot_official_audio',
      'Café del Mar.mp3': 'caf_del_mar',
      'Hold That Heat(MP3_320K).mp3': 'hold_that_heat',
      'I Heard You_re Married(MP3_320K).mp3': 'i_heard_you_re_married',
    };
    cases.forEach((input, expected) {
      test('"$input" -> $expected', () {
        expect(AnalysisStore.slugify(input), expected);
      });
    });
  });
}
