#!/usr/bin/env python3
"""
AutoMix offline track analyzer.

Produces one `*.automix.json` sidecar per song containing everything the
on-device transition engine needs but can't compute live on a phone:

  - precise BPM + beat grid + downbeats
  - musical key + Camelot notation
  - song structure (intro / verse / chorus / bridge / outro / breakdown / drop)
  - per-section energy + vocal ratio
  - integrated loudness (LUFS)
  - mix-in / mix-out cue points (downbeat-aligned)
  - stem manifest (filled in by stems.py when Demucs has run)

The sidecar schema is versioned (`schema` field). The Dart side
(`app/lib/features/automix/model/track_analysis.dart`) parses exactly this
shape, so keep the two in lock-step.

Run:
    python tools/automix/analyze.py "songs/Some Track(MP3_320K).mp3"
    python tools/automix/analyze.py --out analysis "songs/*.mp3"

Heavy DSP (Demucs stem separation) lives in stems.py and is NOT run here;
this analyzer is CPU-only librosa and finishes in a few seconds per track.
"""

from __future__ import annotations

import argparse
import json
import math
import re
import sys
from dataclasses import asdict, dataclass, field
from pathlib import Path

import numpy as np

SCHEMA_VERSION = 1

# Camelot wheel: (tonic pitch-class 0=C..11=B, mode) -> "8B" etc.
# Major = "B" ring, minor = "A" ring. Built from the canonical wheel.
_CAMELOT = {
    # majors (B ring)
    (0, "major"): "8B", (7, "major"): "9B", (2, "major"): "10B",
    (9, "major"): "11B", (4, "major"): "12B", (11, "major"): "1B",
    (6, "major"): "2B", (1, "major"): "3B", (8, "major"): "4B",
    (3, "major"): "5B", (10, "major"): "6B", (5, "major"): "7B",
    # minors (A ring)
    (9, "minor"): "8A", (4, "minor"): "9A", (11, "minor"): "10A",
    (6, "minor"): "11A", (1, "minor"): "12A", (8, "minor"): "1A",
    (3, "minor"): "2A", (10, "minor"): "3A", (5, "minor"): "4A",
    (0, "minor"): "5A", (7, "minor"): "6A", (2, "minor"): "7A",
}
_PITCH_NAMES = ["C", "C#", "D", "D#", "E", "F",
                "F#", "G", "G#", "A", "A#", "B"]

# Krumhansl-Kessler key profiles (major / minor), normalized at use time.
_KK_MAJOR = np.array([6.35, 2.23, 3.48, 2.33, 4.38, 4.09,
                      2.52, 5.19, 2.39, 3.66, 2.29, 2.88])
_KK_MINOR = np.array([6.33, 2.68, 3.52, 5.38, 2.60, 3.53,
                      2.54, 4.75, 3.98, 2.69, 3.34, 3.17])

# Section labels the engine understands. Order roughly low->high energy
# for the labeler's convenience.
LABELS = ["intro", "breakdown", "bridge", "verse", "chorus", "drop", "outro"]


# --------------------------------------------------------------------------
# dataclasses mirroring the sidecar JSON shape
# --------------------------------------------------------------------------
@dataclass
class BeatGrid:
    first_beat_sec: float
    beats_per_bar: int
    beat_times: list[float]
    downbeat_times: list[float]


@dataclass
class MusicalKey:
    tonic: str          # "A", "C#", ...
    mode: str           # "major" | "minor"
    camelot: str        # "8A", "11B", ...
    confidence: float   # 0..1


@dataclass
class Section:
    label: str          # one of LABELS
    start_sec: float
    end_sec: float
    energy: float       # 0..1, relative to track peak
    vocal_ratio: float  # 0..1, fraction of section that is vocal-dominant


@dataclass
class CuePoints:
    mix_in_sec: float       # where an incoming track should be brought in
    mix_out_sec: float      # where the outgoing track should start mixing out
    intro_end_sec: float
    outro_start_sec: float
    first_drop_sec: float | None


@dataclass
class Stems:
    available: bool = False
    model: str | None = None
    dir: str | None = None
    files: dict = field(default_factory=dict)


@dataclass
class TrackAnalysis:
    schema: int
    file: str
    duration_sec: float
    sample_rate: int
    bpm: float
    bpm_confidence: float
    beat_grid: BeatGrid
    key: MusicalKey
    lufs: float
    sections: list[Section]
    cue_points: CuePoints
    vocal_source: str       # "stems" | "proxy"
    stems: Stems

    def to_json(self) -> dict:
        d = asdict(self)
        # round floats for a compact, diff-friendly sidecar
        return _round_floats(d, 4)


