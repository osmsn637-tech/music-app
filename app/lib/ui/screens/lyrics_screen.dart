import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/album_colors.dart';
import '../../data/database/app_database.dart';
import '../../data/models/lyric_line.dart';
import '../../features/library/album_colors_provider.dart';
import '../../features/lyrics/lrc_parser.dart';
import '../../features/lyrics/lyrics_loader.dart';
import '../../features/lyrics/providers.dart';
import '../../features/lyrics/share_lyrics.dart';
import '../../features/player/now_playing_controller.dart';
import '../../features/player/player_service.dart';
import '../../features/player/providers.dart';

/// Apple-Music-style lyrics view, embedded inline in the expanded
/// player.
///
///  - Active line is large bold white; past lines fade. Inside the
///    active line, each word lights up as the song reaches it
///    (karaoke).
///  - The view jumps to the current line on open (no scroll-from-
///    top).
///  - Tap any line to seek to that timestamp.
///
/// The widget renders only the lyrics body — no background, no header,
/// no Scaffold. The host (the full player) provides chrome and bg.
class InlineLyrics extends ConsumerWidget {
  const InlineLyrics({super.key, this.onScrollGesture});

  /// Called with the direction of a user scroll gesture on the lyrics. The
  /// host player uses it to hide (swipe down) / reveal (swipe up) its
  /// controls. Optional so surfaces with no host chrome (the Mac mini-player)
  /// can embed InlineLyrics with no callback.
  final void Function(ScrollDirection direction)? onScrollGesture;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final song = ref.watch(nowPlayingProvider);
    if (song == null) return const _NotPlayingMessage();
    return ref
        .watch(lyricsForSongProvider(song))
        .when(
          loading: () => const Center(
            child: SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: Colors.white,
              ),
            ),
          ),
          error: (e, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                'Error loading lyrics: $e',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xB3FFFFFF), fontSize: 14),
              ),
            ),
          ),
          data: (result) {
            switch (result.kind) {
              case LyricsKind.synced:
                return _SyncedLyricsView(
                  song: song,
                  lines: result.lines,
                  onScrollGesture: onScrollGesture,
                );
              case LyricsKind.plain:
                return _PlainLyricsView(song: song, text: result.plainText!);
              case LyricsKind.none:
                return _NoLyricsMessage(song: song);
            }
          },
        );
  }
}

class _SyncedLyricsView extends ConsumerStatefulWidget {
  const _SyncedLyricsView({
    required this.song,
    required this.lines,
    this.onScrollGesture,
  });
  final SongRow song;
  final List<LyricLine> lines;
  final void Function(ScrollDirection direction)? onScrollGesture;

  @override
  ConsumerState<_SyncedLyricsView> createState() => _SyncedLyricsViewState();
}

