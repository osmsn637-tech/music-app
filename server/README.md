# Local Wi-Fi Music Server

A tiny nginx-in-Docker static file server that exposes your music library on
your LAN so the Flutter app can sync songs to the phone over Wi-Fi.

## Layout

```
server/
├── docker-compose.yml
├── nginx.conf
├── scripts/
│   ├── generate_manifest.py    # rebuild manifest from scratch (needs Python)
│   ├── export_csv.py           # dump library to CSV for bulk metadata editing
│   ├── import_csv.py           # write CSV rows back as per-song sidecar JSONs
│   ├── piper_tts_server.py     # Piper TTS HTTP server for AI DJ voice (optional)
│   └── set_base_url.sh         # swap the LAN IP into an existing manifest
├── importer/                   # bulk-import audio files via Docker (no host Python needed)
│   ├── Dockerfile
│   └── import.py
├── import/                     # default drop-in folder watched by the importer
└── content/
    ├── manifest.json        # describes the library; ships with __BASE_URL__ placeholder
    ├── songs/   *.mp3       # drop your MP3s here (two CC0 samples ship by default)
    ├── lyrics/  *.lrc       # optional, same stem as the mp3
    └── artwork/ *.jpg|png   # optional, same stem as the mp3
```

## Run

```bash
docker compose up -d
```

The server listens on port 8000. From the phone's browser (on the same
Wi-Fi), confirm `http://<your-pc-lan-ip>:8000/manifest.json` returns JSON.

Find your LAN IP:
- Windows: `ipconfig` → look for "IPv4 Address" under your Wi-Fi adapter.
- macOS:   `ipconfig getifaddr en0`
- Linux:   `hostname -I`

## Adding songs

1. Drop `*.mp3` into `content/songs/`.
2. Optionally drop matching `*.lrc` into `content/lyrics/` and
   `*.jpg`/`*.png` into `content/artwork/` (same filename stem).
3. Optionally add a `content/songs/<stem>.json` sidecar to override
   metadata, e.g.:

   ```json
   {
     "title": "Late Night Drive",
     "artist": "Foo",
     "album": "Bar",
     "genre": "Lofi",
     "mood": "chill",
     "bpm": 84,
     "durationMs": 215000
   }
   ```
