#!/usr/bin/env python3
"""
Import metadata from a CSV into per-song sidecar JSONs.

Usage:
    python scripts/import_csv.py library.csv

For each row, writes server/content/songs/<stem>.json containing only the
non-empty columns. Empty columns are omitted so generate_manifest.py's
defaults still kick in. If every metadata column for a row is empty, the
sidecar is removed (round-trips stay lossless).

After import, rebuild the manifest:
    python scripts/generate_manifest.py --base-url http://<your-lan-ip>:8000
"""
from __future__ import annotations

import argparse
import csv
import json
import sys
from pathlib import Path

CONTENT_DIR = Path(__file__).resolve().parent.parent / "content"
SONGS_DIR = CONTENT_DIR / "songs"

NUMERIC_COLUMNS = {"bpm", "durationMs"}
KNOWN_COLUMNS = {"title", "artist", "album", "genre", "mood", "bpm", "durationMs", "id"}


def coerce(col: str, raw: str):
    raw = raw.strip()
    if not raw:
        return None
    if col in NUMERIC_COLUMNS:
        try:
            return int(raw)
        except ValueError:
            print(
                f"warn: column {col!r} expects an integer, got {raw!r} - skipping cell",
                file=sys.stderr,
            )
            return None
    return raw


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("csv_path", help="CSV produced by export_csv.py")
    args = parser.parse_args()

    csv_path = Path(args.csv_path)
    if not csv_path.is_file():
        print(f"error: {csv_path} does not exist", file=sys.stderr)
        return 1

    written = 0
    cleared = 0
    skipped = 0

    with csv_path.open("r", encoding="utf-8-sig", newline="") as f:
        reader = csv.DictReader(f)
        for row in reader:
            filename = (row.get("filename") or "").strip()
            if not filename:
                continue
            mp3 = SONGS_DIR / filename
            if not mp3.exists():
                print(f"warn: skipping {filename} (no matching mp3)", file=sys.stderr)
                skipped += 1
                continue
            sidecar = SONGS_DIR / f"{mp3.stem}.json"
            payload: dict = {}
            for col, raw in row.items():
                if col is None or col == "filename" or col not in KNOWN_COLUMNS:
                    continue
                value = coerce(col, raw or "")
                if value is not None:
                    payload[col] = value
            if payload:
                sidecar.write_text(
                    json.dumps(payload, indent=2, ensure_ascii=False) + "\n",
                    encoding="utf-8",
                )
                written += 1
            elif sidecar.exists():
                sidecar.unlink()
                cleared += 1

    print(f"Wrote {written} sidecar(s), cleared {cleared}, skipped {skipped}.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
