import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
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
import '../../features/player/providers.dart';
import '../widgets/bloom_background.dart';

/// Apple-Music-style lyrics view.
///
///  - Background is the same blurred-artwork bloom as the Player.
///  - Active line is large bold white; past lines fade. Inside the active
///    line, each word lights up as the song reaches it (karaoke).
///  - The view jumps to the current line on open (no scroll-from-top).
///  - Tap any line to seek to that timestamp.
class LyricsScreen extends ConsumerWidget {
  const LyricsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final song = ref.watch(nowPlayingProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (song != null) BloomBackground(song: song, darkenStrength: 1.4),
          SafeArea(
            child: Material(
              type: MaterialType.transparency,
              child: song == null
                  ? const _NotPlayingMessage()
                  : ref.watch(lyricsForSongProvider(song)).when(
                        loading: () =>
                            const Center(child: CircularProgressIndicator()),
                        error: (e, _) =>
                            Center(child: Text('Error loading lyrics: $e')),
                        data: (result) {
                          switch (result.kind) {
                            case LyricsKind.synced:
                              return _SyncedLyricsView(
                                song: song,
                                lines: result.lines,
                              );
                            case LyricsKind.plain:
                              return _PlainLyricsView(
                                song: song,
                                text: result.plainText!,
                              );
                            case LyricsKind.none:
                              return _NoLyricsMessage(song: song);
                          }
                        },
                      ),
            ),
          ),
        ],
      ),
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
  final _itemKeys = <GlobalKey>[];
  int _activeIndex = -1;
  bool _initialScrollDone = false;

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
  final ValueNotifier<Duration> _posNotifier =
      ValueNotifier<Duration>(Duration.zero);

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
    _itemKeys
      ..clear()
      ..addAll(List.generate(widget.lines.length, (_) => GlobalKey()));
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
    if (old.lines.length != widget.lines.length) {
      _itemKeys
        ..clear()
        ..addAll(List.generate(widget.lines.length, (_) => GlobalKey()));
      _initialScrollDone = false;
      _activeIndex = -1;
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

  /// Estimate the offset of the [index]th line using an assumed line
  /// height. Used for the initial jump so the GlobalKey for the line is
  /// likely to have been built by the time we recompute precisely.
  double _estimateOffset(int index, double viewportHeight) {
    const avgLineHeight = 98.0;
    final activeLift = 16.0;
    final topPad = viewportHeight * 0.25;
    final lineTop = topPad + index * avgLineHeight + activeLift;
    return (lineTop - viewportHeight * 0.38).clamp(0.0, double.infinity);
  }

  /// Precisely scroll the [index]th line to ~38% of viewport height.
  /// Returns true if the line had been built and the scroll was applied.
  bool _scrollToActive(int index, {required bool animate}) {
    if (!_scroll.hasClients) return false;
    if (index < 0 || index >= _itemKeys.length) return false;
    final keyCtx = _itemKeys[index].currentContext;
    if (keyCtx == null) return false;
    final box = keyCtx.findRenderObject() as RenderBox?;
    if (box == null) return false;
    final scrollViewBox = _scroll.position.context.notificationContext
        ?.findRenderObject() as RenderBox?;
    if (scrollViewBox == null) return false;
    final offsetWithinViewport =
        box.localToGlobal(Offset.zero, ancestor: scrollViewBox).dy;
    final viewportHeight = _scroll.position.viewportDimension;
    final delta = offsetWithinViewport - viewportHeight * 0.38;
    final target = (_scroll.offset + delta).clamp(
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

  /// Two-pass jump used on first build. The first jump uses an estimated
  /// offset to put the active line near the viewport (which forces the
  /// ListView.builder to instantiate it), then the second jump fine-tunes
  /// using its real measured position.
  void _initialJumpTo(int index) {
    if (!_scroll.hasClients) return;
    final viewportHeight = _scroll.position.viewportDimension;
    final estimate = _estimateOffset(index, viewportHeight).clamp(
      _scroll.position.minScrollExtent,
      _scroll.position.maxScrollExtent,
    );
    _scroll.jumpTo(estimate);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _scrollToActive(index, animate: false);
      _initialScrollDone = true;
    });
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
    // Build runs only when stream pos / play state / duration changes (a
    // few times per second from just_audio) or when _activeIndex moves.
    // Per-frame karaoke updates flow through _posNotifier and never
    // rebuild the list.
    final streamPos =
        ref.watch(playerPositionProvider).valueOrNull ?? Duration.zero;
    final playerState = ref.watch(playerStateStreamProvider).valueOrNull;
    final isPlaying = playerState?.playing ?? false;
    final songDuration =
        ref.watch(playerDurationProvider).valueOrNull ?? Duration.zero;

    if (streamPos != _streamPos) {
      _streamPos = streamPos;
      _streamPosAt = DateTime.now();
      // Snap notifier if we drifted far (e.g., user just seeked).
      if ((_posNotifier.value - streamPos).inMilliseconds.abs() > 250) {
        _posNotifier.value = streamPos;
      }
    }
    _isPlaying = isPlaying;

    if (!_initialScrollDone && _activeIndex >= 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _initialScrollDone) return;
        _initialJumpTo(_activeIndex);
      });
    }

    final viewportHeight = MediaQuery.of(context).size.height;
    final lines = widget.lines;

    return Stack(
      children: [
        Column(
          children: [
            _Header(song: widget.song),
            Expanded(
              child: ListView.builder(
                controller: _scroll,
                // Asymmetric horizontal padding — left edge sits closer
                // to the screen edge so the active line's 1.18x scale
                // doesn't push the right edge into the gutter.
                padding: EdgeInsets.fromLTRB(
                  18, viewportHeight * 0.26, 30, viewportHeight * 0.32,
                ),
                itemCount: lines.length,
                itemBuilder: (context, i) {
                  final line = lines[i];
                  final isActive = i == _activeIndex;
                  final isPast = i < _activeIndex;
                  final isSelected = _selected.contains(i);
                  final lineEnd =
                      isActive ? _lineEnd(i, songDuration) : Duration.zero;
                  return RepaintBoundary(
                    child: KeyedSubtree(
                      key: _itemKeys[i],
                      child: _LyricLineRow(
                        text: line.text,
                        isActive: isActive,
                        isPast: isPast,
                        isSelected: isSelected,
                        posNotifier: _posNotifier,
                        start: line.time,
                        end: lineEnd,
                        onTap: () => _onLineTap(i, line.time),
                        onLongPress: () => _onLineLongPress(i),
                      ),
                    ),
                  );
                },
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

  @override
  Widget build(BuildContext context) {
    final fallbackColor =
        isPast ? _past : (isActive ? _bright : _future);
    final baseSize = isActive ? 34.0 : 30.0;
    final fallbackWeight = isActive ? FontWeight.w900 : FontWeight.w800;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        onLongPress: onLongPress,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: isSelected
                ? Colors.white.withValues(alpha: 0.16)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(18),
          ),
          child: AnimatedScale(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment.centerLeft,
            // Active stays at natural width (1.0) so a long lyric never
            // overflows the right edge; the "bigger" feel comes from the
            // inactive lines shrinking around it.
            scale: isActive ? 1.0 : 0.92,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                style: TextStyle(
                  color: fallbackColor,
                  fontSize: baseSize,
                  fontWeight: fallbackWeight,
                  letterSpacing: -0.9,
                  height: 1.12,
                ),
                child: isActive
                    ? _KaraokeText(
                        text: text.isEmpty ? '♪' : text,
                        posNotifier: posNotifier,
                        start: start,
                        end: end,
                      )
                    : Text(text.isEmpty ? '♪' : text),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The active line's text, with each word's colour eased from dim to bright
/// as the playhead moves through the line. Word durations are weighted by
/// character count so short connectives don't get the same time as long
/// words.
class _KaraokeText extends StatelessWidget {
  _KaraokeText({
    required this.text,
    required this.posNotifier,
    required this.start,
    required this.end,
  })  : _words = _splitWords(text),
        _wordRanges = _computeRanges(_splitWords(text));

  final String text;
  final ValueListenable<Duration> posNotifier;
  final Duration start;
  final Duration end;

  // Cached once per build of this widget — splitting + range math is
  // pure on the text, so doing it every frame would burn cycles for
  // nothing. The ValueListenableBuilder below only re-runs the colour
  // interpolation each tick.
  final List<String> _words;
  final List<(double, double)> _wordRanges;

  static List<String> _splitWords(String s) =>
      s.split(RegExp(r'\s+'));

  static List<(double, double)> _computeRanges(List<String> words) {
    final totalChars =
        words.fold<int>(0, (a, w) => a + (w.isEmpty ? 1 : w.length));
    final out = <(double, double)>[];
    var charsSoFar = 0;
    for (final w in words) {
      final weight = w.isEmpty ? 1 : w.length;
      final s = charsSoFar / totalChars;
      charsSoFar += weight;
      final e = charsSoFar / totalChars;
      out.add((s, e));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final base = DefaultTextStyle.of(context).style;
    if (_words.length <= 1) {
      // Single-word lines have nothing to interpolate inside.
      return Text(text);
    }
    final spanMs = end > start ? (end - start).inMilliseconds : 1;

    return ValueListenableBuilder<Duration>(
      valueListenable: posNotifier,
      builder: (context, position, _) {
        final elapsed =
            (position - start).inMilliseconds.clamp(0, spanMs).toDouble();
        final progress = elapsed / spanMs;

        final spans = <InlineSpan>[];
        for (var i = 0; i < _words.length; i++) {
          final (wordStart, wordEnd) = _wordRanges[i];
          final t = wordEnd == wordStart
              ? 1.0
              : ((progress - wordStart) / (wordEnd - wordStart))
                  .clamp(0.0, 1.0);
          final color = Color.lerp(
            _LyricLineRow._dimActive,
            _LyricLineRow._bright,
            Curves.easeOut.transform(t),
          )!;
          spans.add(TextSpan(text: _words[i], style: TextStyle(color: color)));
          if (i < _words.length - 1) {
            spans.add(const TextSpan(text: ' '));
          }
        }

        return Text.rich(
          TextSpan(style: base, children: spans),
          textAlign: TextAlign.left,
        );
      },
    );
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
