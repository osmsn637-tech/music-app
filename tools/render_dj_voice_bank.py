#!/usr/bin/env python3
"""
Render the DJ voice bank locally using the fine-tuned F5-TTS checkpoint.

Loads F5-TTS once (not per line), walks docs/dj-voice-bank-script.md,
runs inference for each (id, text) pair, encodes to Opus 32 kbps mono,
and lays the files out under build/dj_voice_bank/ matching the
manifest.seed.json folder structure.

Pre-import setup we care about on Windows:
  - torch is imported FIRST so its native DLLs win the load order over
    pyarrow's bundled copies (segfault otherwise).
  - The Gyan FFmpeg-shared bin folder is added to the Python DLL search
    path so torchcodec can find avcodec / swresample / etc. at runtime.
"""

from __future__ import annotations

# ---- Windows DLL setup (must run before any other imports) ---------------
import os
import sys

if sys.platform == "win32":
    _ffmpeg_dll_dir = (
        r"C:\Users\Osman\AppData\Local\Microsoft\WinGet\Packages"
        r"\Gyan.FFmpeg.Shared_Microsoft.Winget.Source_8wekyb3d8bbwe"
        r"\ffmpeg-8.1-full_build-shared\bin"
    )
    if os.path.isdir(_ffmpeg_dll_dir):
        os.add_dll_directory(_ffmpeg_dll_dir)
        os.environ["PATH"] = _ffmpeg_dll_dir + os.pathsep + os.environ.get("PATH", "")

# Import torch BEFORE any module that might pull in pyarrow.
import torch  # noqa: E402,F401

# ---- Now safe to do the rest ---------------------------------------------
import argparse  # noqa: E402
import re  # noqa: E402
import shutil  # noqa: E402
import subprocess  # noqa: E402
import time  # noqa: E402
from dataclasses import dataclass  # noqa: E402
from pathlib import Path  # noqa: E402

# Markdown rows look like:
#   | `gen_intro_set_001` | Take a breath. The set's about to begin. |
ROW = re.compile(r"^\s*\|\s*`([a-z0-9_]+)`\s*\|\s*(.+?)\s*\|\s*$")


@dataclass(frozen=True)
class Line:
    id: str
    text: str

    @property
    def kind(self) -> str:
        if self.id.startswith("mode_intro_"):
            return "mode_intro"
        if self.id.startswith("gen_"):
            return "generic"
        if self.id.startswith("artist_"):
            return "artist"
        if self.id.startswith("song_"):
            return "song"
        return "other"

    @property
    def relative_path(self) -> Path:
        if self.kind == "generic":
            return Path("generic") / f"{self.id}.opus"
        if self.kind == "mode_intro":
            # mode_intro_<mode>_NNN -> mode_intros/<mode>/<id>.opus
            rest = self.id[len("mode_intro_"):]
            mode = re.sub(r"_\d+$", "", rest)
            return Path("mode_intros") / mode / f"{self.id}.opus"
        if self.kind == "artist":
            slug = self.id[len("artist_"):]
            slug = re.sub(r"_\d+$", "", slug).replace("_", "-")
            return Path("artists") / slug / f"{self.id}.opus"
        if self.kind == "song":
            # song_<slug>_NNN OR song_<slug>_lyric_NNN
            rest = self.id[len("song_"):]
            slug = re.sub(r"_(?:lyric_)?\d+$", "", rest).replace("_", "-")
            return Path("songs") / slug / f"{self.id}.opus"
        return Path(f"{self.id}.opus")


def parse_script(md: Path) -> list[Line]:
    lines: list[Line] = []
    seen: set[str] = set()
    for raw in md.read_text(encoding="utf-8").splitlines():
        m = ROW.match(raw)
        if not m:
            continue
        clip_id, text = m.group(1), m.group(2).strip()
        if not text or text.strip("- ") == "":
            continue
        if clip_id in seen:
            continue
        seen.add(clip_id)
        lines.append(Line(id=clip_id, text=text))
    return lines


def run_ffmpeg(cmd: list[str]) -> None:
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        sys.stderr.write(result.stderr or "")
        raise RuntimeError(f"ffmpeg failed: {' '.join(cmd[:4])} ...")


