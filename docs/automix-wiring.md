# Wiring the AutoMix button (player page)

How to connect the **AutoMix engine** (`features/automix/`) to the **"Automix"
button** that already exists (greyed-out) in the expanded player. The engine,
planner and executor are done + tested; this is pure integration.

> **The good news:** the button placeholder and a pre-emptive transition slot
> already exist. Wiring = giving the button an `onTap`, flipping one branch in
> the playback chokepoint, and getting the analysis sidecars onto the device.
> Three small edits, no new widgets.

---

## How it hooks in (the one mechanic to understand)

Every play/advance funnels through one method:

```dart
// now_playing_controller.dart
Future<void> _playInternal(SongRow song, {Duration crossfade = Duration.zero}) async {
  ...
  await _player.playSong(song, crossfade: crossfade);   // ← the play call
  ...
}
```

Only **one** caller passes `crossfade > 0`: the auto-advance in `_onPosition`,
which fires `_autoMixWindow` (4 s) before the track ends:

```dart
// _onPosition — fires ~4s before end
_queueIndex += 1;
_publishQueue();
_playInternal(_queue[_queueIndex], crossfade: _autoMixWindow);   // pre-emptive crossfade
```

So: **branch inside `_playInternal` on `crossfade > 0`** → auto-advance
transitions run the AutoMix engine, while user skips (`next()`/`previous()`/
`jumpTo()`, all `crossfade: zero`) stay hard cuts. Exactly the intended
behavior, and the bookkeeping (`state`, `announceSong`, `tracker`,
`stampPlayed`) is preserved for free because it all lives in `_playInternal`.

---

## Prerequisite — sidecars on the device

`AutoMixService` reads `*.automix.json` from `analysisDirProvider`
(`<app-support>/automix_analysis/`). The 764 generated sidecars currently live
in the repo's `analysis/` dir. Two ways to make the engine see them:

**Debug / quick test** — override the dir to point at the repo. In
`main.dart`'s `ProviderScope(overrides: [...])`:

```dart
analysisDirProvider.overrideWith((ref) async => '/Users/qeuapp/Downloads/music app/analysis'),
```

**Production** — ship sidecars through the existing song-sync pipeline (the app
already downloads audio + `.lrc`); drop the matching `<slug>.automix.json` into
`<app-support>/automix_analysis/` next to each track. Join key is a slug of the
audio filename (`AnalysisStore.slugify`), so no id plumbing needed.

If a track has no sidecar, `mixToNext` returns `noAnalysis` and the code below
falls back to the existing simple crossfade — so partial coverage is safe.

---

## Step 1 — an enable flag (conflict-free, no edits to your player files)

Add to `features/automix/providers.dart`:

```dart
/// Whether auto-advance transitions use the AutoMix engine (vs the simple
/// linear crossfade). Toggled by the player's Automix button.
final autoMixEnabledProvider = StateProvider<bool>((ref) => false);
```

(StateProvider keeps it independent of `playbackModesProvider`; fold it in there
later if you want it to persist alongside repeat/shuffle/endless.)

---

## Step 2 — light up the button

`ui/widgets/expanding_player.dart`, in `_QueueControlsRow.build` (~line 853).
It's already a `ConsumerWidget` that reads `playbackModesProvider` and
`nowPlayingProvider.notifier`, so add one watch and replace the dead props:

```dart
// add near the other ref.watch calls in _QueueControlsRow.build:
final automixOn = ref.watch(autoMixEnabledProvider);
```

```dart
// the existing placeholder ↓
_QueueControl(
  icon: Icons.auto_awesome_rounded,
  label: 'Automix',
  active: false,                                   // ← was hardcoded
  accent: accent,
  dim: Colors.white.withValues(alpha: 0.25),
  onTap: null,                                     // ← was greyed out
),

// becomes ↓
_QueueControl(
  icon: Icons.auto_awesome_rounded,
  label: 'Automix',
  active: automixOn,
  accent: accent,
  dim: Colors.white.withValues(alpha: 0.25),
  onTap: () =>
      ref.read(autoMixEnabledProvider.notifier).update((v) => !v),
),
```

Don't forget the import:
`import '../../features/automix/providers.dart';`

---

## Step 3 — run the engine on auto-advance

`features/player/now_playing_controller.dart`. The controller already holds
`final Ref _ref;`, so it can read the providers. Patch `_playInternal`:

