#!/usr/bin/env python3
"""
Bulk-import audio files into the music server's content folder.

Reads each MP3 in --source, extracts ID3 tags + embedded artwork via mutagen,
copies the audio into /content/songs/<id>.mp3, writes a sidecar metadata
JSON, saves embedded artwork to /content/artwork/<id>.<ext>, copies any
matching .lrc lyrics file, then regenerates manifest.json.

Idempotent — songs already in /content/songs are skipped unless --overwrite.

Usage (typical, via docker-compose):
    docker compose --profile tools run --rm importer

Or directly:
    python import.py --source /in --content /out --base-url http://192.168.1.20:8000
"""
from __future__ import annotations

import argparse
import json
import re
import shutil
import sys
from pathlib import Path

try:
    from mutagen import File as MutagenFile
    from mutagen.id3 import ID3, APIC
    from mutagen.mp3 import MP3
except ImportError:
    print("error: mutagen not installed. Run inside the importer Docker image.",
          file=sys.stderr)
    sys.exit(2)


SUPPORTED_AUDIO_EXTS = {".mp3", ".m4a", ".flac", ".ogg", ".opus", ".wav"}
SUPPORTED_ART_EXTS = (".jpg", ".jpeg", ".png", ".webp")


def stable_id(stem: str) -> str:
    safe = re.sub(r"[^a-zA-Z0-9_-]+", "_", stem).strip("_").lower()
    safe = re.sub(r"_+", "_", safe)
    return f"imp_{safe or 'song'}"


def read_metadata(path: Path) -> dict:
    """Returns title/artist/album/genre/durationMs/bpm + artwork bytes if any."""
    out: dict = {}
    artwork: tuple[bytes, str] | None = None

    audio = MutagenFile(str(path))
    if audio is None:
        return out

    duration = getattr(getattr(audio, "info", None), "length", None)
    if duration:
        out["durationMs"] = int(duration * 1000)

    def _clean(s):
        """Strip leading UTF-8 BOM + surrounding whitespace. Some downloaders
        prepend a BOM byte to every ID3 text frame, which would otherwise
        render as an invisible glitch character in the app."""
        if s is None:
            return None
        s = str(s).lstrip("﻿").strip()
        return s or None

    # Best-effort tag extraction across formats
    def first(tags, *keys):
        for k in keys:
            v = tags.get(k)
            if v:
                if hasattr(v, "text"):
                    return _clean(v.text[0]) if v.text else None
                if isinstance(v, list):
                    return _clean(v[0])
                return _clean(v)
        return None

    if isinstance(audio, MP3):
        try:
            id3 = ID3(str(path))
        except Exception:
            id3 = None
        if id3 is not None:
            out["title"] = first(id3, "TIT2")
            out["artist"] = first(id3, "TPE1", "TPE2")
            out["album"] = first(id3, "TALB")
            out["genre"] = first(id3, "TCON")
            try:
                bpm = first(id3, "TBPM")
                if bpm:
                    out["bpm"] = int(float(bpm))
            except (TypeError, ValueError):
                pass
            for k in id3.keys():
                if k.startswith("APIC"):
                    apic: APIC = id3[k]
                    artwork = (apic.data, apic.mime or "image/jpeg")
                    break
    else:
        # m4a/flac/ogg: mutagen exposes a tags dict
        tags = getattr(audio, "tags", None) or {}
        out["title"] = first(tags, "title", "TITLE", "\xa9nam")
        out["artist"] = first(tags, "artist", "ARTIST", "\xa9ART")
        out["album"] = first(tags, "album", "ALBUM", "\xa9alb")
        out["genre"] = first(tags, "genre", "GENRE", "\xa9gen")
        # Pictures (FLAC) / cover (m4a)
        pics = getattr(audio, "pictures", None)
        if pics:
            artwork = (pics[0].data, pics[0].mime or "image/jpeg")
        else:
            covr = tags.get("covr") if isinstance(tags, dict) else None
            if covr:
                first_cover = covr[0] if isinstance(covr, list) else covr
                artwork = (
                    bytes(first_cover),
                    "image/png" if getattr(first_cover, "imageformat", None) == 14
                        else "image/jpeg",
                )

    # Trim empty values
    out = {k: v for k, v in out.items() if v not in (None, "")}
    if artwork:
        out["_artwork"] = artwork
    return out