class _SyncedLyricsViewState extends ConsumerState<_SyncedLyricsView>
    with SingleTickerProviderStateMixin {
  final _scroll = ScrollController();
  int _activeIndex = -1;
  bool _initialScrollDone = false;

  // Per-line top offsets inside the content area (i.e. excluding the
  // ListView's top padding). Computed once when the lines or content
  // width change, using a TextPainter per line to measure exactly how
  // tall each row will render. This replaces a fixed-avg estimate
  // (98 px / line) — when a song's lyrics wrap to 2 rows on average,
  // the fixed estimate undershoots, so the auto-scroll drifts the
  // active line lower and lower until it sticks to the bottom of the
  // viewport. The exact heights keep it at the intended 38 % anchor.
  List<double> _lineTops = const [];
  double? _measuredWidth;

  // Style used for each lyric row's text. Must match _LyricLineRow's
  // base style exactly, otherwise the measured heights diverge from
  // the rendered ones.
  static const TextStyle _lineStyle = TextStyle(
    fontSize: _LyricLineRow._baseSize,
    fontWeight: _LyricLineRow._baseWeight,
    letterSpacing: -0.025 * _LyricLineRow._baseSize,
    height: 1.12,
  );

  // Adlib rows render smaller (and parenthesized); measuring them with the
  // base style over-estimates their height and drifts the auto-scroll.
  static const TextStyle _adlibLineStyle = TextStyle(
    fontSize: _LyricLineRow._adlibSize,
    fontWeight: _LyricLineRow._adlibWeight,
    letterSpacing: -0.025 * _LyricLineRow._adlibSize,
    height: 1.12,
  );

  // Per-row padding contributions: inner Padding(symmetric h:8, v:8)
  // around the styled text + outer Padding(symmetric v:18) around the
  // GestureDetector. Both come from [_LyricLineRow].
  static const double _innerHPad = 8;
  static const double _innerVPad = 8;
  static const double _outerVPad = 18;
  static const double _rowPaddingY = (_innerVPad + _outerVPad) * 2;

  // When the user manually scrolls, suspend the auto-scroll for a few
  // seconds so a swipe sticks. Without this, every lyric-line
  // transition would yank the list back to the auto-scroll anchor and
  // override the user's gesture.
  DateTime _lastUserScrollAt = DateTime.fromMillisecondsSinceEpoch(0);
  // How long to leave the lyrics wherever the user scrolled before gently
  // gliding back to the active line — long enough to actually read/browse,
  // short enough that it still follows the song.
  static const Duration _userScrollGrace = Duration(seconds: 5);

  // True once the user has scrolled away. When the grace window elapses we
  // glide back to the active line ONCE — even if the active line never
  // changed, so a steady section still re-anchors instead of staying stuck.
  bool _awaitingReturn = false;

  // Position interpolation state. just_audio's positionStream only ticks
  // ~1x/sec, which would make per-word highlighting jerky. We snapshot
  // the last known stream position + wallclock time, then add the delta
  // on every Ticker frame so each frame has a sub-frame-accurate estimate.
  //
  // The interpolated position lives in a ValueNotifier so the karaoke
  // text can rebuild *itself* every frame without rebuilding the
  // ListView, every line in it, the header, or anything else. The
  // active-line index lives on regular state because it changes only
  // every few seconds.
  late final Ticker _ticker;
  Duration _streamPos = Duration.zero;
  DateTime _streamPosAt = DateTime.now();
  bool _isPlaying = false;
  Duration _songDuration = Duration.zero;
  // User-tunable lyric timing offset (positive = lyrics later).
  Duration _offset = Duration.zero;
  final ValueNotifier<Duration> _posNotifier = ValueNotifier<Duration>(
    Duration.zero,
  );
  bool _providersSeeded = false;

  // Off-active blur: non-active lines are blurred (depth-of-field) while the
  // view is anchored to the active line, and stay SHARP the whole time the
  // user browses — re-blurring ONLY when we re-anchor (re-jump) to the active
  // line (see [_scrollToActive]), not on every momentary scroll-settle.
  // Mirrors [_posNotifier]'s pattern so only the visible rows rebuild.
  final ValueNotifier<bool> _scrollingNotifier = ValueNotifier<bool>(false);

  /// Indices of lyric lines the user has picked for share-as-image.
  /// Empty = no selection mode (taps seek normally). Capped at 4 lines
  /// because the share card layout doesn't read well past that.
  final Set<int> _selected = <int>{};
  static const int _maxSelected = 4;
  bool _sharing = false;

  /// Edited lyric lines. When non-null, overrides the original lines
  /// for share/save so the user can tweak wording before exporting.
  List<String>? _editedLines;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
  }

  void _onTick(Duration _) {
    final raw = _isPlaying
        ? _streamPos + DateTime.now().difference(_streamPosAt)
        : _streamPos;
    final next = raw - _offset;

    // Active-line tracking runs every frame, BEFORE the karaoke throttle
    // below — otherwise when the per-frame delta is tiny (e.g. lyrics opened
    // while paused) it would bail before ever computing the active line and
    // nothing would highlight / auto-jump.
    final resolved = _resolveActive(next);
    final changed = resolved != _activeIndex;
    if (changed) {
      setState(() => _activeIndex = resolved);
    }

    // Re-anchor to the active line when the line CHANGES, or when the user
    // browsed away and the grace window has now elapsed (a gentle one-shot
    // return so a steady section still comes back). _scrollToActive itself
    // no-ops while still inside the grace, so this never fights a live swipe.
    final graceElapsed =
        DateTime.now().difference(_lastUserScrollAt) >= _userScrollGrace;
    if (_activeIndex >= 0 && (changed || (_awaitingReturn && graceElapsed))) {
      if (_awaitingReturn && graceElapsed) _awaitingReturn = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _scrollToActive(_activeIndex, animate: true);
      });
    }

    // Throttle ONLY the per-frame karaoke position notifier — its sole job.
    final prev = _posNotifier.value;
    final delta = (next - prev).inMilliseconds.abs();
    if (delta < 80) return;
    _posNotifier.value = next;
  }

  /// Active line index at [position], or -1 during instrumental gaps / the
  /// outro (when the playhead is past the active line's end, with a small
  /// grace so back-to-back line boundaries don't flicker the highlight off).
  int _resolveActive(Duration position) {
    var idx = LrcParser.activeIndex(
      widget.lines,
      position,
    ).clamp(-1, widget.lines.length - 1);
    if (idx >= 0) {
      // Generous grace so only genuine instrumental breaks clear the
      // highlight — natural inter-line pauses keep the previous line lit.
      final end = _lineEnd(idx, _songDuration);
      if (position > end + const Duration(milliseconds: 1500)) idx = -1;
    }
    return idx;
  }

  @override
  void didUpdateWidget(covariant _SyncedLyricsView old) {
    super.didUpdateWidget(old);
    if (!identical(old.lines, widget.lines) ||
        old.lines.length != widget.lines.length) {
      _initialScrollDone = false;
      _activeIndex = -1;
      _invalidateMeasure();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _scroll.dispose();
    _posNotifier.dispose();
    _scrollingNotifier.dispose();
    super.dispose();
  }

  Future<void> _seekTo(Duration time) async {
    final controller = ref.read(nowPlayingProvider.notifier);
    await controller.seek(time);
    // Tapping a lyric line is a "play from here" gesture. If the song is
    // currently paused (or completed), seeking alone leaves us silent at
    // the new position — start playback too so the user hears the line.
    final playing =
        ref.read(playerStateStreamProvider).valueOrNull?.playing ?? false;
    if (!playing) {
      await controller.resume();
    }
  }

  void _onLineTap(int index, Duration time) {
    // While the user has any line selected for sharing, taps toggle
    // selection. Otherwise taps seek (existing behavior).
    if (_selected.isNotEmpty) {
      _toggleSelected(index);
      return;
    }
    _seekTo(time);
  }

  void _onLineLongPress(int index) {
    _toggleSelected(index);
  }

  void _toggleSelected(int index) {
    setState(() {
      if (_selected.contains(index)) {
        _selected.remove(index);
      } else if (_selected.length < _maxSelected) {
        _selected.add(index);
      }
      // Edits are tied to a specific selection — when the set changes,
      // drop the override so the dialog repopulates from originals next
      // time the user taps Edit.
      _editedLines = null;
    });
  }

  void _clearSelection() => setState(() {
    _selected.clear();
    _editedLines = null;
  });

  List<String> _selectedLineTexts() {
    if (_editedLines != null && _editedLines!.isNotEmpty) {
      return _editedLines!;
    }
    final indices = _selected.toList()..sort();
    return [for (final i in indices) widget.lines[i].text];
  }

  List<Color> _currentColors() =>
      ref.read(albumColorsProvider(widget.song.localArtworkPath)).valueOrNull ??
      AlbumColors.fallback;

  Future<void> _shareSelected() async {
    if (_selected.isEmpty || _sharing) return;
    setState(() => _sharing = true);
    try {
      await shareLyricsAsImage(
        context: context,
        song: widget.song,
        lines: _selectedLineTexts(),
        colors: _currentColors(),
      );
      if (mounted) _clearSelection();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not share: $e')));
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  Future<void> _editSelected() async {
    if (_selected.isEmpty || _sharing) return;
    final initial = _selectedLineTexts();
    final controllers = [
      for (final line in initial) TextEditingController(text: line),
    ];
    final result = await showDialog<List<String>>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1E),
        title: const Text(
          'Edit Lyrics',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: controllers.length,
            itemBuilder: (_, i) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: TextField(
                controller: controllers[i],
                style: const TextStyle(color: Colors.white),
                maxLines: null,
                decoration: InputDecoration(
                  labelText: 'Line ${i + 1}',
                  labelStyle: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: Colors.white.withValues(alpha: 0.2),
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: Colors.white.withValues(alpha: 0.2),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Colors.white),
                  ),
                ),
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              'Cancel',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
            ),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(ctx).pop([for (final c in controllers) c.text]),
            child: const Text('Done'),
          ),
        ],
      ),
    );
    for (final c in controllers) {
      c.dispose();
    }
    if (result != null && mounted) {
      setState(() => _editedLines = result);
    }
  }

  Future<void> _saveSelected() async {
    if (_selected.isEmpty || _sharing) return;
    setState(() => _sharing = true);
    try {
      await saveLyricsAsImage(
        context: context,
        song: widget.song,
        lines: _selectedLineTexts(),
        colors: _currentColors(),
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Saved to Photos')));
        _clearSelection();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not save: $e')));
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  /// Lazily measure each lyric line's rendered height at the current
  /// content width. Cached on `(lines, width)`. The measured tops feed
  /// [_offsetForLine] so the auto-scroll lands the active line at
  /// exactly 38 % of viewport height regardless of how many rows each
  /// line wraps to.
  void _ensureMeasured(double contentWidth) {
    if (_measuredWidth == contentWidth &&
        _lineTops.length == widget.lines.length) {
      return;
    }
    final textWidth = contentWidth - _innerHPad * 2;
    final lines = widget.lines;
    final tops = <double>[];
    var cursor = 0.0;
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      tops.add(cursor);
      // Mirror _LyricLineRow's rendered text + style EXACTLY, or _lineTops
      // diverges from the real layout and the auto-scroll drifts: adlibs
      // render smaller + parenthesized, and speaker-change lines add a header.
      final isAdlib = line.isAdlib;
      final raw = line.text.isEmpty ? '♪' : line.text;
      final renderedText = isAdlib ? '($raw)' : raw;
      final tp = TextPainter(
        text: TextSpan(
          text: renderedText,
          style: isAdlib ? _adlibLineStyle : _lineStyle,
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: textWidth);
      var rowH = tp.size.height + _rowPaddingY;
      tp.dispose();
      // Speaker header (Text fontSize 11 + 6px bottom padding), inserted by
      // build() on the same condition: speaker-change, non-adlib lines.
      if (line.speakerName != null && !isAdlib) {
        String? prevName;
        for (var j = i - 1; j >= 0; j--) {
          if (lines[j].isAdlib) continue;
          prevName = lines[j].speakerName;
          break;
        }
        if (prevName != line.speakerName) {
          final htp = TextPainter(
            text: TextSpan(
              text: (line.speakerName ?? '').toUpperCase(),
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.4,
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout(maxWidth: textWidth);
          rowH += htp.size.height + 6;
          htp.dispose();
        }
      }
      cursor += rowH;
    }
    _lineTops = tops;
    _measuredWidth = contentWidth;
  }

  /// Scroll offset that places the [index]th line at ~30 % of the
  /// viewport. Uses the precomputed per-line heights — exact, no
  /// drift across long songs / wrapped lines.
  ///
  /// `topPadFrac` and `anchorFrac` MUST mirror the fractions used for
  /// the ListView's top padding and the visible anchor row in build()
  /// — when they drift, the active line ends up far above or below
  /// where it was supposed to land. Keeping them equal also pins
  /// line 0 to the anchor at scroll=0, so the very first line never
  /// has to clamp against the scroll min/max extents.
  static const double _topPadFrac = 0.28;
  static const double _anchorFrac = 0.28;

  double _offsetForLine(int index, double viewportHeight) {
    if (index < 0 || index >= _lineTops.length) return 0;
    final topPad = viewportHeight * _topPadFrac;
    final lineTop = topPad + _lineTops[index];
    return (lineTop - viewportHeight * _anchorFrac).clamp(0.0, double.infinity);
  }

  /// Scroll the [index]th line into view at ~38 % of viewport height.
  /// Skipped while the user has scrolled manually within the last few
  /// seconds — auto-scroll should never fight a deliberate swipe.
  bool _scrollToActive(int index, {required bool animate}) {
    if (!_scroll.hasClients) return false;
    if (index < 0 || index >= widget.lines.length) return false;
    if (animate &&
        DateTime.now().difference(_lastUserScrollAt) < _userScrollGrace) {
      return false;
    }
    final viewportHeight = _scroll.position.viewportDimension;
    final target = _offsetForLine(
      index,
      viewportHeight,
    ).clamp(_scroll.position.minScrollExtent, _scroll.position.maxScrollExtent);
    // Re-anchoring to the active line is the ONE moment the depth-of-field
    // returns — eased back in via the rows' TweenAnimationBuilder. Browsing
    // keeps the lines sharp until this fires (after the user-scroll grace).
    if (_scrollingNotifier.value) _scrollingNotifier.value = false;
    if (animate) {
      _scroll.animateTo(
        target,
        duration: const Duration(milliseconds: 620),
        curve: Curves.easeOutCubic,
      );
    } else {
      _scroll.jumpTo(target);
    }
    return true;
  }

  /// Jump straight to the active line on first build. Uses the exact
  /// precomputed offset — no second-pass refinement needed.
  void _initialJumpTo(int index) {
    if (!_scroll.hasClients) return;
    final viewportHeight = _scroll.position.viewportDimension;
    final estimate = _offsetForLine(
      index,
      viewportHeight,
    ).clamp(_scroll.position.minScrollExtent, _scroll.position.maxScrollExtent);
    _scroll.jumpTo(estimate);
    _initialScrollDone = true;
  }

  /// Drop the measured heights when the lyric list changes, so the
  /// next build re-measures against the new lines.
  void _invalidateMeasure() {
    _lineTops = const [];
    _measuredWidth = null;
  }

  /// Called from the ListView's NotificationListener when a scroll
  /// gesture from the user (not our own animateTo) drives the
  /// position. Marks the user-scroll grace window so the auto-scroll
  /// stops fighting the swipe.
  bool _onScrollNotification(ScrollNotification n) {
    if (n is UserScrollNotification && n.direction != ScrollDirection.idle) {
      // User-initiated drag/fling. (Our own animateTo emits ScrollUpdate but
      // never UserScroll, so auto-scroll doesn't trip this.) Sharpen the
      // lyrics and HOLD them sharp — they re-blur only when we re-anchor to
      // the active line (in _scrollToActive), not on every scroll-settle.
      _lastUserScrollAt = DateTime.now();
      _awaitingReturn = true; // glide back to active once the grace elapses
      if (!_scrollingNotifier.value) _scrollingNotifier.value = true;
      // Hand the swipe direction to the host (player) so it can hide controls
      // on a downward swipe and reveal them on the second upward swipe.
      widget.onScrollGesture?.call(n.direction);
    }
    return false;
  }

  /// Time at which the active line ends. Prefers the parsed trailing
  /// `<mm:ss.xx>` end marker from the alignment pass; falls back to the
  /// next line's start, then song duration, then +4s.
  Duration _lineEnd(int index, Duration songDuration) {
    final line = widget.lines[index];
    if (line.endTime != null) return line.endTime!;
    if (index + 1 < widget.lines.length) {
      return widget.lines[index + 1].time;
    }
    if (songDuration > line.time) return songDuration;
    return line.time + const Duration(seconds: 4);
  }

  @override
  Widget build(BuildContext context) {
    // Side-effect-only listeners on the player streams. Using
    // `ref.listen` instead of `ref.watch` keeps the position emission
    // (~16 Hz) from rebuilding the entire ListView every frame — the
    // ticker handles per-frame interpolation, this is just keeping the
    // snapshot baseline fresh. Build now only runs when _activeIndex
    // or share-state changes, which is what makes the page 60 fps.
    ref.listen<AsyncValue<Duration>>(playerPositionProvider, (_, next) {
      final pos = next.valueOrNull;
      if (pos == null || pos == _streamPos) return;
      _streamPos = pos;
      _streamPosAt = DateTime.now();
      final adjusted = pos - _offset;
      if ((_posNotifier.value - adjusted).inMilliseconds.abs() > 250) {
        _posNotifier.value = adjusted;
      }
    });
    ref.listen<AsyncValue<PlayerSnapshot>>(playerStateStreamProvider, (
      _,
      next,
    ) {
      _isPlaying = next.valueOrNull?.playing ?? false;
    });
    ref.listen<AsyncValue<Duration?>>(playerDurationProvider, (_, next) {
      _songDuration = next.valueOrNull ?? _songDuration;
    });

    // Live lyric offset (rebuilds this view when nudged).
    _offset = Duration(
      milliseconds: ref.watch(lyricOffsetProvider(widget.song.id)),
    );

    // Seed once from a synchronous read so the first frame has values.
    // `ref.listen` only fires on subsequent emissions.
    if (!_providersSeeded) {
      _providersSeeded = true;
      _streamPos =
          ref.read(playerPositionProvider).valueOrNull ?? Duration.zero;
      _streamPosAt = DateTime.now();
      _posNotifier.value = _streamPos - _offset;
      _isPlaying =
          ref.read(playerStateStreamProvider).valueOrNull?.playing ?? false;
      _songDuration =
          ref.read(playerDurationProvider).valueOrNull ?? Duration.zero;
      // Seed the active index so the initial-jump gate fires even when the
      // song is paused (the ticker's first delta would otherwise be ~0).
      _activeIndex = _resolveActive(_streamPos - _offset);
    }
    final songDuration = _songDuration;

    if (!_initialScrollDone && _activeIndex >= 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _initialScrollDone) return;
        _initialJumpTo(_activeIndex);
      });
    }

    final lines = widget.lines;

    return Stack(
      children: [
        Column(
          children: [
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // viewportHeight is the actual pane the ListView paints
                  // into — for the player's embedded lyrics that's the
                  // freed area between the thumbnail header and the
                  // scrubber, much shorter than the full screen. Using
                  // it (rather than MediaQuery.size.height) keeps the
                  // active line anchored near the top of the *visible*
                  // pane instead of dumping it off the bottom.
                  final viewportHeight = constraints.maxHeight;
                  // Measure line heights against the ACTUAL list width, which on
                  // desktop (the 640px panel) and the mini-player is far
                  // narrower than the window — matching the 18 + 50 h-padding
                  // below. Measuring with the window width made wrapped lines
                  // mis-measure short, drifting the active line off the bottom.
                  _ensureMeasured(constraints.maxWidth - 18 - 50);
                  return NotificationListener<ScrollNotification>(
                    onNotification: _onScrollNotification,
                    child: ListView.builder(
                      controller: _scroll,
                      // Asymmetric horizontal padding — left edge sits
                      // close to the screen edge so the active line's
                      // `_activeScale` (~1.22) can grow rightward
                      // without bleeding into the gutter. Right padding
                      // is generous for the same reason.
                      padding: EdgeInsets.fromLTRB(
                        18,
                        viewportHeight * _topPadFrac,
                        50,
                        viewportHeight * 0.50,
                      ),
                      itemCount: lines.length,
                      itemBuilder: (context, i) {
                        final line = lines[i];
                        final isActive = i == _activeIndex;
                        final isPast = i < _activeIndex;
                        final isSelected = _selected.contains(i);
                        final lineEnd = _lineEnd(i, songDuration);
                        // Show a small uppercase artist label above the first
                        // line of each new speaker block. Skips adlib lines
                        // when comparing — diarization on adlibs is noisy.
                        String? speakerHeader;
                        if (line.speakerName != null && !line.isAdlib) {
                          String? prevName;
                          for (var j = i - 1; j >= 0; j--) {
                            if (lines[j].isAdlib) continue;
                            prevName = lines[j].speakerName;
                            break;
                          }
                          if (prevName != line.speakerName) {
                            speakerHeader = line.speakerName;
                          }
                        }
                        // Depth-of-field distance from the active line (big =
                        // no active line → render everything sharp).
                        final distanceFromActive = _activeIndex < 0
                            ? 999
                            : (i - _activeIndex).abs();
                        return _LyricLineRow(
                          line: line,
                          speakerHeader: speakerHeader,
                          isActive: isActive,
                          isPast: isPast,
                          isSelected: isSelected,
                          posNotifier: _posNotifier,
                          scrollingNotifier: _scrollingNotifier,
                          distanceFromActive: distanceFromActive,
                          end: lineEnd,
                          onTap: () => _onLineTap(i, line.time),
                          onLongPress: () => _onLineLongPress(i),
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
        // Frosted glass edges — lyric lines scroll *behind* a soft frost
        // at the top and bottom of the pane (seen through the blur)
        // instead of hard-cutting at the boundary.
        const Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: _LyricFrostEdge(top: true),
        ),
        const Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: _LyricFrostEdge(top: false),
        ),
        // Share toolbar — slides in from the top whenever the user has
        // any line selected. Sits above the lyrics, doesn't push them.
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            child: AnimatedSlide(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              offset: _selected.isEmpty ? const Offset(0, -1.4) : Offset.zero,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 180),
                opacity: _selected.isEmpty ? 0 : 1,
                child: _ShareToolbar(
                  selectedCount: _selected.length,
                  maxCount: _maxSelected,
                  busy: _sharing,
                  onCancel: _clearSelection,
                  onShare: _shareSelected,
                  onSave: _saveSelected,
                  onEdit: _editSelected,
                ),
              ),
            ),
          ),
        ),
        // Lyric sync offset nudge — hidden while picking lines to share.
        if (_selected.isEmpty)
          Positioned(
            right: 12,
            bottom: 6,
            child: _OffsetControl(songId: widget.song.id),
          ),
      ],
    );
  }
}

/// Soft frosted edge for the lyrics pane. Two stacked blur strips — a
/// light frost over the whole band and a heavier one concentrated at the
/// very edge — so lyric lines dissolve into glass as they reach the top /
/// bottom rather than hard-cutting. The lines there are already
/// depth-of-field blurred, which hides the strips' inner seam. [top]
/// picks which edge it hugs.
class _LyricFrostEdge extends StatelessWidget {
  const _LyricFrostEdge({required this.top});

  final bool top;

  static const double _band = 96;

  Widget _strip(double height, double sigma) => ClipRect(
    child: ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (rect) => LinearGradient(
        begin: top ? Alignment.topCenter : Alignment.bottomCenter,
        end: top ? Alignment.bottomCenter : Alignment.topCenter,
        colors: [Colors.white, Colors.white.withValues(alpha: 0)],
      ).createShader(rect),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
        child: SizedBox(height: height, width: double.infinity),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final align = top ? Alignment.topCenter : Alignment.bottomCenter;
    return IgnorePointer(
      child: SizedBox(
        height: _band,
        width: double.infinity,
        child: Stack(
          alignment: align,
          children: [_strip(_band, 7), _strip(_band * 0.55, 16)],
        ),
      ),
    );
  }
}

class _OffsetControl extends ConsumerWidget {
  const _OffsetControl({required this.songId});
  final String songId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ms = ref.watch(lyricOffsetProvider(songId));
    final notifier = ref.read(lyricOffsetProvider(songId).notifier);
    final label = ms == 0
        ? 'Sync'
        : '${ms > 0 ? '+' : ''}${(ms / 1000).toStringAsFixed(1)}s';

    Widget btn(IconData icon, VoidCallback onTap) => GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Icon(icon, size: 18, color: Colors.white),
      ),
    );

    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          btn(
            Icons.remove,
            () => notifier.state = (ms - 200).clamp(-5000, 5000),
          ),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => notifier.state = 0,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(
                label,
                style: TextStyle(
                  color: ms == 0
                      ? Colors.white.withValues(alpha: 0.7)
                      : Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [],
                ),
              ),
            ),
          ),
          btn(Icons.add, () => notifier.state = (ms + 200).clamp(-5000, 5000)),
        ],
      ),
    );
  }
}