# --------------------------------------------------------------------------
# helpers
# --------------------------------------------------------------------------
def _round_floats(obj, ndigits):
    if isinstance(obj, float):
        if math.isnan(obj) or math.isinf(obj):
            return None
        return round(obj, ndigits)
    if isinstance(obj, list):
        return [_round_floats(x, ndigits) for x in obj]
    if isinstance(obj, dict):
        return {k: _round_floats(v, ndigits) for k, v in obj.items()}
    return obj


def slugify(name: str) -> str:
    # NOTE: must stay byte-identical to AnalysisStore.slugify in the Dart app
    # (app/lib/features/automix/runtime/analysis_store.dart) — that's the join
    # key between a sidecar and a SongRow. Dart's core has no Unicode NFKD,
    # so we deliberately do NOT fold accents here: a non-[a-z0-9] char becomes
    # "_" on BOTH sides, keeping the slug consistent (if uglier) for titles
    # like "Jhené Aiko".
    name = name.lower()
    name = re.sub(r"\(mp3_320k\)", "", name)
    name = re.sub(r"[^a-z0-9]+", "_", name).strip("_")
    return name or "track"


def _as_scalar(x) -> float:
    """librosa sometimes returns a 0-d / 1-elem array for tempo."""
    arr = np.atleast_1d(np.asarray(x, dtype=float))
    return float(arr.flat[0])


# --------------------------------------------------------------------------
# analysis stages
# --------------------------------------------------------------------------
def _estimate_tempo_and_beats(y, sr):
    import librosa
    onset_env = librosa.onset.onset_strength(y=y, sr=sr)
    tempo, beat_frames = librosa.beat.beat_track(
        onset_envelope=onset_env, sr=sr, trim=False
    )
    tempo = _as_scalar(tempo)
    beat_times = librosa.frames_to_time(beat_frames, sr=sr).tolist()

    # Refine tempo from the median inter-beat interval — beat_track's global
    # estimate can lock to a half/double value; the median IBI is steadier.
    conf = 0.0
    if len(beat_times) >= 4:
        ibis = np.diff(beat_times)
        ibis = ibis[(ibis > 0.2) & (ibis < 2.0)]  # 30..300 BPM sanity window
        if len(ibis) >= 3:
            med = float(np.median(ibis))
            if med > 0 and tempo > 0:
                refined = 60.0 / med
                # only trust the refinement if it's close to a (half/double)
                # multiple of the tracker's tempo
                for mult in (0.5, 1.0, 2.0):
                    if abs(refined - tempo * mult) / (tempo * mult) < 0.08:
                        tempo = refined
                        break
            # confidence: how tight the IBI distribution is (low CV -> high conf)
            cv = float(np.std(ibis) / (np.mean(ibis) + 1e-9))
            conf = float(max(0.0, min(1.0, 1.0 - cv * 2.0)))
    return tempo, beat_times, onset_env, beat_frames, conf


def _estimate_downbeats(onset_env, sr, beat_frames, beat_times, beats_per_bar=4):
    """Pick the bar phase (0..beats_per_bar-1) whose beats carry the most
    onset energy, then mark every `beats_per_bar`-th beat from there."""
    import librosa
    if len(beat_times) < beats_per_bar:
        return beat_times[:1]
    # onset strength sampled at each beat
    strengths = onset_env[np.clip(beat_frames, 0, len(onset_env) - 1)]
    best_phase, best_sum = 0, -1.0
    for phase in range(beats_per_bar):
        s = float(np.sum(strengths[phase::beats_per_bar]))
        if s > best_sum:
            best_sum, best_phase = s, phase
    downbeats = [beat_times[i] for i in range(best_phase, len(beat_times), beats_per_bar)]
    return downbeats


