#!/usr/bin/env python3
"""
Scan server/content/songs/*.mp3 and rebuild server/content/manifest.json.

Usage:
    python scripts/generate_manifest.py --base-url http://192.168.1.20:8000

Each MP3 in content/songs/ becomes one entry. If a matching .lrc or .jpg
exists in content/lyrics or content/artwork (same stem), it is linked.

Optional sidecar metadata: content/songs/<stem>.json overrides defaults
(title, artist, album, genre, mood, bpm, durationMs).
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

CONTENT_DIR = Path(__file__).resolve().parent.parent / "content"
SONGS_DIR = CONTENT_DIR / "songs"
LYRICS_DIR = CONTENT_DIR / "lyrics"
ARTWORK_DIR = CONTENT_DIR / "artwork"
MANIFEST_PATH = CONTENT_DIR / "manifest.json"


def stable_id(stem: str) -> str:
    safe = re.sub(r"[^a-zA-Z0-9_-]+", "_", stem).strip("_").lower()
    return safe or "song"


def find_artwork(stem: str) -> Path | None:
    for ext in ("jpg", "jpeg", "png", "webp"):
        p = ARTWORK_DIR / f"{stem}.{ext}"
        if p.exists():
            return p
    return None


def build_entry(mp3: Path, base_url: str) -> dict:
    stem = mp3.stem
    sidecar = SONGS_DIR / f"{stem}.json"
    overrides: dict = {}
    if sidecar.exists():
        try:
            overrides = json.loads(sidecar.read_text(encoding="utf-8"))
        except json.JSONDecodeError as e:
            print(f"warn: bad sidecar {sidecar.name}: {e}", file=sys.stderr)

    entry: dict = {
        "id": overrides.get("id") or stable_id(stem),
        "title": overrides.get("title") or stem.replace("_", " ").title(),
        "artist": overrides.get("artist") or "Unknown Artist",
        "album": overrides.get("album"),
        "genre": overrides.get("genre"),
        "mood": overrides.get("mood"),
        "bpm": overrides.get("bpm"),
        "durationMs": overrides.get("durationMs"),
        "fileName": mp3.name,
        "audioUrl": f"{base_url}/songs/{mp3.name}",
    }

    lrc = LYRICS_DIR / f"{stem}.lrc"
    if lrc.exists():
        entry["lyricsUrl"] = f"{base_url}/lyrics/{lrc.name}"

    art = find_artwork(stem)
    if art is not None:
        entry["artworkUrl"] = f"{base_url}/artwork/{art.name}"

    return entry


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--base-url",
        default="http://localhost:8000",
        help="Base URL the Flutter app will reach the server at "
             "(use your LAN IP, e.g. http://192.168.1.20:8000).",
    )
    args = parser.parse_args()

    if not SONGS_DIR.is_dir():
        print(f"error: {SONGS_DIR} does not exist", file=sys.stderr)
        return 1

    base = args.base_url.rstrip("/")
    mp3s = sorted(SONGS_DIR.glob("*.mp3"))
    songs = [build_entry(m, base) for m in mp3s]

    manifest = {"version": 1, "songs": songs}
    MANIFEST_PATH.write_text(
        json.dumps(manifest, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )
    print(f"Wrote {MANIFEST_PATH} with {len(songs)} song(s).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
