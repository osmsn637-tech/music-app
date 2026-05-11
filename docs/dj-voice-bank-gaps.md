# DJ Voice Bank — What's Missing

After dropping live TTS and writing the master script + manifest seed,
here's everything that still needs to happen for the bank to actually
talk in the app. Ranked by how much it blocks day-one use.

## 1. Audio recording / rendering — **blocking**

The script has ~150 lines. None have audio yet. Pick one of:

- **Record yourself.** Phone mic + a quiet room is enough; pop filter
  helps. One take per line, save as WAV, batch-encode to Opus 32 kbps
  mono with `ffmpeg -i in.wav -c:a libopus -b:a 32k -ac 1 out.opus`.
- **Voice clone, one-shot, offline.** ElevenLabs (Adam), Play.ht,
  Anthropic voice models, or OpenAI `tts-1-hd` (alloy / onyx). Render
  once at design time, drop the `.opus` files into the bank, and the
  app never touches the API at runtime. This is consistent with
  "drop TTS" — the app stays offline; the rendering happens before
  the audio ships into `<app docs>/dj_voice_bank/`.
- **Hire a VO.** Two-hour session covers the full script.

Either way, the file naming has to match `id` in the manifest exactly.
A small script that loops the manifest and prints `id → text` next to a
suggested filename is worth writing once before recording.

## 2. Selector cannot match by artist — **blocking for artist banks**

`DjVoiceClip` only filters on `songId`, `intent`, `position`, and
`mode`. The script has 38 artist-level lines that need an `artistId`
filter that doesn't exist yet. Until it lands, those clips will only
fire as generic clips (no filter) — meaning they'll play for the wrong
artists.

Fix:

- Add `artistId` to `DjVoiceClip`, `DjVoiceBankRequest`, and the
  manifest schema in [app/lib/features/ai_dj/dj_voice_bank.dart](../app/lib/features/ai_dj/dj_voice_bank.dart).
- Resolve the active song's artist to a slug (`Drake` → `drake`,
  `A$AP Rocky` → `asap-rocky`) in `selectForContext` — same slugging
  as `splitMultiArtist` in the queue controller.
- Score: artist match adds ~500 (between song = 1000 and generic = 0).
- Update [docs/plans/2026-05-01-dj-voice-bank-format.md](plans/2026-05-01-dj-voice-bank-format.md)
  to document `artistId` and the new selection priority.
- Once shipped, change the seed manifest's placeholder `_artistId` keys
  to the real `artistId` field.

## 3. Per-song clips need real `songId` values — **blocking for song banks**

The seed manifest uses `"songId": "REPLACE_WITH_LIBRARY_SONG_ID"` for
every per-song clip. Song ids in this app are content-addressed (sha
of the file), so there's no way to know them until the user has the
library synced.

Fix: a one-time helper that scans the songs table by title/artist and
substitutes the right id. Could be a 30-line Dart script under
`tools/`, or a Settings → AI DJ → "Wire bank to library" button that
runs the substitution and rewrites `manifest.json` once.

## 4. Per-song coverage stops at 11 tracks — **partial blocker**

The library has ~200 songs. The script has bespoke per-song banks for
11. Everything else falls through to the artist + generic banks, which
is fine and intentional — but if the goal is "4–5 lines per song" for
every track, that's another 950 lines to write and record.

Two pragmatic paths:

- Decide that 4–5 per song was aspirational; the artist + generic banks
  cover the gap. (My recommendation — bespoke lines on a 200-song
  library go stale fast because each song only fires its own clips.)
- Generate them. Feed `(title, artist, queue position)` into a
  prompt-based template ("write a Morgan-Freeman-cadence one-liner
  introducing this track") and review/edit the output. Keep the same
  schema; only the `text` and `path` change per row.

Either way, document the call so it doesn't sit half-shipped.

## 5. The `dj_voice` toggle still says "Voice commentary" elsewhere

Settings copy is updated. But the seed manifest's voice id is
`deep_host`, while the queue controller doesn't surface that anywhere.
If you want to support more than one voice pack later, the manifest's
`voiceId` field is unused at runtime. Cheap to wire: pick the manifest
whose `voiceId` matches a setting; ignore others. Defer until there's a
second voice pack to switch between.

## 6. Dormant DB tables left behind

- `dj_speech_cache` — was the text cache for TTS. No reads/writes
  anymore. Harmless. Can be dropped in a future schema migration.
- `pronunciation_fixes` — same story. Harmless. Drop on migration.
- `recent_dj_lines` — still wired (hostBubble uses it for repeat
  suppression on the rotating idle line). Keep.

## 7. Tests

Removed: `dj_voice_engine_phase_d_test.dart`,
`fallback_voice_engine_test.dart`, `dj_speech_cache_phase_c_test.dart`,
`pronunciation_service_test.dart`. Still present:
`dj_voice_bank_test.dart`, `dj_voice_bank_player_test.dart`,
`dj_commentary_phase_b_test.dart` (covers `announce()` which is now
unused — either delete the file or trim to host bubble coverage),
plus the rest of the suite.

Add at some point:
- `artistId` selection tests once the field lands.
- A test that asserts every clip id in the seed manifest is unique and
  resolvable to a path.

## 8. APK size won

Removing `flutter_tts`, `crypto`, the Kokoro Docker image, and the
~340 MB `kokoro-models/` directory drops the project footprint by a
lot. The pubspec comment about "150 MB → 55 MB" was about the old
bundled-TTS removal — the bank pack itself is roughly 1–2 MB at Opus
32 kbps for 150 lines, so the runtime APK barely grows.
