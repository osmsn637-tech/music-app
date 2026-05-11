import 'dart:collection';
import 'dart:math' as math;

import '../lyrics/lyrics_hook_extractor.dart';
import 'dj_mode.dart';
import 'dj_speech_types.dart';
import 'recent_dj_lines_service.dart';
import 'user_listening_profile.dart';

/// Generates DJ patter from a [DjSpeechContext]. Two surfaces:
///
///   - [announce] — said by the DJ over TTS before each track plays.
///     Async because it consults [RecentDjLinesService] for cross-session
///     repeat suppression.
///   - [hostBubble] — silent rotating text shown in the host speech
///     bubble on the AI DJ screen while the user browses. Sync.
///
/// All output is template-driven and fully offline. Templates are organized
/// by [DjIntent] (selected upstream by [DjIntentSelector]) and optionally
/// by [QueuePositionType] when the position warrants a different phrasing
/// (e.g., a `studyFocus` line at the opener vs. mid-set).
///
/// Tone rules baked into every phrasing — these are deliberate:
///   - contractions (I'm, let's, it's)
///   - max ~18 words for a normal line, ~30 for an opener
///   - no "based on your data / algorithm / recommendation / score" language
///   - no "as an AI" / "I selected this because"
///   - title and artist mentioned only when the phrasing benefits — many
///     transitions read more natural without the full song reference
class DjCommentary {
  DjCommentary({RecentDjLinesService? recentLines, math.Random? random})
      : _recentLines = recentLines,
        _rng = random ?? math.Random() {
    _trackTemplates = _buildTrackTemplates();
    _hostTemplates = _buildHostTemplates();
  }

  final RecentDjLinesService? _recentLines;
  final math.Random _rng;
  late final List<_Template> _trackTemplates;
  late final List<_HostTemplate> _hostTemplates;

  /// In-memory ring used when no [RecentDjLinesService] is wired in (tests,
  /// host-bubble rotation). Track announcements with a service attached
  /// also use the ring as a same-session boost on top of the DB query.
  final Queue<String> _recentRing = Queue<String>();
  static const int _ringSize = 8;

  /// Whether the previous [announce] picked a lyric-quoting template. Used
  /// by [_shouldQuoteNow] as a cooldown — back-to-back quotes get tuned out
  /// fast, so we force at least one non-quoting transition between them.
  bool _lastAnnouncementUsedLyrics = false;

  /// Picks a phrasing for [ctx]'s intent + position, fills slots, suppresses
  /// repeats against both the in-memory ring and the persistent recent-lines
  /// table, records the chosen line, and returns it. Caller is responsible
  /// for sending the returned text to the TTS layer.
  Future<String> announce(DjSpeechContext ctx) async {
    final intent = ctx.intent ?? DjIntent.nextTrack;
    final position = ctx.queuePosition;

    // Decide once per call whether lyric-quoting templates are eligible.
    // [_shouldQuoteNow] folds in confidence, cooldown, skip-recovery, and
    // a context-aware probability roll so quotes feel earned, not spammy.
    final canQuote = _shouldQuoteNow(ctx);
    bool lyricsOk(_Template t) => !t.requiresLyrics || canQuote;

    // Find templates matching this (intent, position). Prefer ones that
    // match the position exactly; fall back to position-agnostic.
    final exact = _trackTemplates
        .where((t) =>
            t.intent == intent && t.position == position && lyricsOk(t))
        .toList();
    final any = _trackTemplates
        .where((t) =>
            t.intent == intent && t.position == null && lyricsOk(t))
        .toList();
    final candidates = [...exact, ...any];
    if (candidates.isEmpty) {
      // No template for this intent — fall back to nextTrack so the DJ
      // never goes silent when an exotic intent slips through.
      candidates.addAll(_trackTemplates.where(
        (t) =>
            t.intent == DjIntent.nextTrack &&
            t.position == null &&
            lyricsOk(t),
      ));
    }
    if (candidates.isEmpty) {
      _lastAnnouncementUsedLyrics = false;
      return _trackFallback(ctx);
    }

    // Build all (template, phrasing) pairs and fill slots. Keep the
    // template handle alongside the filled text so we can update the
    // lyric-cooldown flag based on what actually got picked.
    final filled = <_FilledLine>[];
    for (final t in candidates) {
      for (final p in t.phrasings) {
        filled.add(_FilledLine(t, _fill(p, ctx)));
      }
    }

    // Suppress repeats: check both the in-memory ring and the DB recent set.
    final dbRecent = await _recentLines?.recentTexts(limit: 30) ??
        const <String>{};
    final ringRecent = _recentRing.toSet();
    final fresh = filled
        .where((e) =>
            !dbRecent.contains(e.text) && !ringRecent.contains(e.text))
        .toList();
    final pool = fresh.isEmpty ? filled : fresh;

    final picked = pool[_rng.nextInt(pool.length)];
    _lastAnnouncementUsedLyrics = picked.template.requiresLyrics;
    _markRecent(picked.text);
    await _recentLines?.record(
      lineText: picked.text,
      intent: intent.id,
      songId: ctx.song.id,
      mode: ctx.mode.id,
    );
    return picked.text;
  }