def encode_opus(wav: Path, opus: Path) -> None:
    """Encode WAV -> Opus 32 kbps mono."""
    opus.parent.mkdir(parents=True, exist_ok=True)
    run_ffmpeg([
        "ffmpeg", "-y", "-loglevel", "error",
        "-i", str(wav),
        "-c:a", "libopus",
        "-b:a", "32k",
        "-ac", "1",
        "-ar", "24000",
        str(opus),
    ])


def main() -> None:
    p = argparse.ArgumentParser(description="Render the DJ voice bank.")
    p.add_argument("--script", type=Path,
                   default=Path("docs/dj-voice-bank-script.md"))
    p.add_argument("--ckpt", type=Path,
                   default=Path("data/dj_voice_inference.pt"),
                   help="Slim inference checkpoint (EMA weights only).")
    p.add_argument("--ref-audio", type=Path,
                   default=Path("data/reference.wav"))
    p.add_argument("--ref-text-file", type=Path,
                   default=Path("data/reference.txt"))
    p.add_argument("--output", type=Path, default=Path("build/dj_voice_bank"))
    p.add_argument("--only", type=str, default=None,
                   help="Comma-separated id prefixes to limit to.")
    p.add_argument("--skip-existing", action="store_true", default=True)
    p.add_argument("--no-skip-existing", dest="skip_existing",
                   action="store_false")
    args = p.parse_args()

    if shutil.which("ffmpeg") is None:
        sys.exit("ffmpeg not found on PATH.")
    for path, label in [
        (args.script, "script"), (args.ckpt, "checkpoint"),
        (args.ref_audio, "ref audio"), (args.ref_text_file, "ref text"),
    ]:
        if not path.exists():
            sys.exit(f"{label} not found: {path}")

    ref_text = args.ref_text_file.read_text(encoding="utf-8").strip()
    if not ref_text or len(ref_text) < 10:
        sys.exit(f"reference text looks wrong: {ref_text!r}")

    lines = parse_script(args.script)
    if args.only:
        prefixes = [x.strip() for x in args.only.split(",") if x.strip()]
        lines = [ln for ln in lines if any(ln.id.startswith(x) for x in prefixes)]

    args.output.mkdir(parents=True, exist_ok=True)
    work = args.output / ".work"
    work.mkdir(exist_ok=True)

    print(f"[render] {len(lines)} lines to process")
    print(f"[render] loading F5-TTS (one-time, ~30-60s)...", flush=True)
    t0 = time.monotonic()
    from f5_tts.api import F5TTS
    model = F5TTS(model="F5TTS_v1_Base", ckpt_file=str(args.ckpt))
    print(f"[render] model loaded in {time.monotonic() - t0:.1f}s", flush=True)

    rendered = 0
    skipped = 0
    failed = 0
    total_render_s = 0.0
    for i, line in enumerate(lines, 1):
        opus_out = args.output / line.relative_path
        if args.skip_existing and opus_out.exists() and opus_out.stat().st_size > 0:
            skipped += 1
            continue

        wav_tmp = work / f"{line.id}.wav"
        t = time.monotonic()
        try:
            model.infer(
                ref_file=str(args.ref_audio),
                ref_text=ref_text,
                gen_text=line.text,
                file_wave=str(wav_tmp),
            )
            elapsed = time.monotonic() - t
            total_render_s += elapsed
            encode_opus(wav_tmp, opus_out)
            wav_tmp.unlink(missing_ok=True)
            rendered += 1
            avg = total_render_s / rendered
            remaining = (len(lines) - i) * avg
            print(
                f"[render] {i:3d}/{len(lines)} {line.id} "
                f"({elapsed:.0f}s, ETA {remaining/60:.0f} min remaining)",
                flush=True,
            )
        except Exception as e:
            failed += 1
            print(f"[render]  ! failed: {line.id}: {e}", file=sys.stderr,
                  flush=True)

    for stale in work.glob("*.wav"):
        stale.unlink(missing_ok=True)

    print()
    print(f"[render] rendered {rendered} / skipped {skipped} / failed {failed}")
    print(f"[render] output:   {args.output}")


if __name__ == "__main__":
    main()