class _ShareToolbar extends StatelessWidget {
  const _ShareToolbar({
    required this.selectedCount,
    required this.maxCount,
    required this.busy,
    required this.onCancel,
    required this.onShare,
    required this.onSave,
    required this.onEdit,
  });

  final int selectedCount;
  final int maxCount;
  final bool busy;
  final VoidCallback onCancel;
  final VoidCallback onShare;
  final VoidCallback onSave;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final disabled = busy || selectedCount == 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Material(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(999),
        elevation: 0,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                tooltip: 'Cancel',
                onPressed: busy ? null : onCancel,
              ),
              Expanded(
                child: Text(
                  '$selectedCount of $maxCount selected',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.save_alt, color: Colors.white),
                tooltip: 'Save to Photos',
                onPressed: disabled ? null : onSave,
              ),
              IconButton(
                icon: const Icon(Icons.edit, color: Colors.white),
                tooltip: 'Edit text',
                onPressed: disabled ? null : onEdit,
              ),
              FilledButton.icon(
                onPressed: disabled ? null : onShare,
                icon: busy
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.ios_share, size: 18),
                label: const Text('Share'),
                style: FilledButton.styleFrom(
                  shape: const StadiumBorder(),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One lyric line. Routing:
///   * [LyricLine.isAdlib] → smaller, parenthesized, dim, no scale-up.
///   * Active + has word timings → [_KaraokeText] sweeps per word using the
///     timings emitted by the server's align pass.
///   * Active without word timings → plain line in bright colour (no fake
///     per-word animation — alignment is the source of truth).
///   * Inactive → plain line, past/future colour.
/// An optional [speakerHeader] renders a small uppercase artist label
/// above the line text on the first line of each speaker block.
class _LyricLineRow extends StatelessWidget {
  const _LyricLineRow({
    required this.line,
    required this.isActive,
    required this.isPast,
    required this.posNotifier,
    required this.scrollingNotifier,
    required this.distanceFromActive,
    required this.end,
    required this.onTap,
    this.speakerHeader,
    this.isSelected = false,
    this.onLongPress,
  });

  final LyricLine line;
  final String? speakerHeader;
  final bool isActive;
  final bool isPast;

  /// True while the user has this line picked for share-as-image.
  /// Renders a highlight pill behind the text.
  final bool isSelected;

  /// Live playhead position. Per-frame updates flow through this notifier
  /// so only the active line's karaoke text rebuilds — the row itself,
  /// the list, and inactive lines stay stable.
  final ValueListenable<Duration> posNotifier;

  /// True while the user is scrolling — blur is suppressed so lines are
  /// sharp and readable; it eases back once the list settles.
  final ValueListenable<bool> scrollingNotifier;

  /// |index - activeIndex| — drives the depth-of-field blur amount.
  final int distanceFromActive;
  final Duration end;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  static const _bright = Colors.white;
  static const _dimActive = Color(0x99FFFFFF); // 60% — un-passed words
  static const _past = Color(0x4DFFFFFF); // 30%
  static const _future = Color(0x8CFFFFFF); // 55%
  // Adlib palette: noticeably dimmer than main text so they read as
  // background rather than primary lyric.
  static const _adlibActive = Color(0xB3FFFFFF); // 70%
  static const _adlibPast = Color(0x33FFFFFF); // 20%
  static const _adlibFuture = Color(0x66FFFFFF); // 40%

  // Every line is laid out at `_baseSize` so the wrap is identical
  // whether it's active or not. The "bigger when active" effect is a
  // Transform.scale — paints same-laid-out text larger without re-flowing.
  // Sized for the inline player surface — the old 32 pt baseline came
  // from a full-screen LyricsScreen and crowded the smaller pane.
  static const _baseSize = 22.0;
  static const _baseWeight = FontWeight.w800;
  // Adlibs render at 70% size, semi-bold (not extra-bold), so they recede.
  static const _adlibSize = _baseSize * 0.7;
  static const _adlibWeight = FontWeight.w600;
  static const _activeScale = 1.22;

  @override
  Widget build(BuildContext context) {
    final isAdlib = line.isAdlib;
    final text = line.text;

    final fallbackColor = isAdlib
        ? (isPast ? _adlibPast : (isActive ? _adlibActive : _adlibFuture))
        : (isPast ? _past : (isActive ? _bright : _future));

    // Adlibs always render plain (parenthesized). Word-by-word highlight
    // on a 1-word "(yeah)" is just visual noise.
    final renderedText = isAdlib
        ? '(${text.isEmpty ? '♪' : text})'
        : (text.isEmpty ? '♪' : text);

    final Widget textChild = (!isAdlib && isActive && line.hasWordTimings)
        ? _KaraokeText(
            words: line.words,
            lineEnd: end,
            posNotifier: posNotifier,
          )
        : Text(renderedText);

    Widget styled = DefaultTextStyle(
      style: TextStyle(
        color: fallbackColor,
        fontSize: isAdlib ? _adlibSize : _baseSize,
        fontWeight: isAdlib ? _adlibWeight : _baseWeight,
        letterSpacing: -0.025 * (isAdlib ? _adlibSize : _baseSize),
        height: 1.12,
      ),
      child: textChild,
    );

    if (isActive && !isAdlib) {
      styled = Transform.scale(
        scale: _activeScale,
        alignment: Alignment.centerLeft,
        child: styled,
      );
    }

    // Speaker header: small uppercase chip-style label above the line,
    // only shown on speaker-change lines.
    Widget body = styled;
    if (speakerHeader != null) {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              speakerHeader!.toUpperCase(),
              style: const TextStyle(
                color: Color(0x99FFFFFF),
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.4,
              ),
            ),
          ),
          styled,
        ],
      );
    }

    Widget content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: body,
    );

    if (isSelected) {
      content = DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(18),
        ),
        child: content,
      );
    }

    // Apple-Music depth-of-field: lines blur more the farther they sit from
    // the active line, but snap sharp while the user scrolls. The active line
    // targets sigma 0 (never blurred). EVERY line is wrapped — not just
    // inactive ones — so the row element is reused across active-status
    // changes and the blur EASES in/out instead of popping. The
    // `sigma < 0.05` early-return means a sharp/active line pays zero cost:
    // no ImageFiltered (and thus no per-frame saveLayer) over the karaoke
    // painter.
    final wantBlur =
        !isActive && distanceFromActive >= 1 && distanceFromActive <= 6;
    content = ValueListenableBuilder<bool>(
      valueListenable: scrollingNotifier,
      child: content,
      builder: (context, scrolling, child) {
        return TweenAnimationBuilder<double>(
          tween: Tween<double>(end: (wantBlur && !scrolling) ? 1.0 : 0.0),
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          child: child,
          builder: (context, t, c) {
            final sigma = t * math.min(6.0, distanceFromActive * 1.1);
            if (sigma < 0.05) return c!;
            return ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
              child: c!,
            );
          },
        );
      },
    );

    return Padding(
      // Vertical padding sized to absorb the scaled-up active line so it
      // doesn't bleed into neighbouring rows.
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        onLongPress: onLongPress,
        child: content,
      ),
    );
  }
}

