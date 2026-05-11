#!/usr/bin/env python3
"""
Auto-repair service for the music server.

Three independent passes, run together by default:

  1. **titles** — clean cruft out of sidecar titles / artists in
     content/songs/<id>.json. Strips `(MP3_320K)`, `(Official Video)`,
     `[Lyrics]`, leading BOMs, etc. Pure regex; no internet.

  2. **artwork** — for any song that doesn't already have an artwork file
     under content/artwork/, queries the iTunes Search API by `artist +
     title`, downloads the first hit's 600x600 cover, saves it.

  3. **lyrics** — for any song that doesn't already have an .lrc under
     content/lyrics/, queries LRCLib for time-synced lyrics. Plain (un-
     timed) lyrics are skipped per user preference.

Usage (typical, via docker-compose):
    docker compose --profile tools run --rm repair

Restrict passes:
    docker compose --profile tools run --rm repair --only=lyrics
    docker compose --profile tools run --rm repair --only=titles --only=artwork

Bake the LAN IP into the regenerated manifest:
    docker compose --profile tools run --rm repair \\
        --base-url http://192.168.1.20:8000

Idempotent: re-running only acts on songs that *currently* lack the asset.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
import time
from pathlib import Path
from typing import Optional

try:
    import requests
except ImportError:
    print("error: requests not installed. Run inside the repair Docker image.",
          file=sys.stderr)
    sys.exit(2)


# --- paths ------------------------------------------------------------------

CONTENT_DIR = Path("/content")
SONGS_DIR = CONTENT_DIR / "songs"
ARTWORK_DIR = CONTENT_DIR / "artwork"
LYRICS_DIR = CONTENT_DIR / "lyrics"
ARTISTS_DIR = CONTENT_DIR / "artists"

# --- API endpoints ----------------------------------------------------------

ITUNES_SEARCH = "https://itunes.apple.com/search"
LRCLIB_GET = "https://lrclib.net/api/get"

UA = "music-app-repair/1.0 (personal-library; +https://github.com/local)"

SUPPORTED_AUDIO_EXTS = {".mp3", ".m4a", ".flac", ".ogg", ".opus", ".wav"}
SUPPORTED_ART_EXTS = (".jpg", ".jpeg", ".png", ".webp")

_BOM = "﻿"


# --- title / artist cleanup -------------------------------------------------

# Patterns to strip from titles. Order matters: strip parens / brackets
# first, then specific phrases, so nothing is left straggling.
_TITLE_PATTERNS = [
    re.compile(r"\s*\(MP3[_-]?\d+\s*[Kk]\)\s*"),                 # (MP3_320K)
    re.compile(r"\s*\(Official\s+(?:Music\s+)?Video\)\s*", re.I),
    re.compile(r"\s*\[Official\s+(?:Music\s+)?Video\]\s*", re.I),
    re.compile(r"\s*\(Official\s+Audio\)\s*", re.I),
    re.compile(r"\s*\[Official\s+Audio\]\s*", re.I),
    re.compile(r"\s*\(Audio\)\s*", re.I),
    re.compile(r"\s*\(Visualizer\)\s*", re.I),
    re.compile(r"\s*\(Visualiser\)\s*", re.I),                   # UK spelling
    re.compile(r"\s*\[Official\s+Visualizer\]\s*", re.I),
    re.compile(r"\s*\[Official\s+Visualiser\]\s*", re.I),
    re.compile(r"\s*-\s*Visualiser\s*$", re.I),
    re.compile(r"\s*-\s*Visualizer\s*$", re.I),
    re.compile(r"\s*\(Lyric[s]?(?:\s+Video)?\)\s*", re.I),
    re.compile(r"\s*\[Lyric[s]?(?:\s+Video)?\]\s*", re.I),
    re.compile(r"\s*\(Live[^)]*\)\s*", re.I),
    re.compile(r"\s*\[Live[^\]]*\]\s*", re.I),
    re.compile(r"\s*\((?:HD|HQ|4K|1080p|720p)\)\s*", re.I),
    re.compile(r"\s*\(Bonus\)\s*", re.I),
    re.compile(r"\s*\(Live Performance Video\)\s*", re.I),
    re.compile(r"\s*\(Take My Heart Don.t Break It\)\s*", re.I),  # YT cruft
    # Parenthesized / bracketed feature credits — strip the whole group:
    #   "Calling For You (feat. 21 Savage)" -> "Calling For You"
    #   "K9 (feat. SahBabii)"                -> "K9"
    #   "Track [ft. X & Y]"                  -> "Track"
    re.compile(r"\s*[\(\[]\s*(?:feat\.?|ft\.?|featuring|with)\s+[^)\]]+[\)\]]\s*",
               re.I),
    # Un-parenthesized trailing feature — strip from " ft. " / " feat. " /
    # " featuring " to end of string:
    #   "N 2 Deep ft. Future"               -> "N 2 Deep"
    #   "Knife Talk ft. 21 Savage & Project Pat" -> "Knife Talk"
    re.compile(r"\s+(?:feat\.?|ft\.?|featuring)\s+.+$", re.I),
]

_ARTIST_PATTERNS = [
    re.compile(r"\s*-\s*Topic\s*$", re.I),                        # "Drake - Topic"
    # YouTube-style label suffixes baked into the artist field by some
    # downloaders. "Drake Media", "Travis Scott VEVO", "Artist Records",
    # etc. — strip the noise word, keep the artist.
    re.compile(r"\s+(?:Media|VEVO|Records|Music|Channel|Official)\s*$",
               re.I),
]


def _clean_text(s: str, patterns: list) -> str:
    out = s.lstrip(_BOM).strip()
    for p in patterns:
        out = p.sub(" ", out)
    return re.sub(r"\s+", " ", out).strip()


def clean_title(s: Optional[str], artist: Optional[str] = None) -> Optional[str]:
    if not s:
        return s
    cleaned = _clean_text(s, _TITLE_PATTERNS)
    # Strip a leading "Artist - " or "Artist: " prefix if the title still
    # carries it. Common when ID3 TIT2 was the YouTube video title rather
    # than the song title proper. Fuzzy match so e.g. "J Cole" / "J. Cole"
    # both work.
    if cleaned and artist:
        norm_artist = re.sub(r"[^a-z0-9]+", "", artist.lower())
        if norm_artist:
            m = re.match(
                r"^\s*([^-:]+?)\s*[-:]\s*(.+?)\s*$", cleaned, re.DOTALL,
            )
            if m:
                lhs_norm = re.sub(r"[^a-z0-9]+", "", m.group(1).lower())
                if lhs_norm == norm_artist:
                    cleaned = m.group(2).strip()
    return cleaned or None


def clean_artist(s: Optional[str]) -> Optional[str]:
    if not s:
        return s
    cleaned = _clean_text(s, _ARTIST_PATTERNS)
    return cleaned or None


# Album-field cleanup. YouTube downloaders frequently set the album field to
# `<Artist> - Topic` (the auto-generated YT channel name) instead of the real
# album. Same goes for `(MP3_320K)` and similar downloader cruft. Strip those
# so songs from the same album cluster under one normalized key for the
# album-grouped artwork lookup.
_ALBUM_PATTERNS = [
    re.compile(r"\s*-\s*Topic\s*$", re.I),
    re.compile(r"\s+(?:Media|VEVO|Records|Music|Channel|Official)\s*$", re.I),
    re.compile(r"\s*\(MP3[_-]?\d+\s*[Kk]\)\s*"),
]


def clean_album(s: Optional[str]) -> Optional[str]:
    if not s:
        return s
    cleaned = _clean_text(s, _ALBUM_PATTERNS)
    return cleaned or None


def repair_titles(sidecar: Path, *, dry_run: bool, verbose: bool) -> bool:
    """Returns True if the sidecar was changed."""
    try:
        data = json.loads(sidecar.read_text(encoding="utf-8"))
    except Exception as e:
        print(f"  warn: bad sidecar {sidecar.name}: {e}", file=sys.stderr)
        return False

    changed = False
    artist = data.get("artist")
    new_artist = clean_artist(artist)
    if new_artist and new_artist != artist:
        data["artist"] = new_artist
        changed = True
        artist = new_artist  # use the cleaned value for title de-prefixing

    title = data.get("title")
    new_title = clean_title(title, artist)
    if new_title and new_title != title:
        data["title"] = new_title
        changed = True

    album = data.get("album")
    new_album = clean_album(album)
    if new_album and new_album != album:
        data["album"] = new_album
        changed = True

    if changed:
        if verbose:
            print(f"  title: {sidecar.stem}")
            if new_title and new_title != title:
                print(f"    title:  {title!r} -> {new_title!r}")
            if new_artist and new_artist != artist:
                print(f"    artist: {artist!r} -> {new_artist!r}")
            if new_album and new_album != album:
                print(f"    album:  {album!r} -> {new_album!r}")
        if not dry_run:
            sidecar.write_text(
                json.dumps(data, indent=2, ensure_ascii=False) + "\n",
                encoding="utf-8",
            )
    return changed


# --- artwork via iTunes Search ----------------------------------------------

def has_artwork(song_id: str) -> bool:
    return any((ARTWORK_DIR / f"{song_id}{ext}").exists()
               for ext in SUPPORTED_ART_EXTS)


def _normalize_for_match(s: str) -> str:
    """Lowercase + collapse non-alphanumerics. Helps `A$AP Rocky` and
    `ASAP Rocky` compare as essentially the same string."""
    return re.sub(r"[^a-z0-9]+", " ", s.lower()).strip()


def _strip_artist_prefix(title: str, artist: str) -> str:
    """Some imported titles are `Artist - Title` because the ID3 TIT2 frame
    was the YouTube video title. Strip the leading artist for matching so
    we compare like-with-like."""
    if not artist:
        return title
    pattern = re.compile(
        r"^\s*" + re.escape(artist) + r"\s*[-:]\s*", re.IGNORECASE,
    )
    return pattern.sub("", title)


def _is_good_match(
    query_artist: str,
    query_title: str,
    result_artist: str,
    result_title: str,
) -> tuple[bool, float, float]:
    """Returns `(ok, artist_score, title_score)`. The bool is True if both
    scores clear their thresholds. Thresholds: loose on artist (handles
    A$AP/ASAP, "feat." variations), strict on title — a low title bar
    was the source of mass mis-matches in the wild."""
    from difflib import SequenceMatcher

    q_artist = _normalize_for_match(query_artist)
    q_title = _normalize_for_match(_strip_artist_prefix(query_title, query_artist))
    r_artist = _normalize_for_match(result_artist)
    r_title = _normalize_for_match(result_title)

    if not q_artist or not q_title or not r_artist or not r_title:
        return False, 0.0, 0.0

    artist_score = SequenceMatcher(None, q_artist, r_artist).ratio()
    title_score = SequenceMatcher(None, q_title, r_title).ratio()

    # Allow either substring containment (catches "A$AP Rocky" inside
    # "A$AP Rocky & Tyler, The Creator") to count as an artist match.
    if q_artist in r_artist or r_artist in q_artist:
        artist_score = max(artist_score, 0.9)
    # Same trick for titles — handles "Sicko Mode" inside "Sicko Mode
    # (Remix)" without going over to "Sicko" matching "Sick of It".
    if q_title in r_title or r_title in q_title:
        title_score = max(title_score, 0.9)

    return (artist_score >= 0.75 and title_score >= 0.78,
            artist_score, title_score)


def _combined_score(artist_score: float, title_score: float) -> float:
    """Title carries more weight than artist for picking the best
    candidate among several plausible iTunes hits."""
    return artist_score * 0.4 + title_score * 0.6


def fetch_artwork(
    artist: str,
    title: str,
    session: requests.Session,
    *,
    album_hint: str = "",
    verbose: bool = False,
) -> Optional[tuple[bytes, str]]:
    """Returns (bytes, ext) or None on miss / error / no plausible match.
    Scores ALL plausible candidates and picks the highest scorer — the
    previous "first acceptable hit" logic was the source of many wrong
    covers when iTunes returned a similar-titled but different song
    higher in the list. When [album_hint] is provided we boost matches
    whose collectionName looks like the album the user already has."""
    term = f"{artist} {title}".strip()
    if not term:
        return None
    params = {"term": term, "entity": "song", "limit": 10, "media": "music"}
    try:
        r = session.get(ITUNES_SEARCH, params=params, timeout=(3, 8))
        r.raise_for_status()
        body = r.json()
    except Exception as e:
        print(f"  warn: iTunes search failed for {term!r}: {e}",
              file=sys.stderr)
        return None
    results = body.get("results") or []
    if not results:
        return None

    from difflib import SequenceMatcher
    hint_norm = _normalize_for_match(album_hint)

    # Score every candidate; keep the best one that clears the threshold.
    best: Optional[tuple[float, dict, float, float]] = None
    for cand in results:
        ok, ar_s, ti_s = _is_good_match(
            artist,
            title,
            cand.get("artistName") or "",
            cand.get("trackName") or "",
        )
        if not ok:
            continue
        score = _combined_score(ar_s, ti_s)
        # Album-hint boost: if we know the album the song is on, prefer
        # candidates whose collectionName matches it. Up to +0.10.
        if hint_norm:
            coll = _normalize_for_match(cand.get("collectionName") or "")
            if coll:
                if hint_norm in coll or coll in hint_norm:
                    score += 0.10
                else:
                    score += 0.10 * SequenceMatcher(
                        None, hint_norm, coll,
                    ).ratio()
        # Collection-type bias: prefer the song's *album* release over its
        # single/EP releases. iTunes often returns the single first, which
        # uses different cover art from the album. For tracks like Travis
        # Scott's UTOPIA cuts (also released as singles) and Weeknd hits
        # (singles + albums), this was the mass source of inconsistent
        # covers across same-album tracks. +0.15 for Album, -0.10 for
        # Single, -0.05 for EP — strong enough to flip ties, not so
        # strong that it overrides a clearly better title match.
        coll_type = (cand.get("collectionType") or "").lower()
        if coll_type == "album":
            score += 0.15
        elif coll_type == "single":
            score -= 0.10
        elif coll_type == "ep":
            score -= 0.05
        if best is None or score > best[0]:
            best = (score, cand, ar_s, ti_s)
    if best is None:
        if verbose and results:
            top = results[0]
            print(f"      ✗ rejected all {len(results)} hits; top was "
                  f"{top.get('artistName')!r} – {top.get('trackName')!r}")
        return None
    chosen = best[1]
    if verbose:
        print(f"      → matched {chosen.get('artistName')!r} – "
              f"{chosen.get('trackName')!r} "
              f"[{chosen.get('collectionName') or '?'}] "
              f"(score={best[0]:.2f}, artist={best[2]:.2f}, "
              f"title={best[3]:.2f})")

    art_url = chosen.get("artworkUrl100")
    if not art_url:
        return None
    # Bump 100x100 → 600x600 (iTunes encodes the size in the URL).
    art_url = re.sub(r"/\d+x\d+bb", "/600x600bb", art_url)
    try:
        r = session.get(art_url, timeout=15)
        r.raise_for_status()
    except Exception as e:
        print(f"  warn: artwork download failed: {e}", file=sys.stderr)
        return None
    ct = r.headers.get("Content-Type", "image/jpeg").lower()
    if "png" in ct:
        ext = ".png"
    elif "webp" in ct:
        ext = ".webp"
    else:
        ext = ".jpg"
    return r.content, ext


def fetch_album_artwork(
    artist: str,
    album: str,
    session: requests.Session,
    *,
    verbose: bool = False,
) -> Optional[tuple[bytes, str]]:
    """Album-level lookup. Queries iTunes Search with `entity=album` so
    the result is the actual album cover (better than per-track stills).
    Scores all candidates and picks the highest scorer above threshold —
    "first acceptable" was the source of mass mismatches. Returns
    (bytes, ext) or None on miss / error / no plausible match."""
    if not artist or not album:
        return None
    term = f"{artist} {album}".strip()
    params = {"term": term, "entity": "album", "limit": 10, "media": "music"}
    try:
        r = session.get(ITUNES_SEARCH, params=params, timeout=(3, 8))
        r.raise_for_status()
        body = r.json()
    except Exception as e:
        print(f"  warn: iTunes album search failed for {term!r}: {e}",
              file=sys.stderr)
        return None
    results = body.get("results") or []
    if not results:
        return None

    best: Optional[tuple[float, dict, float, float]] = None
    for cand in results:
        ok, ar_s, al_s = _is_good_match(
            artist, album,
            cand.get("artistName") or "",
            cand.get("collectionName") or "",
        )
        if not ok:
            continue
        score = _combined_score(ar_s, al_s)
        if best is None or score > best[0]:
            best = (score, cand, ar_s, al_s)
    if best is None:
        if verbose and results:
            top = results[0]
            print(f"      ✗ rejected all {len(results)} album hits; top "
                  f"was {top.get('artistName')!r} – "
                  f"{top.get('collectionName')!r}")
        return None
    chosen = best[1]
    if verbose:
        print(f"      → matched album {chosen.get('artistName')!r} – "
              f"{chosen.get('collectionName')!r} "
              f"(score={best[0]:.2f}, artist={best[2]:.2f}, "
              f"album={best[3]:.2f})")

    art_url = chosen.get("artworkUrl100")
    if not art_url:
        return None
    art_url = re.sub(r"/\d+x\d+bb", "/600x600bb", art_url)
    try:
        r = session.get(art_url, timeout=15)
        r.raise_for_status()
    except Exception as e:
        print(f"  warn: artwork download failed: {e}", file=sys.stderr)
        return None
    ct = r.headers.get("Content-Type", "image/jpeg").lower()
    if "png" in ct:
        ext = ".png"
    elif "webp" in ct:
        ext = ".webp"
    else:
        ext = ".jpg"
    return r.content, ext


def discover_album(
    artist: str,
    title: str,
    session: requests.Session,
    *,
    verbose: bool = False,
) -> Optional[str]:
    """Look up the album a song belongs to via iTunes Search. Used to
    populate the album field on sidecars that are missing it, so the
    album-grouped artwork pass can find them. Strongly prefers
    `collectionType == "Album"` results over Single/EP — the user's
    pain point was that singles and albums share titles but use
    different cover art, and we want the album's cover."""
    if not artist or not title:
        return None
    term = f"{artist} {title}".strip()
    params = {"term": term, "entity": "song", "limit": 10, "media": "music"}
    try:
        r = session.get(ITUNES_SEARCH, params=params, timeout=(3, 8))
        r.raise_for_status()
        body = r.json()
    except Exception:
        return None
    results = body.get("results") or []
    if not results:
        return None

    # Score each plausible track match, pick the album candidate first.
    best: Optional[tuple[float, dict]] = None
    for cand in results:
        ok, ar_s, ti_s = _is_good_match(
            artist, title,
            cand.get("artistName") or "",
            cand.get("trackName") or "",
        )
        if not ok:
            continue
        coll_name = cand.get("collectionName")
        if not coll_name:
            continue
        score = _combined_score(ar_s, ti_s)
        # Heavy bias toward Album-type collections — entire reason this
        # function exists. A Single hit at score 0.85 should lose to an
        # Album hit at score 0.75.
        coll_type = (cand.get("collectionType") or "").lower()
        if coll_type == "album":
            score += 0.30
        elif coll_type == "single":
            score -= 0.20
        elif coll_type == "ep":
            score -= 0.05
        if best is None or score > best[0]:
            best = (score, cand)

    if best is None:
        return None
    chosen = best[1]
    album = chosen.get("collectionName")
    if verbose and album:
        print(f"    discovered album: {album!r} "
              f"({chosen.get('collectionType')})")
    return album


