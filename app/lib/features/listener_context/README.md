# Listener Context Engine

A personalization layer **above** the recommender and the AutoMix engine. It
reads who's listening and how, then outputs one snapshot that drives queue
ordering, recommendations and AutoMix transitions.

```
 history (UserListeningProfile)  ─┐
 AutoMix sidecars → TrackFeatures ─┤
 live SessionEvents ──────────────┤→ ListenerContextEngine.evaluate() → ListenerContext
 candidate songs ─────────────────┤
 location hint (optional) ────────┘
```

Pure + deterministic (no I/O); the service layer loads inputs and the engine
is cheap to re-run every time the queue changes.

## Pipeline (`engine/`)

| Engine | Output |
|---|---|
| `ProfileBuilder` | durable `ListenerProfile` — taste/mood/energy vectors, preferred BPM/energy/loudness ranges, exploration score+tolerance, preferred transition style, session length |
| `SessionAnalyzer` | `SessionState` (engaged/passive/exploring/focused/relaxed/workout/driving/studying/sleeping) + 0–100 confidence, via per-state scoring |
| `MoodDetector` | `Mood` distribution + confidence from track energy/valence × baseline × time × state |
| `TimeContextEngine` | TimeOfDay bucket + energy/valence/smoothness biases (morning uplift, night low+smooth) |
| `EnergyManager` | session energy curve + next-track target energy, capped at ±0.18/step (no spikes/crashes) |
| `FatigueDetector` | 0–1 fatigue from skip rate/accel, searching, queue churn, short skips → remedies |
| `DiscoveryEngine` | discovery score + exploration target, **never exceeding tolerance** |
| `QueueOptimizer` | re-rank: `0.35·Taste + 0.20·Mood + 0.15·Energy + 0.10·Time + 0.10·Discovery + 0.10·Continuity` |
| `AutoMixBridge` | target energy + transition style→`TransitionType` + duration + mood/fatigue/state |

## Output (`ListenerContext.toJson`)

Exactly the spec shape: `currentMood, moodConfidence, sessionState,
sessionConfidence, fatigueScore, discoveryScore, targetEnergy,
recommendedTransitionType, recommendedTransitionDuration, nextTrackCandidates,
queueRanking, listenerProfile`.

## Using it

```dart
final svc = await ref.read(listenerContextServiceProvider.future);
final ctx = await svc.evaluate(
  candidates: candidateSongs,         // pool for the next slot(s)
  recentlyPlayed: sessionSongs,       // play order, last = now playing
  profileSongs: completedSongs,       // optional — widens the taste centroid
  sessionEvents: ref.read(sessionMonitorProvider).recent,
  location: LocationContext.unknown,  // pluggable hint; no GPS today
);
ctx.queueRanking;       // re-ranked candidates
ctx.automix;            // hand to AutoMixService.mixToNext(... type: ctx.automix.transitionStyle.automixType)
```

Feed `sessionMonitorProvider.record(...)` from the player's existing event
hooks (skip/search/volume/queue edits) for live session/fatigue signals.

## Honest limits / learning

- **Location** is a pluggable hint (no GPS); defaults to `unknown` and degrades gracefully.
- **Valence** isn't in the catalog — proxied from key-mode + energy + tempo (`TrackFeatures`).
- **Disliked/hidden** need explicit UI signals the app doesn't persist yet; surfaced as empty, with chronic skips standing in for implicit dislike in scoring.
- **Transition-style learning** currently derives from energy/mood; once AutoMix outcomes are logged per style, `ProfileBuilder._preferredStyle` can learn from them.
- Everything else updates continuously: the profile is rebuilt from persisted stats, so vectors sharpen as history grows.