/// The active line's text, with each word's colour eased from dim to bright
/// as the playhead moves through the line. Word durations are weighted by
/// character count so short connectives don't get the same time as long
/// words.
///
/// Implementation: previously rebuilt a full `Text.rich` with N fresh
/// `InlineSpan`s on every `posNotifier` tick. That forced text layout
/// + glyph shaping every emission (~12 Hz on the throttle, but still
/// per-tick work that's quadratic-ish in line length). Now the line is
/// laid out exactly ONCE — when text or width changes — into two
/// reusable [TextPainter]s (one dim, one bright). The `CustomPainter`
/// listens to [posNotifier] directly via `super(repaint:)`, so a
/// position tick triggers ONLY a paint pass, never a widget rebuild
/// and never a re-layout. The bright text is drawn clipped to
/// already-passed word boxes; the currently-transitioning word gets a
/// `saveLayer` so its alpha can ease 0 → 1 without blowing up the cost.
class _KaraokeText extends StatefulWidget {
  const _KaraokeText({
    required this.words,
    required this.lineEnd,
    required this.posNotifier,
  });

  /// Per-word timings emitted by the server's align pass. Words appear in
  /// playback order; rendering text is `words.map(text).join(' ')`.
  final List<WordTiming> words;

  /// End of the line — preferred order: trailing `<mm:ss.xx>` end marker
  /// from the parser, then next line's start, then song duration.
  final Duration lineEnd;