def ext_for_mime(mime: str) -> str:
    m = mime.lower()
    if "png" in m:
        return ".png"
    if "webp" in m:
        return ".webp"
    return ".jpg"


def find_sibling(
    source_dir: Path,
    stem: str,
    exts: tuple[str, ...],
    stem_suffixes: tuple[str, ...] = ("",),
) -> Path | None:
    """Looks for `<stem><stem_suffix><ext>`. The default empty stem_suffix
    matches exact-stem sidecars; pass extra suffixes (e.g. `_private`) to
    handle YouTube-downloader-style filenames where the lyrics file is
    named `Foo(MP3_320K)_private.lrc` next to `Foo(MP3_320K).mp3`."""
    for suffix in stem_suffixes:
        for ext in exts:
            p = source_dir / f"{stem}{suffix}{ext}"
            if p.exists():
                return p
    return None


def import_one(
    audio_path: Path,
    content: Path,
    overwrite: bool,
    verbose: bool,
) -> tuple[str, str]:
    """Returns (status, song_id). status ∈ {imported, skipped, failed}."""
    stem = audio_path.stem
    sid = stable_id(stem)
    ext = audio_path.suffix.lower()

    songs_dir = content / "songs"
    artwork_dir = content / "artwork"
    lyrics_dir = content / "lyrics"
    for d in (songs_dir, artwork_dir, lyrics_dir):
        d.mkdir(parents=True, exist_ok=True)

    target_audio = songs_dir / f"{sid}{ext}"
    if target_audio.exists() and not overwrite:
        if verbose:
            print(f"  skip   {audio_path.name} (already imported as {sid})")
        return "skipped", sid

    try:
        meta = read_metadata(audio_path)
    except Exception as e:
        if verbose:
            print(f"  warn   metadata read failed for {audio_path.name}: {e}")
        meta = {}

    artwork = meta.pop("_artwork", None)
    shutil.copy2(audio_path, target_audio)

    # Save artwork — prefer same-stem sidecar, fall back to embedded
    side_art = find_sibling(audio_path.parent, stem, SUPPORTED_ART_EXTS)
    if side_art:
        shutil.copy2(side_art, artwork_dir / f"{sid}{side_art.suffix.lower()}")
    elif artwork:
        bytes_, mime = artwork
        (artwork_dir / f"{sid}{ext_for_mime(mime)}").write_bytes(bytes_)

    # Copy same-stem lyrics. Tries both `<stem>.lrc` and `<stem>_private.lrc`
    # — the latter is what most YouTube-to-MP3 downloaders emit.
    side_lrc = find_sibling(
        audio_path.parent, stem, (".lrc",),
        stem_suffixes=("", "_private"),
    )
    if side_lrc:
        shutil.copy2(side_lrc, lyrics_dir / f"{sid}.lrc")

    # Sidecar JSON for the manifest generator
    sidecar = {"id": sid, "fileName": target_audio.name}
    for k in ("title", "artist", "album", "genre", "bpm", "durationMs"):
        if k in meta:
            sidecar[k] = meta[k]
    if "title" not in sidecar:
        # Fallback: "Artist - Title" → Title; otherwise use the stem.
        m = re.match(r"^(?P<artist>.+?)\s+-\s+(?P<title>.+)$", stem)
        if m:
            sidecar.setdefault("artist", m.group("artist"))
            sidecar["title"] = m.group("title")
        else:
            sidecar["title"] = stem.replace("_", " ")
    (songs_dir / f"{sid}.json").write_text(
        json.dumps(sidecar, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )

    if verbose:
        title = sidecar.get("title", "?")
        artist = sidecar.get("artist", "?")
        print(f"  ok     {audio_path.name} → {sid}  ({artist} — {title})")
    return "imported", sid


def regenerate_manifest(content: Path, base_url: str | None) -> None:
    """Mirror of generate_manifest.py logic; runs at the end."""
    songs_dir = content / "songs"
    lyrics_dir = content / "lyrics"
    artwork_dir = content / "artwork"
    manifest_path = content / "manifest.json"

    base = (base_url or "__BASE_URL__").rstrip("/")

    songs = []
    for mp3 in sorted(songs_dir.iterdir()):
        if mp3.suffix.lower() not in SUPPORTED_AUDIO_EXTS:
            continue
        stem = mp3.stem
        sidecar = songs_dir / f"{stem}.json"
        overrides = {}
        if sidecar.exists():
            try:
                overrides = json.loads(sidecar.read_text(encoding="utf-8"))
            except json.JSONDecodeError as e:
                print(f"warn: bad sidecar {sidecar.name}: {e}", file=sys.stderr)

        entry = {
            "id": overrides.get("id") or stable_id(stem),
            "title": overrides.get("title") or stem.replace("_", " "),
            "artist": overrides.get("artist"),
            "album": overrides.get("album"),
            "genre": overrides.get("genre"),
            "mood": overrides.get("mood"),
            "bpm": overrides.get("bpm"),
            "durationMs": overrides.get("durationMs"),
            "fileName": mp3.name,
            "audioUrl": f"{base}/songs/{mp3.name}",
        }
        # Drop nulls (manifest is cleaner that way)
        entry = {k: v for k, v in entry.items() if v is not None}

        lrc = lyrics_dir / f"{stem}.lrc"
        if lrc.exists():
            entry["lyricsUrl"] = f"{base}/lyrics/{lrc.name}"

        for art_ext in SUPPORTED_ART_EXTS:
            art = artwork_dir / f"{stem}{art_ext}"
            if art.exists():
                entry["artworkUrl"] = f"{base}/artwork/{art.name}"
                break

        songs.append(entry)

    manifest = {"version": 1, "songs": songs}
    manifest_path.write_text(
        json.dumps(manifest, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )
    print(f"manifest: wrote {manifest_path} with {len(songs)} song(s).")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", default="/in",
                        help="Folder to scan for audio files (default: /in).")
    parser.add_argument("--content", default="/out",
                        help="Server content folder (default: /out).")
    parser.add_argument("--base-url", default=None,
                        help="Base URL for the manifest. Omit to keep "
                             "__BASE_URL__ placeholders (use set_base_url.sh).")
    parser.add_argument("--overwrite", action="store_true",
                        help="Re-import files that are already present.")
    parser.add_argument("--quiet", action="store_true")
    args = parser.parse_args()

    src = Path(args.source)
    content = Path(args.content)

    if not src.is_dir():
        print(f"error: source folder {src} not found.", file=sys.stderr)
        return 1
    if not content.is_dir():
        print(f"error: content folder {content} not found.", file=sys.stderr)
        return 1

    audio_files = sorted(
        p for p in src.rglob("*")
        if p.is_file() and p.suffix.lower() in SUPPORTED_AUDIO_EXTS
    )
    if not audio_files:
        print(f"No audio files in {src}. Drop MP3/M4A/FLAC/OGG files there "
              f"and re-run.", file=sys.stderr)
        regenerate_manifest(content, args.base_url)
        return 0

    print(f"Scanning {len(audio_files)} file(s) under {src}…")
    counts = {"imported": 0, "skipped": 0, "failed": 0}
    for audio in audio_files:
        try:
            status, _sid = import_one(
                audio, content, args.overwrite, verbose=not args.quiet)
            counts[status] = counts.get(status, 0) + 1
        except Exception as e:
            counts["failed"] += 1
            print(f"  fail   {audio.name}: {e}", file=sys.stderr)

    print(
        f"\nimported {counts['imported']}, "
        f"skipped {counts['skipped']}, "
        f"failed {counts['failed']}."
    )
    regenerate_manifest(content, args.base_url)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