  /// Smart gate that decides whether the lyric-quoting templates should be
  /// in the candidate pool for this transition. Layers four filters:
  ///
  ///   1. **Confidence floor.** No hook, or only a `weak`/`none` hook, →
  ///      never quote. Quoting half a line that isn't really a hook reads
  ///      flat.
  ///   2. **Cooldown.** If the *previous* announcement quoted lyrics, skip
  ///      this one — back-to-back quotes get tuned out fast and the format
  ///      stops feeling special.
  ///   3. **Skip recovery.** When the user just skipped, they want a fast
  ///      pivot, not a poetic reading. Hard-suppress lyric quoting on the
  ///      transition immediately after a skip.
  ///   4. **Context-weighted probability.** Even when eligible, roll a die.
  ///      Strong hooks land more often than medium ones, and "moments" —
  ///      favorites, discoveries, set opener/closer — bias the dice up so
  ///      a quote shows up where it'll actually land. Mid-set generic
  ///      transitions roll lower so they don't all turn into "Listen for…".
  bool _shouldQuoteNow(DjSpeechContext ctx) {
    if (!ctx.hasLyricHook) return false;
    final c = ctx.hookConfidence;
    if (c == LyricHookConfidence.none || c == LyricHookConfidence.weak) {
      return false;
    }
    if (_lastAnnouncementUsedLyrics) return false;
    if (ctx.cameFromSkip) return false;

    final boosted = ctx.isFavorite ||
        ctx.isDiscovery ||
        ctx.isFirstSong ||
        ctx.isLastSong;
    final double odds;
    if (boosted) {
      odds = c == LyricHookConfidence.strong ? 0.75 : 0.50;
    } else {
      odds = c == LyricHookConfidence.strong ? 0.40 : 0.25;
    }
    return _rng.nextDouble() < odds;
  }

  /// Idle host-bubble rotation — no specific track in play, just a vibe
  /// line for the AI DJ screen's header.
  String hostBubble({
    required DjMode mode,
    required UserListeningProfile profile,
    required DateTime now,
  }) {
    final timeBucket = _timeBucket(now);
    final candidates = _hostTemplates.where((t) {
      if (t.modes != null && !t.modes!.contains(mode)) return false;
      if (t.timeBucket != null && t.timeBucket != timeBucket) return false;
      return true;
    }).toList();
    if (candidates.isEmpty) return 'Tonight\'s set is calibrated to your library.';

    final allPhrasings = <String>[];
    for (final t in candidates) {
      allPhrasings.addAll(t.phrasings);
    }
    final ring = _recentRing.toSet();
    final fresh = allPhrasings.where((s) => !ring.contains(s)).toList();
    final pool = fresh.isEmpty ? allPhrasings : fresh;
    final chosen = pool[_rng.nextInt(pool.length)];
    _markRecent(chosen);
    return chosen;
  }

  // ---- helpers ---------------------------------------------------------