  final ValueListenable<Duration> posNotifier;

  @override
  State<_KaraokeText> createState() => _KaraokeTextState();
}

class _KaraokeTextState extends State<_KaraokeText> {
  TextPainter? _tpDim;
  TextPainter? _tpBright;

  // Visual rects per word in the laid-out text. Usually one rect per word;
  // wrapped words get multiple. Used as clip path + saveLayer bounds.
  List<List<Rect>> _wordBoxes = const [];

  // Per-word (startProgress, endProgress) within the line, normalized to
  // [0, 1] from real WordTiming start times. Word i ends where word i+1
  // starts (or at lineEnd for the last word).
  List<(double, double)> _wordRanges = const [];

  // Cached line start (= first word's time) and end. Drive progress in
  // the painter — kept in state so the painter doesn't have to recompute.
  Duration _lineStart = Duration.zero;
  Duration _lineEnd = Duration.zero;

  // Layout cache key.
  String? _laidOutText;
  double? _laidOutWidth;
  double? _laidOutFontSize;
  FontWeight? _laidOutWeight;
  double? _laidOutLetterSpacing;
  double? _laidOutHeight;

  void _ensureLayout(TextStyle base, double maxWidth) {
    final words = widget.words;
    final text = words.isEmpty ? '♪' : words.map((w) => w.text).join(' ');

    if (text == _laidOutText &&
        maxWidth == _laidOutWidth &&
        base.fontSize == _laidOutFontSize &&
        base.fontWeight == _laidOutWeight &&
        base.letterSpacing == _laidOutLetterSpacing &&
        base.height == _laidOutHeight) {
      // Word timings or lineEnd may have changed even when the text /
      // style did not — refresh the time ranges cheap.
      _recomputeRanges();
      return;
    }
    _tpDim?.dispose();
    _tpBright?.dispose();
    final dimStyle = base.copyWith(color: _LyricLineRow._dimActive);
    final brightStyle = base.copyWith(color: _LyricLineRow._bright);
    _tpDim = TextPainter(
      text: TextSpan(text: text, style: dimStyle),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: maxWidth);
    _tpBright = TextPainter(
      text: TextSpan(text: text, style: brightStyle),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: maxWidth);

    // Word char ranges follow the join-with-space layout — one entry per
    // WordTiming, in the same order.
    final charRanges = <(int, int)>[];
    var cursor = 0;
    for (var i = 0; i < words.length; i++) {
      final w = words[i].text;
      if (w.isEmpty) continue;
      charRanges.add((cursor, cursor + w.length));
      cursor += w.length;
      if (i + 1 < words.length) cursor += 1; // joined-space
    }

    _wordBoxes = [
      for (final r in charRanges)
        _tpDim!
            .getBoxesForSelection(
              TextSelection(baseOffset: r.$1, extentOffset: r.$2),
            )
            .map((b) => b.toRect())
            .toList(growable: false),
    ];

    _recomputeRanges();

    _laidOutText = text;
    _laidOutWidth = maxWidth;
    _laidOutFontSize = base.fontSize;
    _laidOutWeight = base.fontWeight;
    _laidOutLetterSpacing = base.letterSpacing;
    _laidOutHeight = base.height;
  }