def _estimate_key(y, sr):
    import librosa
    chroma = librosa.feature.chroma_cqt(y=y, sr=sr)
    profile = np.mean(chroma, axis=1)
    profile = profile / (np.linalg.norm(profile) + 1e-9)

    maj = _KK_MAJOR / np.linalg.norm(_KK_MAJOR)
    minr = _KK_MINOR / np.linalg.norm(_KK_MINOR)

    best = (-2.0, 0, "major")
    scores = []
    for tonic in range(12):
        rot = np.roll(profile, -tonic)
        cmaj = float(np.dot(rot, maj))
        cmin = float(np.dot(rot, minr))
        scores.append(cmaj)
        scores.append(cmin)
        if cmaj > best[0]:
            best = (cmaj, tonic, "major")
        if cmin > best[0]:
            best = (cmin, tonic, "minor")

    corr, tonic, mode = best
    scores = np.array(scores)
    # confidence via softmax over the 24 key correlations: a clear winner
    # (one key correlating far above the rest) -> high confidence; an
    # ambiguous chroma (many keys near-tied) -> low. Temperature 12 keeps
    # the KK correlation spread (~0.05 wide) in a usable 0..1 range.
    sm = np.exp((scores - scores.max()) * 12.0)
    sm = sm / (sm.sum() + 1e-9)
    conf = float(max(0.0, min(1.0, sm.max() * 2.0)))
    camelot = _CAMELOT.get((tonic, mode), "?")
    return MusicalKey(tonic=_PITCH_NAMES[tonic], mode=mode,
                      camelot=camelot, confidence=conf)


def _measure_lufs(y, sr):
    try:
        import pyloudnorm as pyln
        meter = pyln.Meter(sr)
        loud = meter.integrated_loudness(y.astype(np.float64))
        if math.isinf(loud) or math.isnan(loud):
            # unknown loudness -> assume the -14 LUFS streaming target so the
            # planner's loudness match is a no-op rather than a surprise boost.
            # Must match the Dart parser's fallback (track_analysis.dart).
            return -14.0
        return float(loud)
    except Exception:
        # RMS fallback ~ rough dBFS, not true LUFS
        rms = float(np.sqrt(np.mean(y ** 2)) + 1e-9)
        return float(20 * math.log10(rms))


def _segment(y, sr, beat_times):
    """Beat-synchronous agglomerative segmentation into structural sections."""
    import librosa
    duration = librosa.get_duration(y=y, sr=sr)
    # feature stack: CQT (harmony/repetition) + MFCC (timbre)
    cqt = np.abs(librosa.cqt(y=y, sr=sr))
    cqt_db = librosa.amplitude_to_db(cqt, ref=np.max)
    mfcc = librosa.feature.mfcc(y=y, sr=sr, n_mfcc=13)

    beat_frames = librosa.time_to_frames(beat_times, sr=sr)
    beat_frames = np.unique(np.clip(beat_frames, 0, cqt_db.shape[1] - 1))
    if len(beat_frames) < 4:
        return [(0.0, duration)]

    csync = librosa.util.sync(cqt_db, beat_frames, aggregate=np.median)
    msync = librosa.util.sync(mfcc, beat_frames, aggregate=np.mean)
    feat = np.vstack([
        librosa.util.normalize(csync, axis=0),
        librosa.util.normalize(msync, axis=0),
    ])

    # target ~1 boundary per 18s, clamped to a sane structural range
    k = int(np.clip(round(duration / 18.0), 4, 10))
    k = min(k, feat.shape[1] - 1)
    try:
        bound_beats = librosa.segment.agglomerative(feat, k)
    except Exception:
        return [(0.0, duration)]
    # librosa.util.sync yields one more column than len(beat_frames), so an
    # agglomerative boundary index can equal len(beat_frames) and overflow
    # the beat_frames lookup — clip it to the last valid beat.
    bound_beats = np.clip(bound_beats, 0, len(beat_frames) - 1)
    bound_times = librosa.frames_to_time(
        beat_frames[bound_beats], sr=sr
    ).tolist()
    bounds = sorted(set([0.0] + bound_times + [duration]))
    segs = [(bounds[i], bounds[i + 1]) for i in range(len(bounds) - 1)
            if bounds[i + 1] - bounds[i] > 1.0]
    return segs or [(0.0, duration)]


def _section_energy(y, sr, start, end):
    a = int(start * sr)
    b = min(int(end * sr), len(y))
    if b <= a:
        return 0.0
    seg = y[a:b]
    return float(np.sqrt(np.mean(seg ** 2)) + 1e-9)