  String _fill(String phrasing, DjSpeechContext ctx) {
    final title = ctx.song.title;
    final artist = ctx.song.artist ?? 'an artist you like';
    final prevTitle = ctx.previousSong?.title ?? '';
    final prevArtist = ctx.previousSong?.artist ?? 'that one';
    // Lyric snippets — shortened so they read naturally inside a sentence.
    // The candidate filter ensures these placeholders only fire when the
    // context actually has lyric data, so empty fallbacks never reach the
    // user. We still substitute the title as a last-resort safety net.
    final firstLine = _shortLine(ctx.firstLyricLine) ?? title;
    final hook = _shortLine(ctx.hookLyricLine) ??
        _shortLine(ctx.firstLyricLine) ??
        title;
    return phrasing
        .replaceAll('{title}', title)
        .replaceAll('{artist}', artist)
        .replaceAll('{prev_title}', prevTitle)
        .replaceAll('{prev_artist}', prevArtist)
        .replaceAll('{mode}', ctx.mode.label.toLowerCase())
        .replaceAll('{first_line}', firstLine)
        .replaceAll('{hook}', hook);
  }

  /// Trims a lyric snippet to ~70 chars on a word boundary so it reads
  /// inside a longer DJ sentence without running long. Returns null when
  /// the input is null or empty so the caller can fall back to the title.
  String? _shortLine(String? raw) {
    if (raw == null) return null;
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    const maxChars = 70;
    if (trimmed.length <= maxChars) return trimmed;
    final cut = trimmed.substring(0, maxChars);
    final lastSpace = cut.lastIndexOf(' ');
    return (lastSpace > maxChars * 0.6 ? cut.substring(0, lastSpace) : cut)
        .trimRight();
  }

  String _trackFallback(DjSpeechContext ctx) {
    final artist = ctx.song.artist ?? 'an artist you like';
    return 'Up next, ${ctx.song.title}, by $artist.';
  }

  void _markRecent(String s) {
    _recentRing.addLast(s);
    while (_recentRing.length > _ringSize) {
      _recentRing.removeFirst();
    }
  }

  String _timeBucket(DateTime now) {
    final h = now.hour;
    if (h >= 22 || h < 4) return 'late_night';
    if (h < 9) return 'early_morning';
    if (h < 12) return 'morning';
    if (h < 17) return 'afternoon';
    return 'evening';
  }

  // ---- corpus ----------------------------------------------------------