def repair_artwork_by_album(
    sidecars: list,
    *,
    session: requests.Session,
    dry_run: bool,
    verbose: bool,
    force: bool,
    rate_limit: float,
) -> int:
    """Album-grouped artwork pass. Groups sidecars by `(artist, album)`,
    issues *one* iTunes album lookup per group, writes the resulting cover
    to every song in the group. Songs whose sidecar has no album fall back
    to per-song lookup. Far cheaper and more accurate than per-song art
    retrieval, especially when MP3 files have wrong/generic covers
    embedded — every song in the same album ends up with the same correct
    cover after this pass.

    Returns the count of songs whose artwork was written."""
    by_album: dict[tuple[str, str], list[tuple[Path, dict]]] = {}
    no_album: list[tuple[Path, dict]] = []
    # Group key is `(primary_artist, album)` rather than `(artist, album)`.
    # Songs on the same album with different feature credits ("Drake" vs
    # "Drake, 21 Savage") would otherwise become separate groups and each
    # do its own iTunes lookup, giving inconsistent covers across the
    # album. Primary-artist grouping puts all of an album's songs in one
    # bucket regardless of features.
    primary_re = re.compile(r"\s*(?:,|&|\bfeat\.?\b|\bft\.?\b|\bx\b)\s*",
                             re.IGNORECASE)
    for sc in sidecars:
        try:
            data = json.loads(sc.read_text(encoding="utf-8"))
        except Exception:
            continue
        # Honour `coverManual: true` — sidecars that opt out of automated
        # artwork because the user dropped in a hand-picked cover. Even
        # `--retry-artwork` doesn't override; the user has to clear the
        # flag manually if they want to re-fetch from iTunes.
        if data.get("coverManual"):
            if verbose:
                print(f"  skipping {sc.stem} — coverManual=true")
            continue
        # Skip songs that already have artwork unless --retry-artwork.
        if has_artwork(sc.stem) and not force:
            continue
        artist = (data.get("artist") or "").strip()
        album = (data.get("album") or "").strip()
        # Album discovery: if the sidecar has an artist but no album,
        # ask iTunes which album the song lives on (preferring Album
        # over Single/EP) and write the result back. Lets these songs
        # join their album group instead of falling into the per-song
        # path, which is what was giving Travis/Weeknd singles the
        # wrong cover.
        if artist and not album:
            title = (data.get("title") or "").strip()
            discovered = discover_album(artist, title, session,
                                        verbose=verbose)
            time.sleep(rate_limit)
            if discovered:
                album = discovered
                data["album"] = album
                if not dry_run:
                    sc.write_text(
                        json.dumps(data, indent=2, ensure_ascii=False) + "\n",
                        encoding="utf-8",
                    )
        if artist and album:
            primary = primary_re.split(artist, maxsplit=1)[0].strip() or artist
            key = (primary.lower(), album.lower())
            by_album.setdefault(key, []).append((sc, data))
        else:
            no_album.append((sc, data))

    written = 0
    for (primary_lc, al_lc), group in by_album.items():
        # Always query iTunes with the *primary* artist (no feature credits)
        # since iTunes album records only credit the album's primary artist
        # — querying "Playboi Carti, Lil Uzi Vert MUSIC" returns no match
        # while "Playboi Carti MUSIC" finds the album.
        primary = primary_re.split(
            group[0][1].get("artist") or "", maxsplit=1,
        )[0].strip() or (group[0][1].get("artist") or "")
        album = group[0][1].get("album") or ""
        if verbose:
            print(f"  album: {primary!r} / {album!r} ({len(group)} song(s))")
        res = fetch_album_artwork(primary, album, session, verbose=verbose)
        time.sleep(rate_limit)
        if res is None:
            # Album lookup missed (album not on iTunes, fuzzy reject, etc.).
            # Don't skip — fall back to per-song iTunes lookup for each song
            # in the group. They'll get track-specific covers; some may
            # still be wrong but it's better than keeping the bogus
            # embedded-tag artwork from the source MP3s.
            if verbose:
                print(f"    no album match — falling back to per-song "
                      f"({len(group)} song(s))")
            for sc, _ in group:
                if repair_artwork(sc, session=session, dry_run=dry_run,
                                  verbose=verbose, force=force):
                    written += 1
                time.sleep(rate_limit)
            continue
        bytes_, ext = res
        for sc, _ in group:
            song_id = sc.stem
            # Wipe any prior file in any supported ext so we don't leave
            # `<id>.jpg` and `<id>.png` both on disk after replacement.
            for old_ext in SUPPORTED_ART_EXTS:
                old = ARTWORK_DIR / f"{song_id}{old_ext}"
                if old.exists() and not dry_run:
                    try:
                        old.unlink()
                    except Exception:
                        pass
            target = ARTWORK_DIR / f"{song_id}{ext}"
            if not dry_run:
                target.write_bytes(bytes_)
            written += 1
        if verbose:
            verb = "would write" if dry_run else "wrote"
            print(f"    → {verb} cover to {len(group)} song(s) "
                  f"({len(bytes_) // 1024}KB each)")

    # Fallback: songs without an album field — one per-song iTunes call each.
    for sc, _ in no_album:
        if repair_artwork(sc, session=session, dry_run=dry_run,
                          verbose=verbose, force=force):
            written += 1
        time.sleep(rate_limit)

    return written


