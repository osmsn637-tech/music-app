#!/usr/bin/env python3
"""
Batch-analyze a song library into AutoMix sidecars.

Runs the fast librosa analysis (analyze.py) over every track, and — with
--with-stems — the heavy Demucs pass (stems.py) first, so vocal ratios come
from real stems instead of the proxy.

  # fast pass over the whole library (~15 s/track, CPU)
  python tools/automix/batch.py songs --out analysis

  # try a handful first
  python tools/automix/batch.py songs --out analysis --limit 5

  # full pipeline incl. stems (SLOW: minutes/track, ~50 MB/track)
  python tools/automix/batch.py songs --out analysis --with-stems --stems-out stems

Resumable: tracks whose sidecar already exists are skipped unless --force.
"""

from __future__ import annotations

import argparse
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from analyze import analyze_file, slugify  # noqa: E402

AUDIO_EXTS = {".mp3", ".m4a", ".flac", ".wav", ".aac", ".ogg", ".opus"}


def _fmt(secs: float) -> str:
    m, s = divmod(int(secs), 60)
    h, m = divmod(m, 60)
    return f"{h:d}:{m:02d}:{s:02d}" if h else f"{m:d}:{s:02d}"


def main():
    ap = argparse.ArgumentParser(description="AutoMix library batch analyzer")
    ap.add_argument("songs_dir", help="directory of audio files")
    ap.add_argument("--out", default="analysis", help="sidecar output dir")
    ap.add_argument("--limit", type=int, default=0, help="only N tracks (0=all)")
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--with-stems", action="store_true",
                    help="run Demucs first (SLOW) and use stem vocal ratios")
    ap.add_argument("--stems-out", default="stems")
    ap.add_argument("--model", default="htdemucs")
    args = ap.parse_args()

    out_dir = Path(args.out)
    out_dir.mkdir(parents=True, exist_ok=True)

    files = sorted(
        f for f in Path(args.songs_dir).iterdir()
        if f.is_file() and f.suffix.lower() in AUDIO_EXTS
    )
    if args.limit:
        files = files[: args.limit]
    total = len(files)
    print(f"found {total} audio files in {args.songs_dir}")

    separate = None
    if args.with_stems:
        from stems import separate as _sep, have_demucs
        if not have_demucs():
            print("demucs not installed; run without --with-stems or "
                  "`pip install demucs torch`.", file=sys.stderr)
            sys.exit(2)
        separate = _sep

    done = skipped = failed = 0
    start = time.time()
    for i, f in enumerate(files, 1):
        slug = slugify(f.stem)
        sidecar = out_dir / f"{slug}.automix.json"
        if sidecar.exists() and not args.force:
            skipped += 1
            continue

        stems_dir = None
        if separate is not None:
            d = separate(str(f), args.stems_out, model=args.model,
                         force=args.force)
            stems_dir = str(d) if d else None

        try:
            import json
            res = analyze_file(str(f), stems_dir=stems_dir)
            if stems_dir:
                res.stems.available = True
                res.stems.model = args.model
                res.stems.dir = stems_dir
            sidecar.write_text(json.dumps(res.to_json(), indent=2),
                               encoding="utf-8")
            done += 1
        except Exception as e:  # noqa: BLE001
            failed += 1
            print(f"  FAIL [{i}/{total}] {f.name}: {e}", file=sys.stderr)
            continue

        # progress + ETA off the tracks we actually processed
        processed = done + failed
        if processed:
            rate = (time.time() - start) / processed
            eta = rate * (total - i)
            print(f"  [{i}/{total}] {f.name[:48]:48s}  "
                  f"{res.bpm:5.1f}bpm {res.key.camelot:>3}  "
                  f"ETA {_fmt(eta)}")

    print(f"\ndone={done} skipped={skipped} failed={failed}  "
          f"elapsed {_fmt(time.time() - start)}")
    print(f"sidecars in: {out_dir.resolve()}")


if __name__ == "__main__":
    main()