```dart
Future<void> _playInternal(
  SongRow song, {
  Duration crossfade = Duration.zero,
}) async {
  await _ensureNotificationPermission();
  final outgoing = state;            // capture BEFORE we flip to `song`
  state = song;
  _handler?.announceSong(song);
  await _tracker.onSongChanged(song);
  try {
    // AutoMix only on the pre-emptive crossfade path, only when enabled,
    // and only if there's an outgoing track to mix out of.
    var mixed = false;
    if (crossfade > Duration.zero &&
        outgoing != null &&
        _ref.read(autoMixEnabledProvider)) {
      final svc = await _ref.read(autoMixServiceProvider.future);
      final outcome = await svc.mixToNext(current: outgoing, next: song);
      mixed = outcome == AutoMixOutcome.mixed;
    }
    if (!mixed) {
      // no sidecar / disabled / failed → the original behavior
      await _player.playSong(song, crossfade: crossfade);
    }
  } catch (_) {
    if (hasNext) unawaited(Future.microtask(next));
    return;
  }
  _handler?.announceSong(song);
  await _repo.stampPlayed(song.id);
}
```

Imports:
```dart
import '../automix/automix_service.dart';   // AutoMixOutcome
import '../automix/providers.dart';         // autoMixServiceProvider, autoMixEnabledProvider
```

**Why this is correct:**
- `mixToNext` internally calls `beginAutoMix`, which loads + starts the incoming
  track and flips deck activeness — so when `mixed == true` you must **not** also
  call `_player.playSong` (it would double-load). The `if (!mixed)` guard handles
  that.
- When `outcome != mixed` (`noAnalysis`/`failed`), nothing was started on the
  engine, so the fallback `_player.playSong(song, crossfade)` runs the existing
  simple crossfade — seamless degradation.
- `mixToNext` reads `_player.activePosition` for the outgoing playhead *before*
  `beginAutoMix` flips activeness, so the plan uses the correct cue. No change
  needed.

That's it — toggle Automix on, let a track play to its last few seconds, and the
next one beat-matches in.

---

## Optional polish

**Longer blends.** The 4 s `_autoMixWindow` caps the transition: the planner
clamps its duration to the audio remaining after the mix-out point, so with only
4 s left you get ~4 s blends. For fuller club-style transitions, fire earlier —
bump the window where it's computed in `_onDuration`:

```dart
static const Duration _autoMixWindow = Duration(seconds: 10); // was 4
```

**Let the Listener Context pick the style.** Instead of letting AutoMix choose
(`aiSelected`), drive the transition type from who's listening:

```dart
final lc = await _ref.read(listenerContextServiceProvider.future);
final ctx = await lc.evaluate(
  candidates: [song],
  recentlyPlayed: [if (outgoing != null) outgoing],
  sessionEvents: _ref.read(sessionMonitorProvider).recent,
);
final outcome = await svc.mixToNext(
  current: outgoing, next: song,
  type: ctx.automix.transitionStyle.automixType,   // context-aware style
);
```

**Feed the SessionMonitor.** For live mood/fatigue signals, call
`_ref.read(sessionMonitorProvider).record(...)` from the same spots that already
notify `_tracker` (song change, skip, pause) and from the UI for
search/volume/queue edits.

---

## Gotchas

- **Two decks only.** One AutoMix occupies both deck slots for its duration. A
  second transition can't start until the first commits — but the controller
  already serializes via `_autoMixFired` / `_autoAdvancing`, so you're covered.
- **`activePosition` flips.** After `beginAutoMix`, position/duration streams and
  `activePosition` reflect the **incoming** track (intended — the scrubber
  follows the new song). To read the outgoing playhead mid-mix, the executor uses
  `AutoMixDecks.outgoingHandle` directly; you don't need to.
- **Manual skips stay hard cuts** — they call `_playInternal` with
  `crossfade: zero`, which the `crossfade > Duration.zero` guard excludes. If you
  *want* skips to mix too, drop that part of the condition.
- **`beginAutoMix` throws if the incoming file is missing** — already inside the
  `try` here, so a bad file falls through to the `catch` → skip.
- **DJ-queue mode** funnels through `_playInternal` too, so it's covered. If the
  AI-DJ ever advances via its own path, apply the same `mixToNext` call there.

## Files touched
| File | Change |
|---|---|
| `features/automix/providers.dart` | + `autoMixEnabledProvider` |
| `ui/widgets/expanding_player.dart` | button `onTap` + `active` (~line 853) |
| `features/player/now_playing_controller.dart` | `_playInternal` AutoMix branch |
| `main.dart` (debug) | `analysisDirProvider` override to repo `analysis/` |
