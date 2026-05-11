#!/usr/bin/env python3
"""
Export server/content/songs/*.mp3 to a CSV for bulk metadata editing.

Usage:
    python scripts/export_csv.py [--output library.csv]

Each MP3 becomes one row. Existing sidecar JSONs are read and pre-fill the
row, so you can round-trip: export -> edit -> import -> re-export without
losing prior work.

Edit the CSV in Excel / Numbers / Sheets, then run:
    python scripts/import_csv.py library.csv
to write each row back as a per-song sidecar JSON.
"""
from __future__ import annotations

import argparse
import csv
import json
import sys
from pathlib import Path

CONTENT_DIR = Path(__file__).resolve().parent.parent / "content"
SONGS_DIR = CONTENT_DIR / "songs"

COLUMNS = [
    "filename",
    "title",
    "artist",
    "album",
    "genre",
    "mood",
    "bpm",
    "durationMs",
    "id",
]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--output",
        default=str(CONTENT_DIR.parent / "library.csv"),
        help="Where to write the CSV (default: server/library.csv).",
    )
    args = parser.parse_args()

    if not SONGS_DIR.is_dir():
        print(f"error: {SONGS_DIR} does not exist", file=sys.stderr)
        return 1

    rows: list[dict] = []
    for mp3 in sorted(SONGS_DIR.glob("*.mp3")):
        stem = mp3.stem
        sidecar = SONGS_DIR / f"{stem}.json"
        existing: dict = {}
        if sidecar.exists():
            try:
                existing = json.loads(sidecar.read_text(encoding="utf-8"))
            except json.JSONDecodeError as e:
                print(f"warn: bad sidecar {sidecar.name}: {e}", file=sys.stderr)
        row = {"filename": mp3.name}
        for col in COLUMNS[1:]:
            value = existing.get(col)
            row[col] = "" if value is None else value
        rows.append(row)

    out_path = Path(args.output)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    with out_path.open("w", encoding="utf-8-sig", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=COLUMNS)
        writer.writeheader()
        writer.writerows(rows)
    print(f"Wrote {out_path} with {len(rows)} song(s).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