def repair_artwork(
    sidecar: Path,
    *,
    session: requests.Session,
    dry_run: bool,
    verbose: bool,
    force: bool = False,
) -> bool:
    try:
        data = json.loads(sidecar.read_text(encoding="utf-8"))
    except Exception:
        return False
    song_id = sidecar.stem
    already = has_artwork(song_id)
    if already and not force:
        return False
    artist = (data.get("artist") or "").strip()
    title = (data.get("title") or sidecar.stem).strip()
    album_hint = (data.get("album") or "").strip()
    res = fetch_artwork(
        artist, title, session,
        album_hint=album_hint, verbose=verbose,
    )
    if res is None:
        if verbose:
            kind = "no plausible iTunes match" if already else "no hit"
            print(f"  artwork: {kind} for {song_id} "
                  f"({artist or '?'} - {title})")
        return False
    # Replacing existing → wipe whatever's there (handle ext changes).
    if already:
        for old_ext in SUPPORTED_ART_EXTS:
            old = ARTWORK_DIR / f"{song_id}{old_ext}"
            if old.exists() and not dry_run:
                try:
                    old.unlink()
                except Exception:
                    pass
    bytes_, ext = res
    target = ARTWORK_DIR / f"{song_id}{ext}"
    if dry_run:
        if verbose:
            print(f"  artwork (dry): would write {target.name} "
                  f"({len(bytes_) // 1024}KB)")
        return True
    target.write_bytes(bytes_)
    if verbose:
        verb = "replaced" if already else "added"
        print(f"  artwork {verb}: {target.name} ({len(bytes_) // 1024}KB)")
    return True