  void _recomputeRanges() {
    final words = widget.words;
    if (words.isEmpty) {
      _wordRanges = const [];
      _lineStart = Duration.zero;
      _lineEnd = widget.lineEnd;
      return;
    }
    final start = words.first.time;
    final end = widget.lineEnd > start
        ? widget.lineEnd
        : start + const Duration(seconds: 1);
    _lineStart = start;
    _lineEnd = end;
    final spanMs = (end - start).inMilliseconds.clamp(1, 1 << 31);
    // Keep every word's normalized start strictly below 1.0 so a word timed
    // at/after the line end can't make the painter's `progress <= wStart`
    // break fire permanently — otherwise the tail of the line never lights.
    final maxStart = (spanMs - 1).clamp(0, spanMs);
    final ranges = <(double, double)>[];
    for (var i = 0; i < words.length; i++) {
      final ws = (words[i].time - start).inMilliseconds
          .clamp(0, maxStart)
          .toDouble();
      final weEnd = i + 1 < words.length
          ? (words[i + 1].time - start).inMilliseconds
                .clamp(0, spanMs)
                .toDouble()
          : spanMs.toDouble();
      // Guard end >= start so the range stays paintable.
      ranges.add((ws / spanMs, (weEnd < ws ? ws : weEnd) / spanMs));
    }
    _wordRanges = ranges;
  }

