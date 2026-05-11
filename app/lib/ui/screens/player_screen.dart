import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../../features/ai_dj/providers.dart';
import '../../features/library/library_actions.dart';
import '../../features/player/now_playing_controller.dart';
import '../../features/player/providers.dart';
import '../theme/app_theme.dart';
import '../widgets/album_art.dart';
import '../widgets/bloom_background.dart';
import '../widgets/glass.dart';
import '../widgets/mini_player.dart' show miniPlayerArtHeroTag;
import '../widgets/song_actions.dart';
import 'lyrics_screen.dart';

const _playerControlFallbackColor = Color(0xFFFFA08F);

/// Lumen player — iOS 26 redesign.
///
/// Layout (top → bottom):
///   1. Top chrome: chevron-down + centered eyebrow/album + more
///   2. Album art (82% width, 22-radius, breathes 0.86 ↔ 1.0 with play state)
///   3. Title + artist + favorite heart
///   4. Slim white progress bar with elapsed / -remaining (tnum)
///   5. Transport row: shuffle (placeholder) · prev · BIG play · next · repeat
///   6. Niche-cutout bottom bar (glass-strong pill): download · lyrics · sparkle · more
///
/// Bloom background is unchanged from the previous Player — it's a
/// fullscreen blur of the active album art with two slow-drifting
/// pink/violet bloom blobs over a 50% black scrim. Swipe-down dismiss
/// + scale-and-radius shrink during the drag are preserved.
class PlayerScreen extends ConsumerStatefulWidget {
  const PlayerScreen({super.key});

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

String _formatDuration(Duration d) {
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$m:$s';
}

class _PlayerScreenState extends ConsumerState<PlayerScreen>
    with SingleTickerProviderStateMixin {
  /// Live downward-drag offset for swipe-to-dismiss. 0 = at rest. Past a
  /// threshold or with enough downward velocity, the route pops.
  double _dragOffset = 0;
  Color _controlColor = _playerControlFallbackColor;
  String? _controlColorSongId;
  int _colorRequest = 0;
  late final AnimationController _settle;
  Animation<double>? _settleAnim;

  @override
  void initState() {
    super.initState();
    _settle = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    )..addListener(() {
        final a = _settleAnim;
        if (a != null) setState(() => _dragOffset = a.value);
      });
  }

  @override
  void dispose() {
    _settle.dispose();
    super.dispose();
  }

  void _onDragUpdate(DragUpdateDetails d) {
    setState(() {
      _dragOffset = (_dragOffset + d.delta.dy).clamp(0.0, double.infinity);
    });
  }

  Future<void> _onDragEnd(DragEndDetails d) async {
    final v = d.velocity.pixelsPerSecond.dy;
    final h = MediaQuery.of(context).size.height;
    if (_dragOffset > h * 0.18 || v > 800) {
      if (mounted) Navigator.of(context).maybePop();
      return;
    }
    _settleAnim = Tween<double>(begin: _dragOffset, end: 0).animate(
      CurvedAnimation(parent: _settle, curve: Curves.easeOutCubic),
    );
    _settle.value = 0;
    await _settle.forward();
  }

  Future<void> _loadControlColor(String songId, String? artworkPath) async {
    final request = ++_colorRequest;
    final color = await _extractArtworkColor(artworkPath);
    if (!mounted || request != _colorRequest) return;
    setState(() => _controlColor = color);
  }

  Future<Color> _extractArtworkColor(String? artworkPath) async {
    if (artworkPath == null) return _playerControlFallbackColor;
    final file = File(artworkPath);
    if (!file.existsSync()) return _playerControlFallbackColor;
    try {
      final bytes = await file.readAsBytes();
      final codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: 24,
        targetHeight: 24,
      );
      final frame = await codec.getNextFrame();
      final data = await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) return _playerControlFallbackColor;