# --- lyrics via LRCLib ------------------------------------------------------

# LRC timestamp pattern: `[mm:ss.xx]` or `[mm:ss.xxx]` or `[mm:ss]` at line
# start. Used to distinguish a real time-synced LRC from a plain-text dump
# that just happens to live in a .lrc file (which is what most YouTube
# downloaders produce).
_LRC_TIMESTAMP_RE = re.compile(
    r"^\s*\[\d{1,3}:\d{1,2}(?:[.:]\d{1,3})?\]",
    re.MULTILINE,
)


def is_synced_lrc(path: Path) -> bool:
    """Returns True if the file already contains time-synced lyric lines.
    A handful of timestamps is enough — we don't need the whole file to
    be timestamped, just enough to drive the in-app scrolling view."""
    try:
        content = path.read_text(encoding="utf-8", errors="replace")
    except Exception:
        return False
    return len(_LRC_TIMESTAMP_RE.findall(content)) >= 2


def has_synced_lyrics(song_id: str) -> bool:
    """True only if the song has an .lrc file with real timestamps. Plain-
    text .lrc files (un-synced lyrics from a YouTube downloader, etc.) are
    treated as missing so this pass tries to upgrade them."""
    p = LYRICS_DIR / f"{song_id}.lrc"
    return p.exists() and is_synced_lrc(p)