  @override
  void dispose() {
    _tpDim?.dispose();
    _tpBright?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = DefaultTextStyle.of(context).style;
    return LayoutBuilder(
      builder: (ctx, c) {
        _ensureLayout(base, c.maxWidth);
        final dim = _tpDim!;
        return CustomPaint(
          size: Size(dim.size.width, dim.size.height),
          painter: _KaraokePainter(
            tpDim: dim,
            tpBright: _tpBright!,
            wordBoxes: _wordBoxes,
            wordRanges: _wordRanges,
            posNotifier: widget.posNotifier,
            start: _lineStart,
            end: _lineEnd,
          ),
        );
      },
    );
  }
}

class _KaraokePainter extends CustomPainter {
  _KaraokePainter({
    required this.tpDim,
    required this.tpBright,
    required this.wordBoxes,
    required this.wordRanges,
    required this.posNotifier,
    required this.start,
    required this.end,
  }) : super(repaint: posNotifier);

  final TextPainter tpDim;
  final TextPainter tpBright;
  final List<List<Rect>> wordBoxes;
  final List<(double, double)> wordRanges;
  final ValueListenable<Duration> posNotifier;
  final Duration start;
  final Duration end;

  @override
  void paint(Canvas canvas, Size size) {
    // Dim base — un-passed and partially-lit words read against this.
    tpDim.paint(canvas, Offset.zero);

    if (wordRanges.isEmpty) return;

    final spanMs = end > start ? (end - start).inMilliseconds : 1;
    final elapsed = (posNotifier.value - start).inMilliseconds
        .clamp(0, spanMs)
        .toDouble();
    final progress = elapsed / spanMs;
    if (progress <= 0) return;

    // Fully-passed words: one clip path → one paint of the bright TP.
    // Transitioning word (at most one — progress is monotonic): a
    // saveLayer keyed by its eased t so it fades 0 → 1.
    final fullPath = Path();
    var anyFull = false;
    int? transitioningIndex;
    double transitioningEased = 0;
    for (var i = 0; i < wordRanges.length; i++) {
      final (wStart, wEnd) = wordRanges[i];
      if (progress <= wStart) break;
      if (progress >= wEnd) {
        for (final r in wordBoxes[i]) {
          fullPath.addRect(r);
        }
        anyFull = true;
      } else {
        final t = wEnd == wStart
            ? 1.0
            : ((progress - wStart) / (wEnd - wStart)).clamp(0.0, 1.0);
        transitioningEased = Curves.easeOut.transform(t);
        transitioningIndex = i;
        break;
      }
    }
    if (anyFull) {
      canvas.save();
      canvas.clipPath(fullPath);
      tpBright.paint(canvas, Offset.zero);
      canvas.restore();
    }
    if (transitioningIndex != null && transitioningEased > 0) {
      final boxes = wordBoxes[transitioningIndex];
      if (boxes.isNotEmpty) {
        var bounds = boxes.first;
        for (var k = 1; k < boxes.length; k++) {
          bounds = bounds.expandToInclude(boxes[k]);
        }
        canvas.saveLayer(
          bounds,
          Paint()..color = Color.fromRGBO(255, 255, 255, transitioningEased),
        );
        final clip = Path();
        for (final r in boxes) {
          clip.addRect(r);
        }
        canvas.clipPath(clip);
        tpBright.paint(canvas, Offset.zero);
        canvas.restore();
      }
    }
  }