  static List<_Template> _buildTrackTemplates() => <_Template>[
        // ===== introSet (opener-only) =====
        _Template(
          intent: DjIntent.introSet,
          position: QueuePositionType.opener,
          phrasings: [
            "Alright... let's lock in. Starting with something to set the tone.",
            "Here we go. First track of the run, {title}, by {artist}.",
            "Setting the scene now. {title} to ease us in.",
            "Locking it in. Up first, {title}.",
            "Starting steady. {artist}, {title}.",
          ],
        ),

        // ===== nextTrack (mid-set fallback) =====
        _Template(
          intent: DjIntent.nextTrack,
          phrasings: [
            "Up next, {title}, by {artist}.",
            "Coming up, {artist} with {title}.",
            "{title} from {artist}, next.",
            "Rolling into {title}.",
          ],
        ),

        // ===== nextTrack — lyric-quoting variants =====
        // Filter only includes these when ctx.hasLyricHook is true, so we
        // never speak an empty placeholder. Templates use either the song's
        // opening line ({first_line}) or its most-repeated line ({hook}).
        _Template(
          intent: DjIntent.nextTrack,
          requiresLyrics: true,
          phrasings: [
            "Up next, {title}. Kicks off with: {first_line}",
            "{artist}, {title}. Starts with: {first_line}",
            "Rolling into {title} — you know how it goes... {hook}",
            "Here's {title}, by {artist}. {hook}",
            "Coming up, {title}. Listen for this one: {hook}",
          ],
        ),

        // ===== favoriteReturn — lean into the lyric the user knows =====
        _Template(
          intent: DjIntent.favoriteReturn,
          requiresLyrics: true,
          phrasings: [
            "One you keep coming back to — {title}. {hook}",
            "Old reliable. {hook}",
            "You know how this one starts: {first_line}",
          ],
        ),

        // ===== artistSpotlight — lyric variants =====
        _Template(
          intent: DjIntent.artistSpotlight,
          requiresLyrics: true,
          phrasings: [
            "Staying with {artist}. Listen for: {hook}",
            "More {artist}. {first_line}",
            "{artist}, {title}. {hook}",
          ],
        ),

        // ===== discovery — quote the opening line so it lands fresh =====
        _Template(
          intent: DjIntent.discovery,
          requiresLyrics: true,
          phrasings: [
            "Trying something new on you — {title}. It opens: {first_line}",
            "{artist}, {title}. First time on the set: {first_line}",
            "Fresh one. {title} starts here: {first_line}",
          ],
        ),

        // ===== energyUp =====
        _Template(
          intent: DjIntent.energyUp,
          phrasings: [
            "Let's bring the energy up a little...",
            "I'm turning the pace up now.",
            "Time to lift the mood a bit.",
            "Let's wake the set up with this one.",
            "Bringing it up. Here's {title}.",
          ],
        ),

        // ===== energyDown =====
        _Template(
          intent: DjIntent.energyDown,
          phrasings: [
            "Let's ease it back for a second...",
            "I'm smoothing things out now.",
            "Let's bring the mood down just a little.",
            "Time for something a bit softer.",
            "Pulling it back. {title}.",
          ],
        ),

        // ===== keepVibe (default fallback) =====
        _Template(
          intent: DjIntent.keepVibe,
          phrasings: [
            "Keeping the vibe going.",
            "Staying in this lane. {title}, next.",
            "Holding the mood. {artist}, {title}.",
            "Letting this one ride into the next...",
            "Same energy. {title}.",
          ],
        ),

        // ===== studyFocus =====
        _Template(
          intent: DjIntent.studyFocus,
          position: QueuePositionType.opener,
          phrasings: [
            "Alright... let's lock in. Starting with something calm to keep you focused.",
            "Easing in. {title} to set the tone for some focused time.",
          ],
        ),
        _Template(
          intent: DjIntent.studyFocus,
          phrasings: [
            "Alright... I'm keeping this one calm. {title} should sit nicely in the background.",
            "Let's stay locked in. This one keeps the focus steady.",
            "I'm keeping the mood light here... nothing too distracting.",
            "This should give you a steady background while you work.",
            "Quiet pick. Stays out of the way.",
          ],
        ),

        // ===== chillTransition =====
        _Template(
          intent: DjIntent.chillTransition,
          phrasings: [
            "Easing into something smoother now.",
            "Let's coast for a minute. {title}.",
            "Pulling the room down a notch.",
            "Quieter from here. {artist}, {title}.",
          ],
        ),

        // ===== workoutBoost =====
        _Template(
          intent: DjIntent.workoutBoost,
          position: QueuePositionType.opener,
          phrasings: [
            "Set's hot. {title} from {artist} — let's move.",
            "Out of the gate hard. {artist}, {title}.",
          ],
        ),
        _Template(
          intent: DjIntent.workoutBoost,
          phrasings: [
            "Stay with it. {title}, by {artist}.",
            "Don't slow down — {title}.",
            "Push through this one. {artist}.",
            "Keep moving. {title}, next.",
          ],
        ),

        // ===== nightDrive =====
        _Template(
          intent: DjIntent.nightDrive,
          phrasings: [
            "Late one tonight. {title} fits the hour.",
            "Quiet hours. {artist}, {title}.",
            "Easing into the night.",
            "Low and steady from here.",
          ],
        ),

        // ===== discovery =====
        _Template(
          intent: DjIntent.discovery,
          phrasings: [
            "I'm slipping in something you haven't played much yet.",
            "Here's one that deserves a little more time.",
            "Let's try something a little less familiar.",
            "I found something that still fits the mood.",
            "First time in the rotation: {title}, by {artist}.",
          ],
        ),

        // ===== throwback =====
        _Template(
          intent: DjIntent.throwback,
          phrasings: [
            "It's been a while since this one played...",
            "Let's bring this one back for a minute.",
            "This one hasn't been in the mix lately.",
            "I'm reaching back a little for this one.",
            "Dusting this off. {title}, by {artist}.",
          ],
        ),

        // ===== favoriteReturn =====
        _Template(
          intent: DjIntent.favoriteReturn,
          phrasings: [
            "You've come back to this one a few times... so I'm putting it in the mix.",
            "This one keeps showing up for you. Let's run it back.",
            "You usually let this one ride, so I'm bringing it in.",
            "This feels like a safe pick right now.",
            "Back to a favorite — {title}.",
          ],
        ),

        // ===== artistSpotlight =====
        _Template(
          intent: DjIntent.artistSpotlight,
          phrasings: [
            "You've been playing a lot of {artist} lately...",
            "{artist} fits this set pretty well, so I'm keeping them in.",
            "Let's stay with the sound you've been leaning toward.",
            "This artist has been working for you lately.",
            "More from {artist} — {title}.",
          ],
        ),

        // ===== moodShift =====
        _Template(
          intent: DjIntent.moodShift,
          phrasings: [
            "Switching the sound here.",
            "Different lane. {title}, by {artist}.",
            "Shifting gears for a minute.",
            "New angle. {artist}, {title}.",
          ],
        ),

        // ===== recoverFromSkip =====
        _Template(
          intent: DjIntent.recoverFromSkip,
          phrasings: [
            "Yeah, not that one. Let's switch it up.",
            "Switching it up — {title}.",
            "Different angle. Trying {artist}.",
            "Pulling something else for you.",
            "Reading the room. {title}, next.",
          ],
        ),

        // ===== setCloser (closer-only) =====
        _Template(
          intent: DjIntent.setCloser,
          position: QueuePositionType.closer,
          phrasings: [
            "One more to close this out...",
            "Let's end this set smoothly.",
            "I'm closing with something that fits the mood.",
            "Last one for this run... let's make it count.",
            "Closing it out with {title}, by {artist}.",
          ],
        ),

        // =====================================================================
        // PERSONALITY LAYER — looser, more conversational variants that
        // don't always lead with the song name. The point is to break up
        // the "Up next, X by Y" rhythm so the DJ doesn't start every
        // transition the same way. Templates here are intentionally short
        // and punchy; they pair well with the lyric-quoting variants up
        // top because the listener gets a beat of personality, then the
        // hook from the song itself.
        // =====================================================================

        // ----- nextTrack: ad-libbed openers -----
        _Template(
          intent: DjIntent.nextTrack,
          phrasings: [
            "Alright... {title}.",
            "Okay, listen.",
            "This one's the move. {title}.",
            "No skips on this. {title}, by {artist}.",
            "Stay with me. {artist}, {title}.",
            "Trust me on this one — {title}.",
            "Mm. Here we go. {title}.",
            "Yeah... {artist}, {title} is in.",
            "I've been waiting to drop this one.",
            "Let it run. {title}.",
            "This is the one. {artist}.",
            "Pay attention to this. {title}.",
          ],
        ),

        // ----- nextTrack: lyric + ad-lib combo -----
        _Template(
          intent: DjIntent.nextTrack,
          requiresLyrics: true,
          phrasings: [
            "Alright... listen for this: {hook}",
            "Okay. {first_line} — that's how this one opens.",
            "Trust me. Listen to {title} — {hook}",
            "Mm. {hook}. {title}, by {artist}.",
            "This one's all about that line — {hook}",
            "Hits different when it lands at {hook}",
          ],
        ),

        // ----- favoriteReturn: warmer, conversational -----
        _Template(
          intent: DjIntent.favoriteReturn,
          phrasings: [
            "You don't get tired of this one, do you?",
            "Yeah... I knew this had to come back.",
            "Putting one of yours back in. {title}.",
            "This is your lane. {artist}, {title}.",
            "Not the first time we've spun this... won't be the last.",
            "We always end up here. {title}.",
          ],
        ),

        // ----- artistSpotlight: more personality -----
        _Template(
          intent: DjIntent.artistSpotlight,
          phrasings: [
            "Staying with {artist} for a minute. They're earning it tonight.",
            "Two in a row from {artist} — they fit the room.",
            "Not done with {artist} yet.",
            "Locked in on {artist} for this stretch.",
            "While we're here — more {artist}.",
          ],
        ),

        // ----- discovery: curious framing -----
        _Template(
          intent: DjIntent.discovery,
          phrasings: [
            "Let's try something. {title}, by {artist}.",
            "First time tonight — {title}.",
            "I'm curious how this one lands for you.",
            "Pulling something off the shelf you haven't touched.",
            "Bear with me. {artist}, {title} — see what you think.",
            "New blood. {title}.",
          ],
        ),

        // ----- throwback: warm reminisce -----
        _Template(
          intent: DjIntent.throwback,
          phrasings: [
            "It's been a minute since this one played. {title}.",
            "Where's this one been hiding? {artist}, {title}.",
            "Dusting this one off. You used to live in it.",
            "Yeah... we owe this one a spin.",
            "Forgot about this until just now. {title}.",
          ],
        ),

        // ----- energyUp: more shape -----
        _Template(
          intent: DjIntent.energyUp,
          phrasings: [
            "Alright — let's pick the room up.",
            "Time to wake the set.",
            "Bringing the tempo up. {title}.",
            "Lift it. {artist}, {title}.",
            "Faster from here. {title}.",
          ],
        ),

        // ----- energyDown: slower, considered -----
        _Template(
          intent: DjIntent.energyDown,
          phrasings: [
            "Pulling the energy back. {title}.",
            "Letting the room breathe a second.",
            "Slower lane for this one.",
            "Bringing it down a notch. {artist}, {title}.",
            "Softer from here.",
          ],
        ),

        // ----- recoverFromSkip: human reactions -----
        _Template(
          intent: DjIntent.recoverFromSkip,
          phrasings: [
            "Yeah, fair. Trying something else.",
            "Noted. Different vibe — {title}.",
            "Reading you. Pulling another one.",
            "Okay, scratch that. {title}, by {artist}.",
            "My bad. Here, try this.",
          ],
        ),

        // ----- moodShift: explicit pivots -----
        _Template(
          intent: DjIntent.moodShift,
          phrasings: [
            "Time for a turn. {title}.",
            "Switching the room.",
            "Different feeling now. {artist}, {title}.",
            "Pivot. {title}.",
            "Shifting the air.",
          ],
        ),
      ];