_LRCLIB_SEARCH = "https://lrclib.net/api/search"


def _lyric_query_variants(
    artist: str,
    title: str,
    album: str,
    duration_s: Optional[int],
) -> list[dict]:
    """Builds progressively-relaxed `(artist, title)` query candidates so
    LRCLib has multiple shots at matching even when the source metadata is
    a little off.
    Variant order, most-strict first:
      1. as-is
      2. title with `(...)` and `[...]` stripped (drops "(feat. X)",
         "[Official Visualizer]", etc.)
      3. above + artist split on `,` / `&` / `feat` / `ft` (use first only)
      4. above + dollar-sign normalized: `Ca$ino` → `Casino`, `$ex` → `sex`
    """
    out: list[dict] = []
    base = {}
    if album:
        base["album_name"] = album
    if duration_s:
        base["duration"] = duration_s

    def push(a: str, t: str):
        a, t = a.strip(), t.strip()
        if not a or not t:
            return
        cand = {"artist_name": a, "track_name": t, **base}
        if cand not in out:
            out.append(cand)

    # 1: as-is
    push(artist, title)

    # 2: cleaned title (parens + brackets stripped)
    clean_title = re.sub(r"\s*\([^)]*\)\s*", " ", title)
    clean_title = re.sub(r"\s*\[[^\]]*\]\s*", " ", clean_title)
    clean_title = re.sub(r"\s+", " ", clean_title).strip()
    if clean_title and clean_title != title:
        push(artist, clean_title)
    else:
        clean_title = title  # use original below

    # 3: first artist (split on comma / & / feat / ft)
    primary = re.split(
        r"\s*(?:,|&|\bfeat\.?\b|\bft\.?\b)\s*",
        artist,
        maxsplit=1,
        flags=re.IGNORECASE,
    )[0].strip()
    if primary and primary != artist:
        push(primary, clean_title)

    # 4: dollar-sign substitution (handles Ca$ino, $ex Appeal, A$AP)
    if "$" in artist or "$" in title:
        # `$ex` → `sex`, `Ca$ino` → `Casino`, `A$AP` → `ASAP`
        sub_title = re.sub(r"\$", "s",
                           clean_title.lower()).title() if "$" in clean_title \
            else clean_title
        sub_artist = (primary or artist).replace("$", "S") \
            if "$" in (primary or artist) else (primary or artist)
        push(sub_artist, sub_title)

    return out


def _lrclib_get_synced(
    params: dict, session: requests.Session,
) -> Optional[str]:
    """Single /api/get call → returns syncedLyrics or None."""
    try:
        r = session.get(LRCLIB_GET, params=params, timeout=10)
        if r.status_code == 404:
            return None
        r.raise_for_status()
        body = r.json()
    except Exception:
        return None
    if body.get("instrumental"):
        return None
    synced = body.get("syncedLyrics")
    return synced if synced and synced.strip() else None


def _censor_score(text: str) -> int:
    """Count `*` characters used as profanity asterisks. Higher = more
    censored. Used to bias LRCLib selection toward uncensored uploads."""
    if not text:
        return 0
    return text.count("*")


# Any `*` at all triggers a re-fetch attempt — single-word redactions
# (one `****` per file = 4 stars total) are exactly the case we want to
# fix. The downside risk is bounded: `repair_lyrics` only overwrites if
# the new fetch is strictly *less* censored than what's already on disk.
_HEAVY_CENSOR_THRESHOLD = 0


def is_heavily_censored_lrc(path: Path) -> bool:
    """True if the on-disk .lrc has any `*` chars beyond the threshold —
    a signal it's a bowdlerized LRCLib upload and a re-fetch should look
    for a better one."""
    try:
        return _censor_score(path.read_text(encoding="utf-8")) > _HEAVY_CENSOR_THRESHOLD
    except Exception:
        return False


def _lrclib_search_synced(
    artist: str, title: str, session: requests.Session,
) -> Optional[str]:
    """Fallback: LRCLib /api/search returns multiple matches; pick the one
    whose trackName best resembles ours, prefers UNCENSORED uploads, and
    has syncedLyrics. Tie-broken by fuzzy artist/title match."""
    from difflib import SequenceMatcher

    try:
        r = session.get(
            _LRCLIB_SEARCH,
            params={"artist_name": artist, "track_name": title},
            timeout=10,
        )
        r.raise_for_status()
        results = r.json() or []
    except Exception:
        return None

    candidates = [
        x for x in results
        if x.get("syncedLyrics")
        and x["syncedLyrics"].strip()
        and not x.get("instrumental")
    ]
    if not candidates:
        return None

    norm_title = _normalize_for_match(title)
    norm_artist = _normalize_for_match(artist)

    def fuzzy(r: dict) -> tuple[float, float]:
        t_score = SequenceMatcher(
            None, norm_title,
            _normalize_for_match(r.get("trackName") or ""),
        ).ratio()
        a_score = SequenceMatcher(
            None, norm_artist,
            _normalize_for_match(r.get("artistName") or ""),
        ).ratio()
        if norm_artist in _normalize_for_match(r.get("artistName") or "") \
                or _normalize_for_match(r.get("artistName") or "") in norm_artist:
            a_score = max(a_score, 0.9)
        return (a_score, t_score)

    def rank_key(r: dict) -> tuple:
        a_score, t_score = fuzzy(r)
        # Filter first to plausible matches so we don't accept a wildly
        # different but uncensored track.
        plausible = a_score >= 0.6 and t_score >= 0.6
        # Sort: plausible first, then uncensored first (negate so smaller
        # asterisk count ranks higher), then better fuzzy match.
        return (
            1 if plausible else 0,
            -_censor_score(r["syncedLyrics"]),
            a_score + t_score,
        )

    candidates.sort(key=rank_key, reverse=True)
    best = candidates[0]
    a_score, t_score = fuzzy(best)
    if a_score >= 0.6 and t_score >= 0.6:
        return best["syncedLyrics"]
    return None


