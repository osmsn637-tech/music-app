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

/// Apple-Music-style lyrics view.
///
///  - Background is the same blurred-artwork bloom as the Player.
///  - Active line is large bold white; past lines fade. Inside the active
///    line, each word lights up as the song reaches it (karaoke).
///  - The view jumps to the current line on open (no scroll-from-top).
///  - Tap any line to seek to that timestamp.
class LyricsScreen extends ConsumerStatefulWidget {
  const LyricsScreen({super.key});

  @override
  ConsumerState<LyricsScreen> createState() => _LyricsScreenState();
}

class _LyricsScreenState extends ConsumerState<LyricsScreen> {
  @override
  Widget build(BuildContext context) {
    final song = ref.watch(nowPlayingProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Plain dark gradient bg — replaces the previous BloomBackground.
          // The bloom (FFT ticker @ 20 Hz, 3 aurora curtains driven by bass /
          // snare kicks, ImageFiltered blurred art) was running underneath
          // the heavy 1.4× lyrics vignette where ~none of its motion was
          // visible. Static gradient costs zero per-frame work.
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF0A0A12), Color(0xFF000000)],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Material(
              type: MaterialType.transparency,
              child: _buildContent(song),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(SongRow? song) {
    if (song == null) return const _NotPlayingMessage();
    return ref.watch(lyricsForSongProvider(song)).when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error loading lyrics: $e')),
          data: (result) {
            switch (result.kind) {
              case LyricsKind.synced:
                return _SyncedLyricsView(song: song, lines: result.lines);
              case LyricsKind.plain:
                return _PlainLyricsView(
                    song: song, text: result.plainText!);
              case LyricsKind.none:
                return _NoLyricsMessage(song: song);
            }
          },
        );
  }
}

class _Header extends StatelessWidget {
  const _Header({this.song});
  final SongRow? song;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Row(
        children: [
          _RoundIcon(
            icon: Icons.keyboard_arrow_down,
            onTap: () => Navigator.of(context).maybePop(),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  song?.title ?? 'Lyrics',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (song?.artist != null)
                  Text(
                    song!.artist!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.white.withValues(alpha: 0.65),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RoundIcon extends StatelessWidget {
  const _RoundIcon({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: 0.12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
          ),
          child: Icon(icon, size: 18),
        ),
      ),
    );
  }
}

class _SyncedLyricsView extends ConsumerStatefulWidget {
  const _SyncedLyricsView({required this.song, required this.lines});
  final SongRow song;
  final List<LyricLine> lines;

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
  static const Duration _userScrollGrace = Duration(seconds: 4);

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
  final ValueNotifier<Duration> _posNotifier =
      ValueNotifier<Duration>(Duration.zero);
  bool _providersSeeded = false;

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
    final next = _isPlaying
        ? _streamPos + DateTime.now().difference(_streamPosAt)
        : _streamPos;
    final prev = _posNotifier.value;
    final delta = (next - prev).inMilliseconds.abs();
    if (delta < 80) return;
    _posNotifier.value = next;

    // Active-line tracking: only fire setState when the index actually
    // changes. Most ticks just update the karaoke notifier and exit cheap.
    final newActive = LrcParser.activeIndex(widget.lines, next)
        .clamp(-1, widget.lines.length - 1);
    if (newActive != _activeIndex) {
      setState(() => _activeIndex = newActive);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _scrollToActive(_activeIndex, animate: true);
      });
    }
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

  void _clearSelection() => setState(() { _selected.clear(); _editedLines = null; });

  List<String> _selectedLineTexts() {
    if (_editedLines != null && _editedLines!.isNotEmpty) {
      return _editedLines!;
    }
    final indices = _selected.toList()..sort();
    return [for (final i in indices) widget.lines[i].text];
  }

