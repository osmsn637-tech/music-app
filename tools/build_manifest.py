#!/usr/bin/env python3
"""
Build build/dj_voice_bank/manifest.json from docs/dj-voice-bank-script.md.

Right now the selector only filters on (intent, position, mode, songId,
priority). It doesn't know about artistId yet. So this builder ONLY emits
manifest entries for clips that the current selector can actually pick:

  - generic clips: filtered by intent (and mode/position when applicable)
  - mode-intro clips: filtered by intent=intro_set + position=opener + mode

Artist and song clips are deliberately skipped until the artistId selector
field lands and songId placeholders get wired to real library ids.
"""

from __future__ import annotations

import json
import re
from pathlib import Path

ROW = re.compile(r"^\s*\|\s*`([a-z0-9_]+)`\s*\|\s*(.+?)\s*\|\s*$")

# Map generic intent ids to the (intent, mode?, position?) filter set.
GENERIC_FILTERS = {
    "intro_set":          {"intent": "intro_set", "position": "opener"},
    "set_closer":         {"intent": "set_closer", "position": "closer"},
    "next_track":         {"intent": "next_track"},
    "energy_up":          {"intent": "energy_up"},
    "energy_down":        {"intent": "energy_down"},
    "keep_vibe":          {"intent": "keep_vibe"},
    "study_focus":        {"intent": "study_focus", "mode": "study"},
    "chill_transition":   {"intent": "chill_transition", "mode": "chill"},
    "workout_boost":      {"intent": "workout_boost", "mode": "workout"},
    "night_drive":        {"intent": "night_drive", "mode": "night"},
    "discovery":          {"intent": "discovery"},
    "throwback":          {"intent": "throwback"},
    "favorite_return":    {"intent": "favorite_return"},
    "artist_spotlight":   {"intent": "artist_spotlight"},
    "mood_shift":         {"intent": "mood_shift"},
    "recover_from_skip":  {"intent": "recover_from_skip"},
    "lyric_anchor":       {"intent": "next_track"},  # treat as a flavor of next_track
}

REPO = Path(__file__).resolve().parent.parent
SCRIPT_MD = REPO / "docs" / "dj-voice-bank-script.md"
BANK_DIR = REPO / "build" / "dj_voice_bank"


def parse_ids() -> list[str]:
    ids: list[str] = []
    seen: set[str] = set()
    for raw in SCRIPT_MD.read_text(encoding="utf-8").splitlines():
        m = ROW.match(raw)
        if not m:
            continue
        cid = m.group(1)
        if cid in seen:
            continue
        seen.add(cid)
        ids.append(cid)
    return ids


def relative_path(clip_id: str) -> Path:
    if clip_id.startswith("mode_intro_"):
        rest = clip_id[len("mode_intro_"):]
        mode = re.sub(r"_\d+$", "", rest)
        return Path("mode_intros") / mode / f"{clip_id}.opus"
    if clip_id.startswith("gen_"):
        return Path("generic") / f"{clip_id}.opus"
    if clip_id.startswith("artist_"):
        slug = re.sub(r"_\d+$", "", clip_id[len("artist_"):]).replace("_", "-")
        return Path("artists") / slug / f"{clip_id}.opus"
    if clip_id.startswith("song_"):
        rest = clip_id[len("song_"):]
        slug = re.sub(r"_(?:lyric_)?\d+$", "", rest).replace("_", "-")
        return Path("songs") / slug / f"{clip_id}.opus"
    return Path(f"{clip_id}.opus")


def filters_for(clip_id: str) -> dict | None:
    """Returns the manifest filter dict for clip ids the selector supports.
    Returns None for clip kinds the selector can't pick yet."""
    if clip_id.startswith("mode_intro_"):
        rest = clip_id[len("mode_intro_"):]
        mode = re.sub(r"_\d+$", "", rest)
        return {
            "intent": "intro_set",
            "position": "opener",
            "mode": mode,
            "priority": 5,  # outranks generic intro_set
        }
    if clip_id.startswith("gen_"):
        # gen_<intent>_<NNN>  —  intent is everything between "gen_" and "_NNN"
        body = clip_id[len("gen_"):]
        body = re.sub(r"_\d+$", "", body)
        if body in GENERIC_FILTERS:
            return dict(GENERIC_FILTERS[body])
    if clip_id.startswith("artist_"):
        slug = re.sub(r"_\d+$", "", clip_id[len("artist_"):]).replace("_", "-")
        return {"artistId": slug, "priority": 5}
    if clip_id.startswith("song_"):
        # song_<slug>_<NNN> OR song_<slug>_lyric_<NNN>
        rest = clip_id[len("song_"):]
        slug = re.sub(r"_(?:lyric_)?\d+$", "", rest).replace("_", "-")
        return {"songSlug": slug, "priority": 10}
    return None


def main() -> None:
    BANK_DIR.mkdir(parents=True, exist_ok=True)
    ids = parse_ids()

    clips = []
    skipped = 0
    missing_audio = 0
    for cid in ids:
        f = filters_for(cid)
        if f is None:
            skipped += 1
            continue
        rel = relative_path(cid)
        if not (BANK_DIR / rel).exists():
            missing_audio += 1
            continue
        entry = {"id": cid, "path": rel.as_posix()}
        entry.update(f)
        clips.append(entry)

    manifest = {
        "version": 1,
        "voiceId": "deep_host",
        "clips": clips,
    }
    out = BANK_DIR / "manifest.json"
    out.write_text(json.dumps(manifest, indent=2), encoding="utf-8")

    print(f"manifest written: {out}")
    print(f"clips emitted:    {len(clips)}")
    print(f"clips skipped:    {skipped} (artist/song — selector doesn't filter yet)")
    print(f"audio missing:    {missing_audio} (still rendering)")


if __name__ == "__main__":
    main()