def fetch_synced_lyrics(
    artist: str,
    title: str,
    album: str,
    duration_s: Optional[int],
    session: requests.Session,
) -> Optional[str]:
    """Tries `/api/get` with several relaxed query variants, then `/api/search`
    with fuzzy + uncensored-preferring ranking. If `/api/get` returns a
    heavily-censored upload, we ALSO query `/api/search` and keep whichever
    of the two is least censored — LRCLib's exact-match endpoint sometimes
    returns the bowdlerized version when the database has both."""
    if not artist or not title:
        return None

    primary_artist = re.split(
        r"\s*(?:,|&|\bfeat\.?\b|\bft\.?\b)\s*",
        artist, maxsplit=1, flags=re.IGNORECASE,
    )[0].strip() or artist
    clean_title = re.sub(r"\s*\([^)]*\)\s*", " ", title)
    clean_title = re.sub(r"\s*\[[^\]]*\]\s*", " ", clean_title)
    clean_title = re.sub(r"\s+", " ", clean_title).strip() or title

    get_hit: Optional[str] = None
    for params in _lyric_query_variants(artist, title, album, duration_s):
        synced = _lrclib_get_synced(params, session)
        if synced:
            get_hit = synced
            break

    # If /api/get gave us a clean result, ship it without burning a
    # second request.
    if get_hit is not None and _censor_score(get_hit) <= _HEAVY_CENSOR_THRESHOLD:
        return get_hit

    # Either /api/get found nothing, or what it found is heavily censored.
    # Try /api/search and pick whichever option is least censored.
    search_hit = _lrclib_search_synced(primary_artist, clean_title, session)

    candidates = [c for c in (get_hit, search_hit) if c]
    if not candidates:
        return None
    candidates.sort(key=_censor_score)
    return candidates[0]


def repair_lyrics(
    sidecar: Path,
    *,
    session: requests.Session,
    dry_run: bool,
    verbose: bool,
) -> bool:
    try:
        data = json.loads(sidecar.read_text(encoding="utf-8"))
    except Exception:
        return False
    song_id = sidecar.stem
    target = LYRICS_DIR / f"{song_id}.lrc"

    # Three states:
    #   1. We already have synced lyrics AND they're not heavily censored
    #      -> nothing to do, skip.
    #   2. We have synced lyrics but they're heavily censored
    #      -> try to find a less-censored upload on LRCLib. Keep the
    #         existing file if the re-fetch is no better.
    #   3. We have un-synced or no .lrc at all
    #      -> standard upgrade path (was the only path before).
    has_synced = has_synced_lyrics(song_id)
    censored = has_synced and is_heavily_censored_lrc(target)
    if has_synced and not censored:
        return False

    upgrading = target.exists()
    artist = (data.get("artist") or "").strip()
    title = (data.get("title") or "").strip()
    album = (data.get("album") or "").strip()
    duration_ms = data.get("durationMs")
    duration_s = (
        int(duration_ms / 1000)
        if isinstance(duration_ms, (int, float))
        else None
    )
    synced = fetch_synced_lyrics(artist, title, album, duration_s, session)
    if synced is None:
        if verbose:
            kind = ("uncensored upgrade" if censored
                    else ("upgrade" if upgrading else "no synced match"))
            print(f"  lyrics: {kind} unavailable for {song_id} "
                  f"({artist or '?'} - {title})")
        return False

    # If we're trying to dethrone a censored upload, only overwrite when
    # the new fetch is actually less censored — otherwise we'd just replace
    # one bowdlerized version with another (or worse).
    if censored:
        existing_score = _censor_score(target.read_text(encoding="utf-8"))
        new_score = _censor_score(synced)
        if new_score >= existing_score:
            if verbose:
                print(f"  lyrics: no less-censored match for {song_id} "
                      f"(existing={existing_score}*, found={new_score}*)")
            return False

    if dry_run:
        if verbose:
            tag = "uncensor" if censored else ("upgrade" if upgrading else "add")
            print(f"  lyrics (dry, {tag}): would write {target.name} "
                  f"({len(synced)}B, *={_censor_score(synced)})")
        return True
    target.write_text(synced, encoding="utf-8")
    if verbose:
        verb = ("uncensored" if censored
                else ("upgraded" if upgrading else "added"))
        print(f"  lyrics {verb}: {target.name} ({len(synced)}B, "
              f"*={_censor_score(synced)})")
    return True


# --- artist profile pictures (Deezer) ---------------------------------------

DEEZER_ARTIST_SEARCH = "https://api.deezer.com/search/artist"


def normalize_artist_id(name: str) -> str:
    """Same normalization the Flutter app applies, so the server-side
    filename `<id>.<ext>` lines up with what the app derives from the
    artist string in song metadata. Lowercased ASCII alnum + underscores."""
    safe = re.sub(r"[^a-zA-Z0-9]+", "_", name).strip("_").lower()
    return safe or "unknown"


def _split_multi_artist(field: str) -> list[str]:
    """A song's `artist` field can carry collabs ("Drake, 21 Savage", "X &
    Y", "X feat. Y"). Split into individual names so each gets its own
    profile pic lookup."""
    if not field:
        return []
    parts = re.split(
        r"\s*(?:,|&|\bfeat\.?\b|\bft\.?\b)\s*",
        field, flags=re.IGNORECASE,
    )
    return [p.strip() for p in parts if p.strip()]


def fetch_artist_image(
    name: str,
    session: requests.Session,
    *,
    verbose: bool = False,
) -> Optional[tuple[bytes, str]]:
    """Queries Deezer's free artist search and returns `(bytes, ext)` or
    None. Picks the result whose name best matches; rejects weak matches
    so we don't, say, grab a different "Drake" artist's picture."""
    from difflib import SequenceMatcher

    try:
        r = session.get(
            DEEZER_ARTIST_SEARCH,
            params={"q": name, "limit": 5},
            timeout=(3, 5),  # (connect, read)
        )
        r.raise_for_status()
        results = r.json().get("data") or []
    except Exception as e:
        print(f"  warn: Deezer search failed for {name!r}: {e}",
              file=sys.stderr)
        return None
    if not results:
        return None

    norm_q = _normalize_for_match(name)
    scored = []
    for cand in results:
        norm_n = _normalize_for_match(cand.get("name") or "")
        if not norm_n:
            continue
        ratio = SequenceMatcher(None, norm_q, norm_n).ratio()
        # Substring containment counts as a strong match
        if norm_q in norm_n or norm_n in norm_q:
            ratio = max(ratio, 0.92)
        scored.append((ratio, cand))
    scored.sort(key=lambda t: t[0], reverse=True)
    if not scored or scored[0][0] < 0.7:
        if verbose and scored:
            top = scored[0][1]
            print(f"      ✗ rejected top hit "
                  f"{top.get('name')!r} (score={scored[0][0]:.2f})")
        return None

    chosen = scored[0][1]
    img_url = (chosen.get("picture_xl")
               or chosen.get("picture_big")
               or chosen.get("picture_medium")
               or chosen.get("picture"))
    if not img_url:
        return None
    if verbose:
        print(f"      → matched {chosen.get('name')!r} "
              f"(score={scored[0][0]:.2f})")
    try:
        r = session.get(img_url, timeout=(3, 8))  # (connect, read)
        r.raise_for_status()
    except Exception as e:
        print(f"  warn: artist image download failed for {name!r}: {e}",
              file=sys.stderr, flush=True)
        return None
    ct = r.headers.get("Content-Type", "image/jpeg").lower()
    if "png" in ct:
        ext = ".png"
    elif "webp" in ct:
        ext = ".webp"
    else:
        ext = ".jpg"
    return r.content, ext


