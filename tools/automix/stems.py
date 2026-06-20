#!/usr/bin/env python3
"""
Demucs stem separation for the AutoMix engine.

Splits a track into vocals / drums / bass / other (htdemucs, 4-stem) — the
elements the smart-stem mixer (§6) fades independently. The 6-stem model
(htdemucs_6s) additionally separates guitar + piano if you want a distinct
"melody" stem; pass --model htdemucs_6s.

This is the HEAVY half of analysis: Demucs is a neural net — seconds on a
GPU, a few minutes per track on CPU, and each track's stems are ~40-60 MB
of WAV. It is intentionally separate from analyze.py so the fast librosa
pass can run on the whole library without waiting on Demucs.

Stems land in   <out>/<slug>/{vocals,drums,bass,other}.wav
and the path is recorded back into the track's sidecar (analyze.py picks
them up via --stems-root on a re-run, switching vocal detection from the
proxy to the exact stem ratio).

Run:
    python tools/automix/stems.py "songs/Track(MP3_320K).mp3" --out stems
    python tools/automix/stems.py --model htdemucs_6s "songs/Track.mp3"

Requires: pip install demucs torch  (torchaudio recommended).
"""

from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
from pathlib import Path

# import slugify from the sibling analyzer so stem dirs match sidecar keys
sys.path.insert(0, str(Path(__file__).resolve().parent))
from analyze import slugify  # noqa: E402

STEM_NAMES = ("vocals", "drums", "bass", "other")


def have_demucs() -> bool:
    try:
        import demucs  # noqa: F401
        return True
    except Exception:
        return False


def separate(path: str, out_root: str, model: str = "htdemucs",
             force: bool = False) -> Path | None:
    """Run Demucs on one file, flatten its output to <out_root>/<slug>/."""
    src = Path(path)
    slug = slugify(src.stem)
    dest = Path(out_root) / slug
    if dest.exists() and not force and any(
            (dest / f"{s}.wav").exists() for s in STEM_NAMES):
        print(f"  skip (done): {src.name}")
        return dest

    dest.mkdir(parents=True, exist_ok=True)
    # Demucs writes <demucs_out>/<model>/<trackstem>/<stem>.wav
    tmp = Path(out_root) / "_demucs_tmp"
    cmd = [
        sys.executable, "-m", "demucs",
        "-n", model,
        "--out", str(tmp),
        str(src),
    ]
    print(f"  separating: {src.name}  (model={model}) …")
    try:
        subprocess.run(cmd, check=True)
    except subprocess.CalledProcessError as e:
        print(f"  FAIL: {src.name}: demucs exited {e.returncode}",
              file=sys.stderr)
        return None

    produced = tmp / model / src.stem
    if not produced.exists():
        # demucs sanitises the track-folder name; find the single subdir
        cand = list((tmp / model).glob("*"))
        produced = cand[0] if cand else produced
    moved = 0
    for stem in STEM_NAMES:
        wav = produced / f"{stem}.wav"
        if wav.exists():
            shutil.move(str(wav), str(dest / f"{stem}.wav"))
            moved += 1
    # 6-stem model also yields guitar/piano — keep them as bonus "melody"
    for extra in ("guitar", "piano"):
        wav = produced / f"{extra}.wav"
        if wav.exists():
            shutil.move(str(wav), str(dest / f"{extra}.wav"))
    shutil.rmtree(tmp, ignore_errors=True)
    if moved == 0:
        print(f"  FAIL: {src.name}: no stems produced", file=sys.stderr)
        return None
    print(f"  ok: {src.name} -> {dest}  ({moved} stems)")
    return dest


def main():
    ap = argparse.ArgumentParser(description="AutoMix Demucs stem splitter")
    ap.add_argument("inputs", nargs="+", help="audio file(s)")
    ap.add_argument("--out", default="stems", help="stems root dir")
    ap.add_argument("--model", default="htdemucs",
                    help="demucs model (htdemucs | htdemucs_6s)")
    ap.add_argument("--force", action="store_true")
    args = ap.parse_args()

    if not have_demucs():
        print("demucs not installed. `pip install demucs torch` first.",
              file=sys.stderr)
        sys.exit(2)

    ok = 0
    for inp in args.inputs:
        if separate(inp, args.out, model=args.model, force=args.force):
            ok += 1
    print(f"\ndone: {ok}/{len(args.inputs)} tracks separated")


if __name__ == "__main__":
    main()
