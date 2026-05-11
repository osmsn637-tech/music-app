# Offline DJ Voice Bank — Status

**Status (2026-05-01):** Tasks 1–4 are merged. Live TTS has been deleted
from the app and server entirely (Kokoro container, Piper engine,
flutter_tts, pronunciation map, training screen, speech cache). The bank
is now the only path the DJ can speak through.

## Where things stand

- **Selection model** ([app/lib/features/ai_dj/dj_voice_bank.dart](../../app/lib/features/ai_dj/dj_voice_bank.dart))
  loads the manifest, scores clips by match quality, and returns the
  best one for a `DjSpeechContext`.
- **Loader + player** ([app/lib/features/ai_dj/dj_voice_bank_player.dart](../../app/lib/features/ai_dj/dj_voice_bank_player.dart))
  reads `<app_documents>/dj_voice_bank/manifest.json`, resolves clip
  paths, and plays clips through a dedicated `AudioPlayer`. Emits
  `isSpeakingStream` for the music ducker.
- **Queue controller integration** ([app/lib/features/ai_dj/ai_dj_queue_controller.dart](../../app/lib/features/ai_dj/ai_dj_queue_controller.dart))
  selects a clip after the intent selector runs and plays it before the
  song starts. No clip → silent transition. No fallback to TTS.
- **Format reference** ([./2026-05-01-dj-voice-bank-format.md](./2026-05-01-dj-voice-bank-format.md))
  documents the manifest shape, selection rules, and storage estimates.
- **Master script** ([../dj-voice-bank-script.md](../dj-voice-bank-script.md))
  contains every line the bank can speak (~150 lines): generic mode ×
  intent × position, per-artist sets for the 8 most-played artists, and
  per-song sets for 11 signature tracks.
- **Manifest seed** ([../../app/assets/dj_voice_bank/manifest.seed.json](../../app/assets/dj_voice_bank/manifest.seed.json))
  is the manifest template with every script line wired up. Drop the
  recorded `.opus` files into the matching folder structure under
  `<app_documents>/dj_voice_bank/` and the bank works.

## What's still open

See [../dj-voice-bank-gaps.md](../dj-voice-bank-gaps.md) — covers the
selector enhancements (artist matching), the audio-rendering pipeline
choice, the song-id wiring step, and the per-song bank coverage gap.