      Color best = _playerControlFallbackColor;
      var bestScore = -1.0;
      for (var i = 0; i < data.lengthInBytes; i += 4) {
        final alpha = data.getUint8(i + 3);
        if (alpha < 200) continue;
        final color = Color.fromARGB(
          alpha,
          data.getUint8(i),
          data.getUint8(i + 1),
          data.getUint8(i + 2),
        );
        final hsl = HSLColor.fromColor(color);
        final saturation = hsl.saturation;
        final lightness = hsl.lightness;
        if (lightness < 0.14 || lightness > 0.92) continue;
        final score = saturation * 0.70 + (1 - (lightness - 0.58).abs()) * 0.30;
        if (score > bestScore) {
          bestScore = score;
          best = hsl
              .withSaturation(saturation.clamp(0.50, 0.88))
              .withLightness(lightness.clamp(0.58, 0.74))
              .toColor();
        }
      }
      return best;
    } catch (_) {
      return _playerControlFallbackColor;
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.read(nowPlayingProvider.notifier);
    final song = ref.watch(nowPlayingProvider);
    final state = ref.watch(playerStateStreamProvider);

    final isPlaying = state.valueOrNull?.playing ?? false;
    final processing = state.valueOrNull?.processingState;

    final djQueue = ref.watch(aiDjQueueControllerProvider);
    final djActive = djQueue.isActive;
    final hasPrev = djActive
        ? djQueue.currentIndex > 0
        : controller.hasPrev;
    final hasNext = djActive
        ? djQueue.currentIndex + 1 < djQueue.queue.length
        : controller.hasNext;

    if (song == null) {
      return const Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(child: Text('Nothing playing.')),
      );
    }

    if (_controlColorSongId != song.id) {
      _controlColorSongId = song.id;
      _controlColor = _playerControlFallbackColor;
      _loadControlColor(song.id, song.localArtworkPath);
    }

    final h = MediaQuery.of(context).size.height;
    final progress = (_dragOffset / (h * 0.5)).clamp(0.0, 1.0);
    final scale = 1.0 - 0.05 * progress;
    final radius = 28.0 * progress;

    return Scaffold(
      // Solid black bg so the player itself is never see-through. The
      // route is still `opaque: false` (see openPlayerRoute) so the
      // page below stays mounted and reveals as the player drags down.
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onVerticalDragUpdate: _onDragUpdate,
        onVerticalDragEnd: _onDragEnd,
        child: Transform.translate(
          offset: Offset(0, _dragOffset),
          child: Transform.scale(
            scale: scale,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(radius),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Art-bloom background — heavily blurred fullscreen artwork.
                  Positioned.fill(child: BloomBackground(song: song)),
                  SafeArea(
                    child: Material(
                      type: MaterialType.transparency,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(22, 8, 22, 18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // ─── Top chrome ─────────────────────────
                            Row(
                              children: [
                                _IconCircle(
                                  icon: Icons.keyboard_arrow_down,
                                  onTap: () =>
                                      Navigator.of(context).maybePop(),
                                ),
                                Expanded(
                                  child: Column(
                                    children: [
                                      Text(
                                        'PLAYING ${song.album != null ? "FROM ALBUM" : "OFFLINE"}',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 0.5,
                                          color: Colors.white
                                              .withValues(alpha: 0.55),
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        song.album ?? song.artist ?? '',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                _IconCircle(
                                  icon: Icons.more_horiz,
                                  onTap: () =>
                                      SongActionsSheet.show(context, song),
                                ),
                              ],
                            ),

                            // ─── Album art (breathes with play state) ──
                            const SizedBox(height: 22),
                            Expanded(
                              child: Center(
                                child: SingleChildScrollView(
                                  physics: const NeverScrollableScrollPhysics(),
                                  child: ConstrainedBox(
                                    constraints:
                                        const BoxConstraints(maxWidth: 370),
                                    child: Glass(
                                      borderRadius: LumenTokens.rXl,
                                      padding: const EdgeInsets.all(18),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          AspectRatio(
                                            aspectRatio: 1,
                                            child: AnimatedScale(
                                              scale: isPlaying ? 1.0 : 0.94,
                                              duration: LumenTokens.dSlow,
                                              curve: LumenTokens.easeOut,
                                              child: Hero(
                                                tag: miniPlayerArtHeroTag(song.id),
                                                flightShuttleBuilder: (
                                                  _,
                                                  animation,
                                                  _,
                                                  _,
                                                  _,
                                                ) {
                                                  // Lerp corner radius mini (12)
                                                  // → full (22) so artwork doesn't
                                                  // snap shape mid-flight.
                                                  return AnimatedBuilder(
                                                    animation: animation,
                                                    builder: (_, _) {
                                                      final r = 12.0 +
                                                          (LumenTokens.rXl -
                                                                  12.0) *
                                                              animation.value;
                                                      return AspectRatio(
                                                        aspectRatio: 1,
                                                        child: AlbumArt(
                                                          artworkPath: song
                                                              .localArtworkPath,
                                                          seed: song.id,
                                                          size: double.infinity,
                                                          radius: r,
                                                        ),
                                                      );
                                                    },
                                                  );
                                                },
                                                child: AlbumArt(
                                                  artworkPath:
                                                      song.localArtworkPath,
                                                  seed: song.id,
                                                  size: double.infinity,
                                                  radius: LumenTokens.rLg,
                                                ),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 22),
                                          Text(
                                            song.title,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 30,
                                              fontWeight: FontWeight.w900,
                                              letterSpacing: -0.8,
                                              height: 1.08,
                                              color: Colors.white,
                                            ),
                                          ),
                                          const SizedBox(height: 12),
                                          Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  song.artist ??
                                                      'Unknown artist',
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.w600,
                                                    color: Colors.white
                                                        .withValues(alpha: 0.72),
                                                  ),
                                                ),
                                              ),
                                              IconButton(
                                                iconSize: 30,
                                                color: Colors.white
                                                    .withValues(alpha: 0.76),
                                                onPressed: () => ref
                                                    .read(libraryActionsProvider)
                                                    .toggleFavorite(song),
                                                icon: Icon(song.isFavorite == 1
                                                    ? Icons.favorite
                                                    : Icons.favorite_border),
                                              ),
                                              IconButton(
                                                iconSize: 28,
                                                color: Colors.white
                                                    .withValues(alpha: 0.58),
                                                onPressed: () =>
                                                    SongActionsSheet.show(
                                                        context, song),
                                                icon: const Icon(
                                                    Icons.more_vert_rounded),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),

                            // ─── Title row + favorite ───────────────
                            const SizedBox(height: 22),

                            // ─── Progress + tnum time labels ────────
                            const _ProgressBar(),
                            const SizedBox(height: 14),

                            // ─── Transport row ──────────────────────
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                IconButton(
                                  iconSize: 62,
                                  color: _controlColor,
                                  disabledColor:
                                      Colors.white.withValues(alpha: 0.20),
                                  onPressed: hasPrev
                                      ? () {
                                          if (djActive) {
                                            ref
                                                .read(
                                                    aiDjQueueControllerProvider
                                                        .notifier)
                                                .playAt(
                                                    djQueue.currentIndex - 1);
                                          } else {
                                            controller.previous();
                                          }
                                        }
                                      : null,
                                  icon: const Icon(Icons.fast_rewind_rounded),
                                ),
                                const SizedBox(width: 26),
                                _BigPlayButton(
                                  isPlaying: isPlaying,
                                  loading:
                                      processing == ProcessingState.loading,
                                  color: _controlColor,
                                  onTap: () async {
                                    if (isPlaying) {
                                      await controller.pause();
                                    } else {
                                      await controller.resume();
                                    }
                                  },
                                ),
                                const SizedBox(width: 26),
                                IconButton(
                                  iconSize: 62,
                                  color: _controlColor,
                                  disabledColor:
                                      Colors.white.withValues(alpha: 0.20),
                                  onPressed: hasNext
                                      ? () {
                                          if (djActive) {
                                            ref
                                                .read(
                                                    aiDjQueueControllerProvider
                                                        .notifier)
                                                .skip();
                                          } else {
                                            controller.next();
                                          }
                                        }
                                      : null,
                                  icon: const Icon(Icons.fast_forward_rounded),
                                ),
                              ],
                            ),
                            const SizedBox(height: 28),

                            // ─── Niche-cutout glass bar ─────────────
                            _NicheBar(
                              accentColor: _controlColor,
                              onLyrics: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const LyricsScreen(),
                                ),
                              ),
                              onMore: () =>
                                  SongActionsSheet.show(context, song),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _IconCircle extends StatelessWidget {
  const _IconCircle({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(LumenTokens.rPill),
        onTap: onTap,
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: 0.12),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.10),
            ),
          ),
          child: Icon(
            icon,
            size: 18,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

class _BigPlayButton extends StatelessWidget {
  const _BigPlayButton(
      {required this.isPlaying,
      required this.loading,
      required this.color,
      required this.onTap});
  final bool isPlaying;
  final bool loading;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(LumenTokens.rPill),
        onTap: onTap,
        child: SizedBox(
          width: 74,
          height: 74,
          child: Center(
            child: loading
                ? const Icon(
                    Icons.hourglass_top_rounded,
                    size: 48,
                    color: _playerControlFallbackColor,
                  )
                : Icon(
                    isPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    size: 74,
                    color: color,
                  ),
          ),
        ),
      ),
    );
  }
}

/// Niche bar: glass-strong pill with 4 evenly-spaced action glyphs.
/// Sits below the transport row; the sparkle gets pink ink so the
/// AI/DJ jump is always visually distinct.
class _NicheBar extends StatelessWidget {
  const _NicheBar({
    required this.accentColor,
    required this.onLyrics,
    required this.onMore,
  });

  final Color accentColor;
  final VoidCallback onLyrics;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _NicheGlyph(
          icon: Icons.tune_rounded,
          onTap: null,
        ),
        const SizedBox(width: 18),
        Expanded(
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(LumenTokens.rPill),
            child: InkWell(
              borderRadius: BorderRadius.circular(LumenTokens.rPill),
              onTap: onLyrics,
              child: Glass(
                borderRadius: LumenTokens.rPill,
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: Text(
                    'Lyrics',
                    style: TextStyle(
                      color: accentColor,
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 18),
        _NicheGlyph(
          icon: Icons.queue_music_rounded,
          onTap: onMore,
        ),
      ],
    );
  }
}

class _NicheGlyph extends StatelessWidget {
  const _NicheGlyph({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(LumenTokens.rPill),
            onTap: onTap,
            child: Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.08),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.10),
                ),
              ),
              child: Center(
                child: Icon(
                  icon,
                  size: 28,
                  color: Colors.white.withValues(alpha: onTap == null ? 0.36 : 0.82),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Slider + elapsed/remaining labels. Self-contained Consumer so the rest
/// of the player screen doesn't rebuild on every position tick.
class _ProgressBar extends ConsumerWidget {
  const _ProgressBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final position =
        ref.watch(playerPositionProvider).valueOrNull ?? Duration.zero;
    final duration =
        ref.watch(playerDurationProvider).valueOrNull ?? Duration.zero;
    final hasDuration = duration > Duration.zero;
    final maxMs =
        duration.inMilliseconds.toDouble().clamp(1.0, double.infinity);
    final valueMs = position.inMilliseconds
        .clamp(0, duration.inMilliseconds)
        .toDouble();

    return Column(
      children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: Colors.white.withValues(alpha: 0.85),
            inactiveTrackColor: Colors.white.withValues(alpha: 0.18),
            thumbColor: Colors.white,
            trackHeight: 4,
            thumbShape:
                const RoundSliderThumbShape(enabledThumbRadius: 6),
            overlayShape:
                const RoundSliderOverlayShape(overlayRadius: 14),
          ),
          child: Slider(
            min: 0,
            max: maxMs,
            value: valueMs,
            onChanged: hasDuration
                ? (v) => ref
                    .read(nowPlayingProvider.notifier)
                    .seek(Duration(milliseconds: v.toInt()))
                : null,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _formatDuration(position),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withValues(alpha: 0.6),
                  fontFeatures: LumenTokens.tnum,
                ),
              ),
              Text(
                '-${_formatDuration(duration - position)}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withValues(alpha: 0.6),
                  fontFeatures: LumenTokens.tnum,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
