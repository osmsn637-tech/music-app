# AutoMix engine

An Apple-Music-AutoMix-style transition engine: it analyses tracks offline,
then performs beat-matched, harmonic, stem-aware transitions in the live
player instead of a fixed crossfade.

## Three layers

```
 ┌─ offline (Python, this dir) ──────────────────────────────────────────┐
 │  analyze.py   audio → *.automix.json sidecar                           │
 │               (BPM, beat grid + downbeats, key + Camelot, structure,   │
 │                per-section energy + vocal ratio, LUFS, cue points)     │
 │  stems.py     audio → vocals/drums/bass/other.wav  (Demucs, heavy)     │
 │  batch.py     run both over a whole library, resumable + ETA           │
 └────────────────────────────────────────────────────────────────────────┘
 ┌─ planner (Dart, app/lib/features/automix/{model,engine}) ─────────────┐
 │  pure, deterministic, unit-tested. Loads a sidecar, scores every       │
 │  transition type (§12), picks downbeat-aligned cue points, and emits a │
 │  TransitionPlan = gain/EQ/stem/pitch/tempo automation curves + score.  │
 └────────────────────────────────────────────────────────────────────────┘
 ┌─ runtime (Dart, app/lib/features/automix/runtime) ────────────────────┐
 │  AutoMixEngine drives SoLoud's two decks from the plan: tempo (relative │
 │  play speed) + pitch hold (pitch-shift filter), dynamic EQ (8-band      │
 │  equalizer), reverb/echo sends, master limiter.                         │
 └────────────────────────────────────────────────────────────────────────┘
```

The deterministic planner is the "brain"; SoLoud is the only place hardware
limits bite (see **Honest limits** below).

## Setup (analysis box)

The repo `.venv` is Windows-only. On macOS/Linux:

```bash
python3.12 -m venv .venv-mac-automix
./.venv-mac-automix/bin/pip install librosa pyloudnorm soundfile numpy scipy
# stems only:
./.venv-mac-automix/bin/pip install demucs torch
```

## Running

```bash
# one track
./.venv-mac-automix/bin/python tools/automix/analyze.py "songs/Track(MP3_320K).mp3"

# whole library, fast pass (~7–8 s/track CPU). Resumable.
./.venv-mac-automix/bin/python tools/automix/batch.py songs --out analysis

# full pipeline incl. stems (SLOW: minutes/track, ~50 MB/track)
./.venv-mac-automix/bin/python tools/automix/batch.py songs --out analysis \
    --with-stems --stems-out stems
```

For the ~1172-track library the fast pass is ≈ **2.5 hours** single-process.
Stems are many hours + ~50 GB — run on a GPU box.

Sidecars are keyed by a slug of the audio basename, so the app joins them to
`SongRow.fileName` with no dependency on the DB id scheme.

## Sidecar schema (v1)

`schema:1, file, duration_sec, sample_rate, bpm, bpm_confidence,
beat_grid{first_beat_sec, beats_per_bar, beat_times[], downbeat_times[]},
key{tonic, mode, camelot, confidence}, lufs, sections[{label, start_sec,
end_sec, energy, vocal_ratio}], cue_points{mix_in_sec, mix_out_sec,
intro_end_sec, outro_start_sec, first_drop_sec}, vocal_source, stems{...}`

The Dart parser (`app/lib/features/automix/model/track_analysis.dart`) mirrors
this exactly; the `schema` int guards against drift.

## Wiring the player button

```dart
final autoMix = await ref.read(autoMixServiceProvider.future);
final outcome = await autoMix.mixToNext(current: nowPlaying, next: upNext);
if (outcome != AutoMixOutcome.mixed) {
  await player.playSong(upNext); // fallback hard-cut (e.g. no sidecar yet)
}
```

`planTransition(...)` / `rankTransitions(...)` return the plan(s) without
playing — for a preview/timeline or a "why this mix" panel.
On-device sidecar dir: `<app-support>/automix_analysis/` (see
`providers.dart`); ship/sync sidecars there.

## Honest limits

- **Stems + heavy analysis are offline.** Demucs/structure detection can't run
  live on a phone — exactly how Apple's catalog AutoMix works.
- **Time-stretch** is SoLoud play-speed + pitch-shift correction: clean for the
  ±6 % beat-match range, not Rubber-Band quality for extreme stretches (the
  planner prefers half/double-time to keep stretch small).
- **Structure labels are heuristic** (energy/position/vocal-ratio), not a
  trained segmenter — good enough to drive outro→intro / breakdown→drop
  preferences, not a ground-truth arrangement map.
- **Vocal ratio** is a track-relative proxy until stems exist
  (`vocal_source:"proxy"` vs `"stems"`).