4. Regenerate the manifest. Two options:

   **With Python** (rebuilds the manifest from whatever's in `content/songs/`):

   ```bash
   python scripts/generate_manifest.py --base-url http://<your-lan-ip>:8000
   ```

   **Without Python** (rewrites only the base URL in the existing manifest —
   useful if you just want to point the included samples at your LAN IP):

   ```bash
   bash scripts/set_base_url.sh http://<your-lan-ip>:8000
   ```

   No restart of the container is needed — nginx reads files live and the
   manifest is served `Cache-Control: no-store`.

## Bulk import — point at a folder, get songs on the server

You don't need Python on your computer for this — it runs inside a Docker
container that's built on first use. The importer reads ID3 tags + embedded
artwork, writes per-song sidecar JSONs, and rebuilds `manifest.json`.

**Quick path** — drop files into `server/import/` and run:

```bash
docker compose --profile tools run --rm importer
```

**Custom path** — point at any folder (recursively scanned):

```bash
IMPORT_DIR=/path/to/your/music \
docker compose --profile tools run --rm importer
```

What it does for each audio file (mp3 / m4a / flac / ogg / opus / wav):

1. Generates a stable id from the filename.
2. Copies the audio into `content/songs/<id>.<ext>`.
3. Reads ID3 tags via `mutagen` → writes `content/songs/<id>.json`
   sidecar with `title` / `artist` / `album` / `genre` / `bpm` / `durationMs`.
4. Saves embedded artwork to `content/artwork/<id>.jpg|png` (or copies a
   same-stem `.jpg`/`.png` file from the source folder if you provide one).
5. Copies a same-stem `.lrc` lyrics file if present.

The importer is **idempotent** — re-running skips songs already imported.
Pass `--overwrite` if you want to refresh metadata from updated tags:

```bash
docker compose --profile tools run --rm importer --overwrite
```

Bake the LAN IP into the manifest in the same step:

```bash
docker compose --profile tools run --rm importer \
  --base-url http://192.168.1.20:8000
```

(Or skip that flag and run `bash scripts/set_base_url.sh ...` afterwards.)

## Auto-repair — clean titles, fill missing artwork + lyrics

After a bulk import you'll usually have:
- Some titles still carrying download cruft (`(MP3_320K)`, `(Official Video)`,
  `[Lyrics]`, leading BOM byte from the YouTube downloader's tags).
- A handful of songs without embedded ID3 artwork.
- Most songs without time-synced `.lrc` lyrics.

The repair tool fixes all three in one pass. It runs in Docker so you
don't need anything installed on the host beyond what's already here.

```bash
# Run all three repair passes (default):
docker compose --profile tools run --rm repair

# Or restrict to one or two:
docker compose --profile tools run --rm repair --only=lyrics
docker compose --profile tools run --rm repair --only=titles --only=artwork

# Bake the LAN IP into the regenerated manifest in the same step:
docker compose --profile tools run --rm repair \
  --base-url http://192.168.1.20:8000

# Preview without writing:
docker compose --profile tools run --rm repair --dry-run
```

What each pass does:

1. **`titles`** — regex-cleans every `content/songs/<id>.json` sidecar.
   Pure local pass; no internet. Idempotent.
2. **`artwork`** — for any song that doesn't already have a file in
   `content/artwork/`, queries the **iTunes Search API** by artist + title
   and downloads the first hit's 600×600 cover. Free, no API key.
3. **`lyrics`** — for any song that doesn't already have an `.lrc`,
   queries **LRCLib** for time-synced lyrics. Plain (un-timed) lyrics
   are skipped — only synced LRC is written, so the in-app lyrics view
   highlights the active line. Free, no API key.

Idempotent: re-running only acts on songs that *currently* lack the asset.
Polite by default — sleeps 1 second between iTunes / LRCLib requests.
Manifest is regenerated at the end so the next phone Sync picks up the
new artwork + lyrics URLs.

## Bulk metadata for big libraries

Hand-writing a sidecar JSON per song doesn't scale past a few dozen tracks.
For larger libraries, use the CSV round-trip:

```bash
# 1. Dump every mp3 in content/songs/ to one CSV row each.
python scripts/export_csv.py                   # writes server/library.csv
#    (or: python scripts/export_csv.py --output ~/Desktop/library.csv)

# 2. Open library.csv in Excel / Numbers / Sheets. Fill in title, artist,
#    album, genre, mood, bpm. Use sort + find/replace to fix capitalization,
#    spread albums across rows, etc. Leave columns blank to fall back to
#    defaults from generate_manifest.py. Don't touch the `filename` column.

# 3. Write the CSV back as per-song sidecar JSONs.
python scripts/import_csv.py server/library.csv

# 4. Rebuild the manifest.
python scripts/generate_manifest.py --base-url http://<your-lan-ip>:8000
```

The round-trip is lossless: re-running `export_csv.py` after edits picks
up the values you wrote, so you can iterate. Rows whose metadata columns
are all blank get their sidecar removed (rather than written as `{}`),
keeping the songs/ folder clean.

Notes:
- `bpm` and `durationMs` must be integers; bad cells are warned about and
  skipped (the rest of the row still imports).
- The `id` column is the manifest's stable song ID. Leave it blank unless
  you're intentionally renaming an ID — changing it after the app has
  synced will look like a brand-new song to the device.
- Unknown columns in the CSV are ignored, so adding extra columns for
  your own bookkeeping is safe.

## AI DJ voice via Piper (optional)

The Flutter app can route DJ commentary through a local Piper TTS server
running on this machine instead of the phone's built-in TTS. Voice quality
is dramatically better — sounds like a competent narrator instead of a
navigation app — and the phone caches every line by content hash so each
unique DJ line is synthesized exactly once and replayed from disk forever
after.

### One-time setup (Docker — recommended, no Python needed)

1. **Download a voice.** Pick one from the
   [Piper voice catalog](https://github.com/rhasspy/piper/blob/master/VOICES.md).
   Solid options for a DJ-style narrator:
   - `en_US-ryan-high` — deep male, deliberate cadence
     (Freeman-ish baritone).
   - `en_US-hfc_male-medium` — warm, slightly lighter male.

   Each voice is **two files**: `<voice>.onnx` (the model) and
   `<voice>.onnx.json` (the inference config). Both are required.
   Drop both into `server/voices/`.

2. **Bring up the service:**

   ```bash
   cd server
   docker compose up -d
   ```

   This builds the `piper` image the first time (~2 minutes) and runs
   it alongside your existing music nginx. Both auto-start on reboot
   thanks to `restart: unless-stopped`.

3. **Verify** from any browser on the LAN:
   `http://<your-pc-lan-ip>:8001/health` should return
   `{"ok": true, "voice": "en_US-ryan-high"}`.

### Switching voices

Drop the new `.onnx` + `.onnx.json` into `server/voices/`, then either:

- Override the default voice file the container loads by editing
  `docker-compose.yml` and setting:

  ```yaml
  piper:
    # ...
    command:
      - "python"
      - "/app/piper_tts_server.py"
      - "--voice"
      - "/voices/en_US-hfc_male-medium.onnx"
      - "--bind"
      - "0.0.0.0"
      - "--port"
      - "8001"
  ```

- Then `docker compose up -d --force-recreate piper`.

The phone-side cache is content-addressed — switching voices won't waste
the lines you already cached under the previous voice.

### Wire it into the app

In Settings → AI DJ → "Piper server URL", enter `http://<lan-ip>:8001`.
Leave the field empty to fall back to the on-device flutter_tts engine.

When the URL is set:
- The DJ tries Piper first.
- The phone caches the synthesized audio at
  `<app_documents>/dj_voice/<sha1>.mp3` so repeat lines play offline.
- Any error (server down, timeout, bad response) falls back silently to
  flutter_tts. The DJ will keep talking either way.

### Setup without Docker (host Python)

If you'd rather skip Docker:

```bash
pip install piper-tts
python3 scripts/piper_tts_server.py \
    --voice voices/en_US-ryan-high.onnx \
    --port 8001
```

Note this won't auto-restart and you have to keep the terminal open.

### Notes

- The server is unauthenticated, same posture as the music nginx.
  **Do not expose port 8001 to the public internet.**
- The default bind is `0.0.0.0` so the phone can reach the container
  over LAN. The container layer adds firewall isolation but the host
  port is open to the local network.
- One synthesis ≈ 1–3 seconds on a modern PC CPU. The first time the DJ
  speaks a fresh line it'll pause briefly; cached replays are instant.
- If `docker compose up` fails with a Python wheel error, your CPU
  architecture isn't supported by piper-tts 1.2.0. Try pinning a newer
  version in `piper/Dockerfile` or fall back to the host-Python setup.

## Live Connect — play across your devices (real-time handoff)

`connect/` is a tiny FastAPI WebSocket service that keeps playback in sync
across your iPhone, Android, and the Mac app and lets you **transfer playback
between them mid-song** (Spotify-Connect style) plus remote-control whichever
device is currently playing. It's a long-running service like nginx/piper, so
it starts with `docker compose up -d`.

```bash
# pick a private shared code all your devices will use, then bring it up:
ROOM_CODE=your-secret-code docker compose up -d connect

# verify:
curl http://localhost:8002/health      # {"ok":true,"room":true,"devices":0,"active":null}
```

In the app on **every** device: Settings → Live Connect → enter
`ws://<your-lan-ip>:8002/ws` and the same `ROOM_CODE`. Devices sharing a room
code see each other and can hand off playback.

- **LAN** (all devices on the same Wi-Fi): `ws://<lan-ip>:8002/ws` — simplest.
- **Across networks** (phone on cellular, Mac at home): deploy `connect` on a
  small cloud box and put it behind a TLS reverse proxy, then use
  `wss://<host>/connect/ws`. Plain `ws://` over the internet is unencrypted —
  **do not** expose port 8002 publicly without TLS.

State (current song / queue / position) is snapshotted to
`connect/state/state.json` so a service restart doesn't lose the session.
Wire protocol is frozen as `protocol: 1` (see `connect/app.py`). Run the
built-in two-device self-test any time with:

```bash
docker compose run --rm --no-deps --entrypoint python \
  connect selftest.py ws://connect:8002/ws "$ROOM_CODE"
```

Security: same unauthenticated-LAN posture as the music + piper servers — the
room code is the only gate. Keep it private; rotate it by changing `ROOM_CODE`
and `docker compose up -d connect`.

## First-run smoke test

The repo ships with two CC0 sample MP3s in `content/songs/` and a
`manifest.json` that uses `__BASE_URL__` as a placeholder. To wire it up:

```bash
docker compose up -d
bash scripts/set_base_url.sh http://<your-lan-ip>:8000
curl http://<your-lan-ip>:8000/manifest.json    # should list 2 songs
```

Then in the app: Sync tab → enter `http://<your-lan-ip>:8000` → **Sync**.

## Stopping

```bash
docker compose down
```

## Notes

- This is intentionally read-only and unauthenticated. Do not expose port
  8000 to the public internet.
- Only host music you own or are licensed to use.