def _voiceness_raw(y, sr, start, end):
    """No-stems 'voiceness' for one section: harmonic (not percussive)
    energy in the 300-3400 Hz voice band, weighted by tonality (low
    spectral flatness = tonal lead/vocal rather than broadband noise).
    Returned RAW — normalized track-relative by the caller so sections get
    a real spread instead of all saturating to 1.0. Replaced by exact stem
    ratio when Demucs output is present (vocal_source == 'stems')."""
    import librosa
    a = int(start * sr)
    b = min(int(end * sr), len(y))
    if b <= a + sr // 4:
        return 0.0
    seg = y[a:b]
    harm = librosa.effects.harmonic(seg)
    S = np.abs(librosa.stft(harm, n_fft=2048))
    freqs = librosa.fft_frequencies(sr=sr, n_fft=2048)
    band = (freqs >= 300) & (freqs <= 3400)
    voice = float(np.mean(S[band, :]))
    total = float(np.mean(S)) + 1e-9
    flat = float(np.mean(librosa.feature.spectral_flatness(S=S[band, :] + 1e-9)))
    return (voice / total) * (1.0 - flat)


def _normalize_voiceness(raws):
    """Map raw per-section voiceness to 0..1 via a track-relative sigmoid
    around the median, so the most vocal sections approach 1 and the most
    instrumental approach 0 *within this track* (what the engine needs to
    pick an instrumental mix point)."""
    arr = np.asarray(raws, dtype=float)
    if len(arr) == 0:
        return []
    med = float(np.median(arr))
    spread = float(np.std(arr)) + 1e-6
    z = (arr - med) / spread
    return [float(1.0 / (1.0 + math.exp(-zi))) for zi in z]


def _vocal_ratio_from_stem(vocals_path, sr, start, end, mix_seg_rms):
    import soundfile as sf
    try:
        v, vsr = sf.read(vocals_path, always_2d=False)
        if v.ndim > 1:
            v = v.mean(axis=1)
        a = int(start * vsr)
        b = min(int(end * vsr), len(v))
        if b <= a:
            return 0.0
        vrms = float(np.sqrt(np.mean(v[a:b] ** 2)) + 1e-9)
        return float(max(0.0, min(1.0, vrms / (mix_seg_rms + 1e-9))))
    except Exception:
        return 0.0


def _label_sections(sections_raw, energies_norm, vocals, duration):
    """Heuristic structural labeling. NOT ground truth — uses position +
    relative energy + vocal presence. Good enough to drive transition
    preferences (outro->intro, breakdown->drop, instrumental->vocal)."""
    n = len(sections_raw)
    labels = ["verse"] * n
    if n == 0:
        return labels
    if n == 1:
        # a lone section can't be both intro and outro; leave it neutral so
        # cue derivation doesn't tag the whole track 'outro'
        return ["verse"]
    e = np.array(energies_norm)
    hi = float(np.percentile(e, 75)) if n >= 3 else 0.6
    lo = float(np.percentile(e, 30)) if n >= 3 else 0.3
    peak = float(e.max())

    for i, ((s, en), eg, vr) in enumerate(zip(sections_raw, e, vocals)):
        first = i == 0
        last = i == n - 1
        if first and eg <= e.mean():
            labels[i] = "intro"
        elif last and eg <= e.mean():
            labels[i] = "outro"
        elif eg >= hi and vr < 0.25:
            labels[i] = "drop"          # high energy, low vocal -> drop
        elif eg >= hi:
            labels[i] = "chorus"        # high energy with vocals -> chorus
        elif eg <= lo and vr < 0.2:
            labels[i] = "breakdown"     # low energy, sparse -> breakdown
        elif eg <= lo:
            labels[i] = "bridge"
        else:
            labels[i] = "verse"
    # ensure the very first/last are intro/outro even if energetic
    labels[0] = "intro"
    labels[-1] = "outro"
    return labels


def _cue_points(sections, downbeats, duration):
    intro_end = sections[0].end_sec if sections else 0.0
    outro_start = sections[-1].start_sec if sections else duration

    def nearest_downbeat(t):
        if not downbeats:
            return t
        return min(downbeats, key=lambda d: abs(d - t))

    mix_in = nearest_downbeat(intro_end)
    mix_out = nearest_downbeat(outro_start)
    # mix_out shouldn't be the literal last beat; pull it ~16s before end if
    # the outro is tiny/missing
    if duration - mix_out < 4.0:
        mix_out = nearest_downbeat(max(0.0, duration - 16.0))

    first_drop = None
    for s in sections:
        if s.label == "drop":
            first_drop = s.start_sec
            break
    return CuePoints(
        mix_in_sec=float(mix_in),
        mix_out_sec=float(mix_out),
        intro_end_sec=float(intro_end),
        outro_start_sec=float(outro_start),
        first_drop_sec=first_drop,
    )