def has_artist_image(artist_id: str) -> bool:
    return any((ARTISTS_DIR / f"{artist_id}{ext}").exists()
               for ext in SUPPORTED_ART_EXTS)


def collect_unique_artists() -> dict[str, str]:
    """Walks every sidecar and returns `{normalized_id: original_name}`.
    First-seen name wins for the canonical display string."""
    out: dict[str, str] = {}
    for sidecar in SONGS_DIR.glob("*.json"):
        try:
            data = json.loads(sidecar.read_text(encoding="utf-8"))
        except Exception:
            continue
        for piece in _split_multi_artist(data.get("artist") or ""):
            aid = normalize_artist_id(piece)
            out.setdefault(aid, piece)
    return out


def repair_artists(
    *,
    session: requests.Session,
    dry_run: bool,
    verbose: bool,
    rate_limit: float = 1.0,
) -> int:
    """Fills `content/artists/<id>.<ext>` for every artist that doesn't
    already have one. Returns the number of new images written. Sleeps
    `rate_limit` seconds between Deezer calls to be polite."""
    ARTISTS_DIR.mkdir(parents=True, exist_ok=True)
    seen = collect_unique_artists()
    pending = [
        (aid, name) for aid, name in sorted(seen.items(), key=lambda kv: kv[1].lower())
        if not has_artist_image(aid)
    ]
    print(f"  artists: {len(seen)} unique, {len(pending)} missing image(s)",
          flush=True)

    added = 0
    consecutive_failures = 0
    for i, (aid, name) in enumerate(pending, start=1):
        # Always print which artist we're about to hit so a hang is
        # visible (you can see the line printed and no progress after it).
        print(f"  [{i}/{len(pending)}] {name!r}...", flush=True)
        try:
            res = fetch_artist_image(name, session, verbose=verbose)
        except Exception as e:
            print(f"  warn: unexpected error on {name!r}: {e}",
                  file=sys.stderr, flush=True)
            res = None
        time.sleep(rate_limit)
        if res is None:
            consecutive_failures += 1
            # Circuit-breaker: if Deezer or its CDN is consistently failing
            # (network down, rate-limited, blocked), don't grind through
            # 700 artists silently. Bail after 8 in a row.
            if consecutive_failures >= 8:
                print(
                    f"  artists: 8 consecutive failures — aborting the "
                    f"artist-image pass. Re-run with `--only=artwork,lyrics` "
                    f"to skip and try artists later.",
                    file=sys.stderr,
                    flush=True,
                )
                break
            continue
        consecutive_failures = 0
        bytes_, ext = res
        target = ARTISTS_DIR / f"{aid}{ext}"
        if dry_run:
            print(f"      (dry) would write {target.name} "
                  f"({len(bytes_) // 1024}KB)", flush=True)
            added += 1
            continue
        target.write_bytes(bytes_)
        print(f"      ok {target.name} ({len(bytes_) // 1024}KB)", flush=True)
        added += 1
    return added


# --- manifest regeneration --------------------------------------------------

def stable_id(stem: str) -> str:
    safe = re.sub(r"[^a-zA-Z0-9_-]+", "_", stem).strip("_").lower()
    safe = re.sub(r"_+", "_", safe)
    return f"imp_{safe or 'song'}"


