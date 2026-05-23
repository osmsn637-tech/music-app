---
status: fixing
trigger: "back-button-exits-app — pressing back exits app instead of navigating to previous screen"
created: 2026-05-23T00:00:00Z
updated: 2026-05-23T00:20:00Z
---

## Current Focus

hypothesis: CONFIRMED — HomeShell uses IndexedStack for tabs (no route per tab). No PopScope existed at the shell level to intercept back and redirect to tab 0. The new ExpandingPlayer architecture (expanded player is an in-shell animation, not a pushed route) also lacked back handling. Together: back on any tab or from the expanded player exits the app.
test: Fix applied — _ShellBackHandler added to home_shell.dart; PopScope removed from expanding_player.dart.
expecting: Back from non-home tabs → Home tab. Back when player expanded → collapse player. Back when on Home tab with mini player → exit (correct).
next_action: Await human verification

## Symptoms

expected: Pressing Android back (or equivalent) should pop the navigation stack to the previous screen.
actual: Pressing back from any page immediately closes/exits the entire app.
errors: None reported. No stack traces.
reproduction: Open app → navigate into any inner page (Now Playing, Lyrics, Playlist Detail, Settings, Sync, AI DJ, Search) → press system back → app exits.
started: Likely introduced by uncommitted edits; most recent commit is "Lag fixes + queue navigation + lyrics/now-playing polish". player_screen.dart and mini_player.dart were deleted.

## Eliminated

(none yet)

## Evidence

- timestamp: 2026-05-23T00:10:00Z
  checked: lib/app.dart
  found: MaterialApp uses `home: const HomeShell()` — single-navigator, no GoRouter, no named routes. All routes pushed via Navigator.of(context).push.
  implication: Navigation stack is imperative; back button pops the top route. HomeShell IS the root route.

- timestamp: 2026-05-23T00:11:00Z
  checked: lib/ui/screens/home_shell.dart (current)
  found: Tabs (Home/AI DJ/Search/Library) use IndexedStack — tab switches do NOT push routes. ExpandingPlayer is a Positioned.fill widget inside the Stack (not a route). PlayerExpansionScope wraps everything.
  implication: Pressing back on any tab exits the app because there are no routes below HomeShell. This is the main regression for tab navigation.

- timestamp: 2026-05-23T00:12:00Z
  checked: lib/ui/widgets/expanding_player.dart lines 329-335
  found: PopScope(canPop: e < 0.05, onPopInvokedWithResult: collapse) inside AnimatedBuilder inside _PlayerMorph. When e=0 (mini), canPop:true. When e>=0.05 (expanded), canPop:false → collapse().
  implication: This correctly handles player collapse on back. But there is NO tab-aware back handling in HomeShell.

- timestamp: 2026-05-23T00:13:00Z
  checked: git diff HEAD -- home_shell.dart (old vs new)
  found: Old home_shell used MiniPlayer widget + separate PlayerScreen route (pushed via openPlayerRoute()). Back from PlayerScreen popped the route. New architecture uses ExpandingPlayer in-shell (no route for the full player). No PopScope was in the old HomeShell either.
  implication: The tab-exit behavior on back existed before the refactor. The regression for pushed routes (Settings, Lyrics, Sync, Playlist Detail) is NOT caused by a code change in the push calls themselves — those are identical. The PopScope in ExpandingPlayer (new code) is the only structural change that could affect route behavior.

- timestamp: 2026-05-23T00:14:00Z
  checked: profile_sheet.dart (old vs new)
  found: Identical in both commits. Navigator.of(context).pop() then Navigator.of(context).push(MaterialPageRoute(...)) — same code worked before.
  implication: The push calls themselves are correct. If Settings/Sync push fails now, it would be because of some interaction with the new PlayerExpansionScope or PopScope.

- timestamp: 2026-05-23T00:15:00Z
  checked: All .dart files for WillPopScope, SystemNavigator, onBackPressed
  found: None. Only one PopScope in the entire codebase — in expanding_player.dart.
  implication: No accidental back-override anywhere else.

- timestamp: 2026-05-23T00:16:00Z
  checked: MainActivity.kt
  found: No custom onBackPressed override. Only requestHighRefreshRate in onCreate.
  implication: Platform-level back handling is unchanged from default.

## Resolution

root_cause:
fix:
verification:
files_changed: []