# --------------------------------------------------------------------------
# top level
# --------------------------------------------------------------------------
def analyze_file(path: str, stems_dir: str | None = None,
                 sr_target: int = 22050) -> TrackAnalysis:
    import librosa
    y, sr = librosa.load(path, sr=sr_target, mono=True)
    duration = float(librosa.get_duration(y=y, sr=sr))

    bpm, beat_times, onset_env, beat_frames, bpm_conf = \
        _estimate_tempo_and_beats(y, sr)
    downbeats = _estimate_downbeats(onset_env, sr, beat_frames, beat_times)
    key = _estimate_key(y, sr)
    lufs = _measure_lufs(y, sr)

    segs = _segment(y, sr, beat_times)
    raw_energy = [_section_energy(y, sr, s, e) for s, e in segs]
    peak = max(raw_energy) if raw_energy else 1.0
    energies_norm = [v / (peak + 1e-9) for v in raw_energy]

    # vocal ratio: exact from stems if present, else proxy
    vocals_path = None
    vocal_source = "proxy"
    if stems_dir:
        cand = Path(stems_dir) / "vocals.wav"
        if cand.exists():
            vocals_path = str(cand)
            vocal_source = "stems"
    if vocals_path:
        vocals = [_vocal_ratio_from_stem(vocals_path, sr, s, e, rms)
                  for (s, e), rms in zip(segs, raw_energy)]
    else:
        raws = [_voiceness_raw(y, sr, s, e) for (s, e) in segs]
        vocals = _normalize_voiceness(raws)

    labels = _label_sections(list(zip(segs, raw_energy)),
                             energies_norm, vocals, duration)
    sections = [
        Section(label=labels[i], start_sec=float(segs[i][0]),
                end_sec=float(segs[i][1]), energy=float(energies_norm[i]),
                vocal_ratio=float(vocals[i]))
        for i in range(len(segs))
    ]
    cues = _cue_points(sections, downbeats, duration)

    return TrackAnalysis(
        schema=SCHEMA_VERSION,
        file=Path(path).name,
        duration_sec=duration,
        sample_rate=sr,
        bpm=float(bpm),
        bpm_confidence=float(bpm_conf),
        beat_grid=BeatGrid(
            first_beat_sec=float(beat_times[0]) if beat_times else 0.0,
            beats_per_bar=4,
            beat_times=[float(t) for t in beat_times],
            downbeat_times=[float(t) for t in downbeats],
        ),
        key=key,
        lufs=float(lufs),
        sections=sections,
        cue_points=cues,
        vocal_source=vocal_source,
        stems=Stems(),  # filled by stems.py
    )


def main():
    ap = argparse.ArgumentParser(description="AutoMix track analyzer")
    ap.add_argument("inputs", nargs="+", help="audio file(s)")
    ap.add_argument("--out", default="analysis",
                    help="output dir for *.automix.json (default: analysis/)")
    ap.add_argument("--stems-root", default=None,
                    help="root dir of demucs stems (<root>/<slug>/vocals.wav)")
    ap.add_argument("--force", action="store_true",
                    help="re-analyze even if a sidecar already exists")
    args = ap.parse_args()

    out_dir = Path(args.out)
    out_dir.mkdir(parents=True, exist_ok=True)

    for inp in args.inputs:
        p = Path(inp)
        if not p.exists():
            print(f"  skip (missing): {inp}", file=sys.stderr)
            continue
        slug = slugify(p.stem)
        out_path = out_dir / f"{slug}.automix.json"
        if out_path.exists() and not args.force:
            print(f"  skip (done):    {p.name}")
            continue
        stems_dir = None
        if args.stems_root:
            cand = Path(args.stems_root) / slug
            if cand.exists():
                stems_dir = str(cand)
        try:
            res = analyze_file(str(p), stems_dir=stems_dir)
            out_path.write_text(json.dumps(res.to_json(), indent=2),
                                encoding="utf-8")
            k = res.key
            print(f"  ok: {p.name}  ->  {res.bpm:.1f} BPM  "
                  f"{k.tonic}{'m' if k.mode=='minor' else ''} ({k.camelot})  "
                  f"{len(res.sections)} sections  {res.lufs:.1f} LUFS")
        except Exception as e:  # noqa: BLE001
            print(f"  FAIL: {p.name}: {e}", file=sys.stderr)


if __name__ == "__main__":
    main()
