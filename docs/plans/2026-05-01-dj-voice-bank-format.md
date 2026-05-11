# DJ Voice Bank Format

The offline DJ voice bank is local-only. The app reads:

```text
<app_documents>/dj_voice_bank/manifest.json
```

Every audio path in the manifest is resolved relative to that `dj_voice_bank`
folder. No network, server, API, or live model inference is required.

## Manifest

```json
{
  "version": 1,
  "voiceId": "midnight_host",
  "clips": [
    {
      "id": "generic_chill_middle_001",
      "path": "generic/chill_middle_001.opus",
      "mode": "chill",
      "position": "middle",
      "intent": "keep_vibe"
    },
    {
      "id": "song_42_opener",
      "path": "songs/song_42/opener.opus",
      "songId": "song_42",
      "position": "opener",
      "intent": "intro_set",
      "priority": 10
    }
  ]
}
```

## Clip Fields

Required:

- `id`: unique stable clip id.
- `path`: `.opus`, `.mp3`, or another audio file playable by `just_audio`.

Optional filters:

- `songId`: only use this clip for one song.
- `mode`: one of `general`, `study`, `chill`, `workout`, `night`, `favorites`, `discover`, `smart_shuffle`.
- `position`: one of `opener`, `early`, `middle`, `late`, `closer`.
- `intent`: one of `intro_set`, `next_track`, `energy_up`, `energy_down`, `keep_vibe`, `study_focus`, `chill_transition`, `workout_boost`, `night_drive`, `discovery`, `throwback`, `favorite_return`, `artist_spotlight`, `mood_shift`, `recover_from_skip`, `set_closer`.
- `priority`: integer tie-breaker. Higher wins.

## Selection Rules

The app ignores clips that conflict with the current song, mode, intent, or queue position.

Among valid clips, it prefers:

1. Song-specific clips.
2. Exact intent clips.
3. Exact queue-position clips.
4. Exact mode clips.
5. Higher `priority`.

If no local clip matches, the app falls back to the existing generated commentary path.

## Recommended Pack Shape

For a 2,000 song library:

- 500-1,000 generic DJ clips.
- 4-5 song-position clips per song:
  - `opener`
  - `early`
  - `middle`
  - `late`
  - `closer`
- Extra favorite/top-artist clips only for important songs.

Storage estimate:

- Opus 32 kbps: roughly 60-90 MB for 10,000 short clips.
- MP3 64 kbps: roughly 120-180 MB for 10,000 short clips.

Use short lines. The strongest DJ effect comes from not saying title and artist every transition.