  List<Color> _currentColors() =>
      ref
          .read(albumColorsProvider(widget.song.localArtworkPath))
          .valueOrNull ??
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not share: $e')),
        );
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
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
              ),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(
              [for (final c in controllers) c.text],
            ),
            child: const Text('Done'),
          ),
        ],
      ),
    );
    for (final c in controllers) { c.dispose(); }
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Saved to Photos')),
        );
        _clearSelection();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save: $e')),
        );
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
    final tops = <double>[];
    var cursor = 0.0;
    for (final line in widget.lines) {
      tops.add(cursor);
      final text = line.text.isEmpty ? '♪' : line.text;
      final tp = TextPainter(
        text: TextSpan(text: text, style: _lineStyle),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: textWidth);
      cursor += tp.size.height + _rowPaddingY;
      tp.dispose();
    }
    _lineTops = tops;
    _measuredWidth = contentWidth;
  }

  /// Scroll offset that places the [index]th line at ~38 % of the
  /// viewport. Uses the precomputed per-line heights — exact, no
  /// drift across long songs / wrapped lines.
  double _offsetForLine(int index, double viewportHeight) {
    if (index < 0 || index >= _lineTops.length) return 0;
    final topPad = viewportHeight * 0.26;
    final lineTop = topPad + _lineTops[index];
    return (lineTop - viewportHeight * 0.38).clamp(0.0, double.infinity);
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
    final target = _offsetForLine(index, viewportHeight).clamp(
      _scroll.position.minScrollExtent,
      _scroll.position.maxScrollExtent,
    );
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
    final estimate = _offsetForLine(index, viewportHeight).clamp(
      _scroll.position.minScrollExtent,
      _scroll.position.maxScrollExtent,
    );
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
    if (n is UserScrollNotification &&
        n.direction != ScrollDirection.idle) {
      _lastUserScrollAt = DateTime.now();
    }
    return false;
  }

  /// Time at which the active line ends — i.e. when the next line starts,
  /// or the song duration if it's the last line, or +4s as a fallback.
  Duration _lineEnd(int index, Duration songDuration) {
    if (index + 1 < widget.lines.length) {
      return widget.lines[index + 1].time;
    }
    if (songDuration > widget.lines[index].time) return songDuration;
    return widget.lines[index].time + const Duration(seconds: 4);
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
      if ((_posNotifier.value - pos).inMilliseconds.abs() > 250) {
        _posNotifier.value = pos;
      }
    });
    ref.listen<AsyncValue<PlayerSnapshot>>(playerStateStreamProvider,
        (_, next) {
      _isPlaying = next.valueOrNull?.playing ?? false;
    });
    ref.listen<AsyncValue<Duration?>>(playerDurationProvider, (_, next) {
      _songDuration = next.valueOrNull ?? _songDuration;
    });

    // Seed once from a synchronous read so the first frame has values.
    // `ref.listen` only fires on subsequent emissions.
    if (!_providersSeeded) {
      _providersSeeded = true;
      _streamPos =
          ref.read(playerPositionProvider).valueOrNull ?? Duration.zero;
      _streamPosAt = DateTime.now();
      _posNotifier.value = _streamPos;
      _isPlaying =
          ref.read(playerStateStreamProvider).valueOrNull?.playing ?? false;
      _songDuration =
          ref.read(playerDurationProvider).valueOrNull ?? Duration.zero;
    }
    final songDuration = _songDuration;

    if (!_initialScrollDone && _activeIndex >= 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _initialScrollDone) return;
        _initialJumpTo(_activeIndex);
      });
    }

    final mqSize = MediaQuery.sizeOf(context);
    final viewportHeight = mqSize.height;
    final lines = widget.lines;

    // Measure once per (lines, content-width). Content width matches the
    // ListView's horizontal padding: 18 left + 50 right.
    _ensureMeasured(mqSize.width - 18 - 50);

    return Stack(
      children: [
        Column(
          children: [
            _Header(song: widget.song),
            Expanded(
              child: NotificationListener<ScrollNotification>(
                onNotification: _onScrollNotification,
                child: ListView.builder(
                  controller: _scroll,
                  // Asymmetric horizontal padding — left edge sits close
                  // to the screen edge so the active line's `_activeScale`
                  // (~1.22) can grow rightward without bleeding into the
                  // gutter. Right padding is generous for the same reason.
                  padding: EdgeInsets.fromLTRB(
                    18, viewportHeight * 0.26, 50, viewportHeight * 0.32,
                  ),
                  itemCount: lines.length,
                  itemBuilder: (context, i) {
                  final line = lines[i];
                  final isActive = i == _activeIndex;
                  final isPast = i < _activeIndex;
                  final isSelected = _selected.contains(i);
                  final lineEnd =
                      isActive ? _lineEnd(i, songDuration) : Duration.zero;
                  // ListView.builder automatically adds RepaintBoundaries
                  // around each item (addRepaintBoundaries: true). Wrapping
                  // again is redundant and adds layer overhead. GlobalKeys
                  // were dropped too — _scrollToActive uses an offset
                  // estimate now, which keeps the BuildOwner free of
                  // hundreds of registered keys.
                  return _LyricLineRow(
                    text: line.text,
                    isActive: isActive,
                    isPast: isPast,
                    isSelected: isSelected,
                    posNotifier: _posNotifier,
                    start: line.time,
                    end: lineEnd,
                    onTap: () => _onLineTap(i, line.time),
                    onLongPress: () => _onLineLongPress(i),
                  );
                },
                ),
              ),
            ),
          ],
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
      ],
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One lyric line. When [isActive] is true, words inside the line light up
/// as [position] sweeps from [start] to [end] (karaoke). Otherwise the
/// whole line uses a single past/future colour.
class _LyricLineRow extends StatelessWidget {
  const _LyricLineRow({
    required this.text,
    required this.isActive,
    required this.isPast,
    required this.posNotifier,
    required this.start,
    required this.end,
    required this.onTap,
    this.isSelected = false,
    this.onLongPress,
  });

  final String text;
  final bool isActive;
  final bool isPast;
  /// True while the user has this line picked for share-as-image.
  /// Renders a highlight pill behind the text.
  final bool isSelected;
  /// Live playhead position. Per-frame updates flow through this notifier
  /// so only the active line's karaoke text rebuilds — the row itself,
  /// the list, and inactive lines stay stable.
  final ValueListenable<Duration> posNotifier;
  final Duration start;
  final Duration end;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  static const _bright = Colors.white;
  static const _dimActive = Color(0x99FFFFFF); // 60% — un-passed words
  static const _past = Color(0x4DFFFFFF); // 30%
  static const _future = Color(0x8CFFFFFF); // 55%

  // Every line is laid out at `_baseSize` so the wrap is identical
  // whether it's active or not — a 1-line lyric stays 1-line when it
  // takes its turn, a 3-liner stays a 3-liner. The "bigger when
  // active" effect is a Transform.scale, which paints the same laid-out
  // text larger without re-flowing it.
  static const _baseSize = 32.0;
  static const _baseWeight = FontWeight.w800;
  // Modest scale so the active line clearly grows without pushing its
  // right edge past the ListView's right padding (set with this scale
  // in mind).
  static const _activeScale = 1.22;

  @override
  Widget build(BuildContext context) {
    final fallbackColor =
        isPast ? _past : (isActive ? _bright : _future);

    // Per-row widgets are deliberately STATIC (no AnimatedContainer,
    // AnimatedScale, InkWell). The previous build attached an implicit
    // animation controller to every visible row via AnimatedContainer
    // and AnimatedScale; during scroll, each new row instantiated two
    // controllers and disposed them on exit, plus an InkWell maintained
    // a Material ripple state. That per-row state churn was the source
    // of the ~20fps scroll on the lyrics page. Active-line transitions
    // now snap instead of easing — the trade-off is intentional.
    final Widget textChild = isActive
        ? _KaraokeText(
            text: text.isEmpty ? '♪' : text,
            posNotifier: posNotifier,
            start: start,
            end: end,
          )
        : Text(text.isEmpty ? '♪' : text);

    Widget styled = DefaultTextStyle(
      style: TextStyle(
        color: fallbackColor,
        fontSize: _baseSize,
        fontWeight: _baseWeight,
        letterSpacing: -0.025 * _baseSize,
        height: 1.12,
      ),
      child: textChild,
    );

    if (isActive) {
      styled = Transform.scale(
        scale: _activeScale,
        alignment: Alignment.centerLeft,
        child: styled,
      );
    }

    Widget content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: styled,
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
    required this.text,
    required this.posNotifier,
    required this.start,
    required this.end,
  });

  final String text;
  final ValueListenable<Duration> posNotifier;
  final Duration start;
  final Duration end;

  @override
  State<_KaraokeText> createState() => _KaraokeTextState();
}

class _KaraokeTextState extends State<_KaraokeText> {
  TextPainter? _tpDim;
  TextPainter? _tpBright;

  // For each word, the rectangles its glyphs occupy in the laid-out
  // text. Usually one rect per word; a word that wraps across visual
  // lines (rare at fontSize 32 with the lyrics' generous padding) gets
  // multiple. Used both as the clip path and to bound the saveLayer of
  // the transitioning word.
  List<List<Rect>> _wordBoxes = const [];

  // Per-word (startProgress, endProgress) within the line — weighted by
  // character count so "the" doesn't get the same time slice as
  // "abracadabra".
  List<(double, double)> _wordRanges = const [];

  // Layout cache key. Re-layout only when one of these changes.
  String? _laidOutText;
  double? _laidOutWidth;
  double? _laidOutFontSize;
  FontWeight? _laidOutWeight;
  double? _laidOutLetterSpacing;
  double? _laidOutHeight;

  void _ensureLayout(TextStyle base, double maxWidth) {
    final text = widget.text.isEmpty ? '♪' : widget.text;
    if (text == _laidOutText &&
        maxWidth == _laidOutWidth &&
        base.fontSize == _laidOutFontSize &&
        base.fontWeight == _laidOutWeight &&
        base.letterSpacing == _laidOutLetterSpacing &&
        base.height == _laidOutHeight) {
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

    // Tokenise into words on whitespace, record char ranges.
    final charRanges = <(int, int)>[];
    var i = 0;
    while (i < text.length) {
      while (i < text.length && _isWhitespace(text.codeUnitAt(i))) {
        i++;
      }
      final wStart = i;
      while (i < text.length && !_isWhitespace(text.codeUnitAt(i))) {
        i++;
      }
      if (i > wStart) charRanges.add((wStart, i));
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

    final totalChars =
        charRanges.fold<int>(0, (a, r) => a + (r.$2 - r.$1));
    if (totalChars == 0) {
      _wordRanges = const [];
    } else {
      final ranges = <(double, double)>[];
      var soFar = 0;
      for (final r in charRanges) {
        final weight = r.$2 - r.$1;
        final startFrac = soFar / totalChars;
        soFar += weight;
        final endFrac = soFar / totalChars;
        ranges.add((startFrac, endFrac));
      }
      _wordRanges = ranges;
    }

    _laidOutText = text;
    _laidOutWidth = maxWidth;
    _laidOutFontSize = base.fontSize;
    _laidOutWeight = base.fontWeight;
    _laidOutLetterSpacing = base.letterSpacing;
    _laidOutHeight = base.height;
  }

  static bool _isWhitespace(int c) =>
      c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D;

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
            start: widget.start,
            end: widget.end,
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
    final elapsed = (posNotifier.value - start)
        .inMilliseconds
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
          Paint()
            ..color = Color.fromRGBO(255, 255, 255, transitioningEased),
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
    return Column(
      children: [
        _Header(song: song),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 34, 24, 100),
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                height: 1.18,
                letterSpacing: -0.8,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _NoLyricsMessage extends StatelessWidget {
  const _NoLyricsMessage({required this.song});
  final SongRow song;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _Header(song: song),
        const Expanded(
          child: Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.lyrics_outlined,
                      size: 64, color: Color(0x99FFFFFF)),
                  SizedBox(height: 16),
                  Text(
                    'No lyrics available',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Drop a matching .lrc into your server\'s lyrics/ folder, '
                    'or run the repair tool — then sync again.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: Color(0xB3FFFFFF),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _NotPlayingMessage extends StatelessWidget {
  const _NotPlayingMessage();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text(
        'Nothing playing.',
        style: TextStyle(color: Colors.white),
      ),
    );
  }
}
