#!/usr/bin/env python3
"""
Prep one source mp3 of the target voice into F5-TTS fine-tune training data.

Pipeline:
  1. Trim the first N seconds (default 10) to drop a music intro.
  2. Resample to 16 kHz mono WAV (what F5-TTS expects).
  3. Transcribe with faster-whisper, with VAD enabled - silence and
     non-speech are dropped automatically.
  4. Slice the trimmed audio into per-segment WAVs paired with text.
  5. Drop segments outside [2 s, 15 s] or with non-speech text
     ("[Music]", "(laughter)", < 3 words).
  6. Loudness-normalize each clip to -23 LUFS.
  7. Write LJSpeech-style metadata.csv plus a wavs/ folder.

Output layout (ready to feed to an F5-TTS fine-tune notebook):
  <output>/
    metadata.csv           # id|text|duration_s  (pipe-delimited)
    wavs/
      0001.wav
      0002.wav
      ...

One-time deps:
  pip install faster-whisper
  ffmpeg on PATH (https://www.gyan.dev/ffmpeg/builds/ on Windows)

Example:
  python tools/prepare_training_data.py \\
      --input "C:/Users/Osman/Music/voice-source.mp3" \\
      --output data/training \\
      --skip-intro 10 \\
      --whisper-model large-v3
"""

from __future__ import annotations

import argparse
import csv
import re
import shutil
import subprocess
import sys
from pathlib import Path

NON_SPEECH = re.compile(r"^\s*[\[(].*[\])]\s*$")  # [Music], (laughter), ...
MIN_CHUNK_S = 2.0
MAX_CHUNK_S = 15.0
MIN_WORDS = 3


def run(cmd: list[str]) -> None:
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        sys.stderr.write(result.stderr or "")
        raise SystemExit(f"ffmpeg failed: {' '.join(cmd)}")


def check_deps() -> None:
    if shutil.which("ffmpeg") is None:
        sys.exit("ffmpeg not found on PATH - install it first.")
    try:
        import faster_whisper  # noqa: F401
    except ImportError:
        sys.exit("faster-whisper not installed - run: pip install faster-whisper")


def trim_and_resample(src: Path, dst: Path, skip_intro: float) -> None:
    """Trim leading skip_intro seconds, downmix to mono, resample to 16 kHz."""
    run([
        "ffmpeg", "-y", "-loglevel", "error",
        "-i", str(src),
        "-ss", str(skip_intro),
        "-ac", "1",
        "-ar", "16000",
        "-c:a", "pcm_s16le",
        str(dst),
    ])


def transcribe(audio: Path, model_name: str):
    """Returns a list of (start_s, end_s, text)."""
    from faster_whisper import WhisperModel

    print(f"[whisper] loading {model_name} (downloads on first run)...")
    model = WhisperModel(model_name, device="auto", compute_type="auto")
    print(f"[whisper] transcribing {audio.name} - CPU runs take 15-30 min "
          f"per hour of audio, GPU is much faster.")
    segments_iter, info = model.transcribe(
        str(audio),
        language="en",
        vad_filter=True,                      # silence + non-speech dropped
        vad_parameters={"min_silence_duration_ms": 500},
        word_timestamps=False,
        condition_on_previous_text=False,    # avoids drift on long files
    )
    segments = []
    for seg in segments_iter:
        text = seg.text.strip()
        if text:
            segments.append((seg.start, seg.end, text))
    print(f"[whisper] {len(segments)} segments over {info.duration:.0f}s of audio")
    return segments


def keep_segment(start: float, end: float, text: str) -> bool:
    dur = end - start
    if dur < MIN_CHUNK_S or dur > MAX_CHUNK_S:
        return False
    if NON_SPEECH.match(text):
        return False
    if len(text.split()) < MIN_WORDS:
        return False
    return True


def slice_and_normalize(src: Path, start: float, end: float, dst: Path) -> None:
    """Cut [start, end] from src and loudness-normalize to -23 LUFS."""
    dur = end - start
    run([
        "ffmpeg", "-y", "-loglevel", "error",
        "-ss", str(start),
        "-i", str(src),
        "-t", str(dur),
        "-af", "loudnorm=I=-23:LRA=7:TP=-2",
        "-ar", "16000",
        "-ac", "1",
        "-c:a", "pcm_s16le",
        str(dst),
    ])


def main() -> None:
    p = argparse.ArgumentParser(
        description="Prep target-voice mp3 into F5-TTS training data.",
    )
    p.add_argument("--input", required=True, type=Path,
                   help="Source mp3 of the target voice.")
    p.add_argument("--output", required=True, type=Path,
                   help="Output directory for wavs/ + metadata.csv.")
    p.add_argument("--skip-intro", type=float, default=10.0,
                   help="Seconds to trim from the start (e.g. music intro).")
    p.add_argument("--whisper-model", default="large-v3",
                   help="faster-whisper model id "
                        "(tiny / base / small / medium / large-v3).")
    args = p.parse_args()

    check_deps()

    src: Path = args.input.resolve()
    if not src.exists():
        sys.exit(f"input not found: {src}")

    out: Path = args.output.resolve()
    out.mkdir(parents=True, exist_ok=True)
    (out / "wavs").mkdir(exist_ok=True)
    work = out / ".work"
    work.mkdir(exist_ok=True)

    trimmed = work / "full_trimmed.wav"
    print(f"[prep] trimming first {args.skip_intro:.0f}s + resampling -> "
          f"{trimmed.relative_to(out.parent)}")
    trim_and_resample(src, trimmed, args.skip_intro)

    segments = transcribe(trimmed, args.whisper_model)

    metadata: list[tuple[str, str, float]] = []
    kept = 0
    dropped = 0
    for start, end, text in segments:
        if not keep_segment(start, end, text):
            dropped += 1
            continue
        kept += 1
        clip_id = f"{kept:04d}"
        slice_and_normalize(trimmed, start, end, out / "wavs" / f"{clip_id}.wav")
        metadata.append((clip_id, text, end - start))

    csv_path = out / "metadata.csv"
    with csv_path.open("w", encoding="utf-8", newline="") as f:
        w = csv.writer(f, delimiter="|")
        w.writerow(["id", "text", "duration_s"])
        for row in metadata:
            w.writerow([row[0], row[1], f"{row[2]:.2f}"])

    total_min = sum(d for _, _, d in metadata) / 60.0
    print()
    print(f"[prep] kept {kept} / dropped {dropped}")
    print(f"[prep] {total_min:.1f} min of clean training audio")
    print(f"[prep] metadata: {csv_path}")
    print(f"[prep] wavs:     {out / 'wavs'}")
    print(f"[prep] done.")


if __name__ == "__main__":
    main()