  static List<_HostTemplate> _buildHostTemplates() => <_HostTemplate>[
        _HostTemplate(
          modes: const [DjMode.workout],
          phrasings: const [
            'Pace stays up. Picking high-BPM cuts across your library.',
            "Set's calibrated for movement.",
          ],
        ),
        _HostTemplate(
          modes: const [DjMode.chill],
          phrasings: const [
            'Keeping it low. Slower-tempo tracks you tend to finish.',
            'Easy rotation tonight.',
          ],
        ),
        _HostTemplate(
          modes: const [DjMode.study],
          phrasings: const [
            'Background-friendly tracks. Quiet enough to think over.',
            'Building a focus set from your calmer cuts.',
          ],
        ),
        _HostTemplate(
          modes: const [DjMode.discover],
          phrasings: const [
            "Tonight's set leans toward stuff you haven't played yet.",
            'Fresh ground from your library.',
          ],
        ),
        _HostTemplate(
          modes: const [DjMode.night],
          phrasings: const [
            'Drift mode. Calm picks for the late side of the day.',
            'Soft set, low room.',
          ],
        ),
        _HostTemplate(
          timeBucket: 'late_night',
          phrasings: const [
            'Late shift. Calmer rotation than usual.',
            'Quiet hours. Set tuned accordingly.',
          ],
        ),
        _HostTemplate(
          timeBucket: 'early_morning',
          phrasings: const [
            'Easing into the morning.',
            'First half of the day, gentle picks up front.',
          ],
        ),
        _HostTemplate(
          phrasings: const [
            "Tonight's set is calibrated to your library.",
            'Pulling threads from your favorites and a few wildcards.',
            'Hosted live, no requests, all signal.',
          ],
        ),
      ];
}

class _Template {
  const _Template({
    required this.intent,
    required this.phrasings,
    this.position,
    this.requiresLyrics = false,
  });
  final DjIntent intent;
  final QueuePositionType? position;
  final List<String> phrasings;

  /// When true, the candidate filter skips this template unless the
  /// context has a lyric hook to inline (`ctx.hasLyricHook`). Lets us
  /// keep templates that quote `{first_line}` / `{hook}` from blowing up
  /// on instrumental tracks or songs with no `.lrc` on disk yet.
  final bool requiresLyrics;
}

class _HostTemplate {
  const _HostTemplate({
    required this.phrasings,
    this.modes,
    this.timeBucket,
  });
  final List<String> phrasings;
  final List<DjMode>? modes;
  final String? timeBucket;
}

/// A filled phrasing carrying its source template back so the caller can
/// inspect template-level flags (e.g., [_Template.requiresLyrics]) after
/// the random pick. Plain pair — the constructor is what makes the type
/// useful here vs. a record.
class _FilledLine {
  const _FilledLine(this.template, this.text);
  final _Template template;
  final String text;
}