def regenerate_manifest(base_url: Optional[str]) -> None:
    base = (base_url or "__BASE_URL__").rstrip("/")
    songs = []
    for audio in sorted(SONGS_DIR.iterdir()):
        if audio.suffix.lower() not in SUPPORTED_AUDIO_EXTS:
            continue
        stem = audio.stem
        sidecar = SONGS_DIR / f"{stem}.json"
        overrides = {}
        if sidecar.exists():
            try:
                overrides = json.loads(sidecar.read_text(encoding="utf-8"))
            except Exception:
                pass
        entry = {
            "id": overrides.get("id") or stable_id(stem),
            "title": overrides.get("title") or stem.replace("_", " "),
            "artist": overrides.get("artist"),
            "album": overrides.get("album"),
            "genre": overrides.get("genre"),
            "mood": overrides.get("mood"),
            "bpm": overrides.get("bpm"),
            "durationMs": overrides.get("durationMs"),
            "fileName": audio.name,
            "audioUrl": f"{base}/songs/{audio.name}",
        }
        entry = {k: v for k, v in entry.items() if v is not None}
        lrc = LYRICS_DIR / f"{stem}.lrc"
        if lrc.exists():
            entry["lyricsUrl"] = f"{base}/lyrics/{lrc.name}"
        for art_ext in SUPPORTED_ART_EXTS:
            art = ARTWORK_DIR / f"{stem}{art_ext}"
            if art.exists():
                entry["artworkUrl"] = f"{base}/artwork/{art.name}"
                break
        songs.append(entry)

    # Artists block — every image file in content/artists/ becomes a row.
    # The id is the filename stem (already normalized); the name comes from
    # the first sidecar that mentioned this artist so the app shows the
    # original casing / punctuation. Falls back to the id if no sidecar
    # references this artist (orphan image).
    artist_names = collect_unique_artists() if SONGS_DIR.is_dir() else {}
    artists = []
    if ARTISTS_DIR.is_dir():
        for img in sorted(ARTISTS_DIR.iterdir()):
            if img.suffix.lower() not in SUPPORTED_ART_EXTS:
                continue
            aid = img.stem
            artists.append({
                "id": aid,
                "name": artist_names.get(aid, aid),
                "imageUrl": f"{base}/artists/{img.name}",
            })

    manifest = {"version": 1, "songs": songs, "artists": artists}
    manifest_path = CONTENT_DIR / "manifest.json"
    manifest_path.write_text(
        json.dumps(manifest, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )
    print(f"manifest: wrote {manifest_path} with {len(songs)} song(s), "
          f"{len(artists)} artist(s).")


# --- entry point ------------------------------------------------------------

def find_audio_for(song_id: str) -> Optional[Path]:
    for ext in SUPPORTED_AUDIO_EXTS:
        p = SONGS_DIR / f"{song_id}{ext}"
        if p.exists():
            return p
    return None


def transcribe_to_lrc(audio_path: Path, model_name: str = "small") -> str:
    """Returns LRC-formatted lyrics from a Whisper transcription of
    [audio_path]. Used for songs LRCLib doesn't have (instrumentals,
    leaks, unreleased, very recent drops)."""
    from faster_whisper import WhisperModel
    model = WhisperModel(model_name, device="cpu", compute_type="int8")
    segments, _info = model.transcribe(
        str(audio_path),
        language="en",
        vad_filter=True,
        vad_parameters={"min_silence_duration_ms": 500},
        word_timestamps=False,
        condition_on_previous_text=False,
    )
    lines = []
    for seg in segments:
        text = seg.text.strip()
        if not text:
            continue
        m = int(seg.start) // 60
        s = seg.start - m * 60
        # LRC timestamp format: [mm:ss.cc]
        lines.append(f"[{m:02d}:{s:05.2f}]{text}")
    return "\n".join(lines) + "\n"


def transcribe_missing(
    sidecars: list,
    *,
    dry_run: bool,
    verbose: bool,
    model_name: str = "small",
) -> int:
    """Whisper-transcribes every song still missing an .lrc after the
    LRCLib pass and writes the result to LYRICS_DIR. Returns count of
    files written."""
    pending = [sc for sc in sidecars if not has_synced_lyrics(sc.stem)]
    print(
        f"  transcribe: {len(pending)} song(s) need Whisper lyrics "
        f"(model={model_name})",
        flush=True,
    )
    if not pending:
        return 0
    written = 0
    for i, sc in enumerate(pending, start=1):
        song_id = sc.stem
        audio = find_audio_for(song_id)
        if audio is None:
            print(
                f"  [{i}/{len(pending)}] {song_id}: no audio file found",
                file=sys.stderr,
                flush=True,
            )
            continue
        try:
            data = json.loads(sc.read_text(encoding="utf-8"))
        except Exception:
            data = {}
        title = data.get("title") or song_id
        print(f"  [{i}/{len(pending)}] {title!r}: transcribing...",
              flush=True)
        try:
            lrc = transcribe_to_lrc(audio, model_name=model_name)
        except Exception as e:
            print(f"      ! whisper failed: {e}", file=sys.stderr, flush=True)
            continue
        if not lrc.strip():
            print("      no speech detected (likely instrumental); skipping",
                  flush=True)
            continue
        target = LYRICS_DIR / f"{song_id}.lrc"
        if dry_run:
            print(
                f"      (dry) would write {target.name} "
                f"({len(lrc.splitlines())} lines)",
                flush=True,
            )
            written += 1
            continue
        target.write_text(lrc, encoding="utf-8")
        print(
            f"      wrote {target.name} ({len(lrc.splitlines())} lines)",
            flush=True,
        )
        written += 1
    return written


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument(
        "--only",
        action="append",
        choices=["titles", "artwork", "lyrics", "artists", "transcribe"],
        help="Restrict to one or more passes (can be repeated). Default: "
             "everything except transcribe (which is opt-in because it "
             "loads a Whisper model and runs CPU-heavy inference).",
    )
    parser.add_argument(
        "--whisper-model",
        default="small",
        help="faster-whisper model id for the transcribe pass "
             "(tiny/base/small/medium/large-v3). Default: small.",
    )
    parser.add_argument(
        "--base-url",
        default=None,
        help="Base URL baked into the regenerated manifest. Omit to keep "
             "__BASE_URL__ placeholders (use set_base_url.sh later).",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Report what would change without writing anything.",
    )
    parser.add_argument(
        "--quiet",
        action="store_true",
        help="Less per-song output; just summary.",
    )
    parser.add_argument(
        "--rate-limit",
        type=float,
        default=1.0,
        help="Seconds to wait between LRCLib / iTunes requests "
             "(default 1.0, polite).",
    )
    parser.add_argument(
        "--retry-artwork",
        action="store_true",
        help="Re-query iTunes for every song, even ones that already have "
             "an artwork file. Replaces the local file ONLY when the new "
             "strict-match validator accepts a result. Songs whose iTunes "
             "search fails the validator keep their existing artwork — "
             "delete those files manually if you want them re-fetched "
             "next run.",
    )
    args = parser.parse_args()

    if not SONGS_DIR.is_dir():
        print(f"error: {SONGS_DIR} not found.", file=sys.stderr)
        return 1
    ARTWORK_DIR.mkdir(parents=True, exist_ok=True)
    LYRICS_DIR.mkdir(parents=True, exist_ok=True)

    # Default omits "transcribe" — it's CPU-heavy + downloads a Whisper
    # model on first run, so we make it opt-in with --only=transcribe.
    passes = args.only or ["titles", "artwork", "lyrics", "artists"]
    verbose = not args.quiet

    session = requests.Session()
    session.headers.update({"User-Agent": UA})

    sidecars = sorted(SONGS_DIR.glob("*.json"))
    print(f"Repairing {len(sidecars)} sidecar(s) — passes: {', '.join(passes)}"
          + ("  [dry run]" if args.dry_run else ""))
    counts = {"titles": 0, "artwork": 0, "lyrics": 0, "artists": 0,
              "transcribe": 0, "scanned": len(sidecars)}

    # Titles + lyrics still iterate per sidecar. Artwork now runs as a
    # single grouped pass (album-level iTunes lookup, one per album) after
    # titles so any title/album cleanup feeds correct album names into the
    # search query.
    for sidecar in sidecars:
        if "titles" in passes:
            if repair_titles(sidecar, dry_run=args.dry_run, verbose=verbose):
                counts["titles"] += 1
        # Run repair_lyrics if we don't have synced lyrics OR if the existing
        # synced .lrc is heavily censored — repair_lyrics itself decides
        # whether the new fetch is actually less censored before overwriting.
        if "lyrics" in passes:
            lrc_path = LYRICS_DIR / f"{sidecar.stem}.lrc"
            needs_lyrics = (
                not has_synced_lyrics(sidecar.stem)
                or is_heavily_censored_lrc(lrc_path)
            )
            if needs_lyrics:
                changed = repair_lyrics(
                    sidecar, session=session,
                    dry_run=args.dry_run, verbose=verbose,
                )
                if changed:
                    counts["lyrics"] += 1
                time.sleep(args.rate_limit)

    # Artwork: single grouped pass (one iTunes album lookup per unique
    # album, then write the same cover to every song in that album).
    if "artwork" in passes:
        counts["artwork"] = repair_artwork_by_album(
            sidecars,
            session=session,
            dry_run=args.dry_run,
            verbose=verbose,
            force=args.retry_artwork,
            rate_limit=args.rate_limit,
        )

    # Artists pass operates over unique artists, not sidecars, so it lives
    # outside the per-sidecar loop.
    if "artists" in passes:
        counts["artists"] = repair_artists(
            session=session,
            dry_run=args.dry_run,
            verbose=verbose,
            rate_limit=args.rate_limit,
        )

    # Whisper transcription — fallback for songs LRCLib couldn't help
    # with (instrumentals get skipped by the empty-output check inside
    # transcribe_missing).
    if "transcribe" in passes:
        counts["transcribe"] = transcribe_missing(
            sidecars,
            dry_run=args.dry_run,
            verbose=verbose,
            model_name=args.whisper_model,
        )

    print(
        f"\ndone — titles cleaned: {counts['titles']}, "
        f"artwork added: {counts['artwork']}, "
        f"lyrics added: {counts['lyrics']}, "
        f"transcribed: {counts['transcribe']}, "
        f"artists added: {counts['artists']} "
        f"(of {counts['scanned']} sidecars scanned)"
    )

    if not args.dry_run:
        regenerate_manifest(args.base_url)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