  @override
  bool shouldRepaint(_KaraokePainter old) {
    // Same TP + same word data → no repaint needed (the posNotifier
    // drives repaints separately via `super(repaint:)`).
    return !identical(old.tpDim, tpDim) ||
        !identical(old.tpBright, tpBright) ||
        !identical(old.wordBoxes, wordBoxes) ||
        !identical(old.wordRanges, wordRanges) ||
        old.start != start ||
        old.end != end;
  }
}

class _PlainLyricsView extends StatelessWidget {
  const _PlainLyricsView({required this.song, required this.text});
  final SongRow song;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 100),
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              height: 1.22,
              letterSpacing: -0.55,
            ),
          ),
        ),
        const Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: _LyricFrostEdge(top: true),
        ),
        const Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: _LyricFrostEdge(top: false),
        ),
      ],
    );
  }
}

class _NoLyricsMessage extends ConsumerWidget {
  const _NoLyricsMessage({required this.song});
  final SongRow song;

  Future<void> _addLyrics(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1E),
        title: const Text(
          'Add lyrics',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: TextField(
            controller: controller,
            autofocus: true,
            minLines: 6,
            maxLines: 12,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Paste lyrics or a .lrc (with [mm:ss.xx] tags)…',
              hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.4)),
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              'Cancel',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (text == null || text.trim().isEmpty) return;
    await ref.read(lyricsActionsProvider).saveLyrics(song, text);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.lyrics_outlined,
              size: 64,
              color: Color(0x99FFFFFF),
            ),
            const SizedBox(height: 16),
            const Text(
              'No lyrics available',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Paste your own below, or drop a matching .lrc into your '
              'server\'s lyrics/ folder and re-sync.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Color(0xB3FFFFFF)),
            ),
            const SizedBox(height: 20),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _addLyrics(context, ref),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 11,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add_rounded, size: 18, color: Colors.black),
                    SizedBox(width: 6),
                    Text(
                      'Add lyrics',
                      style: TextStyle(
                        color: Colors.black,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotPlayingMessage extends StatelessWidget {
  const _NotPlayingMessage();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text('Nothing playing.', style: TextStyle(color: Colors.white)),
    );
  }
}
