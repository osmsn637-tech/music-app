import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:gal/gal.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/database/app_database.dart';
import '../../ui/widgets/album_art.dart';

/// Output dimensions for the share card. Story-format (9 : 16) so the
/// image drops straight into Instagram / Snapchat / WhatsApp status
/// without cropping — matches the Apple Music share render the user
/// referenced.
const double _kCanvasWidth = 1080;
const double _kCanvasHeight = 1920;

/// Captures the lyric card to PNG bytes. Used by both share + save.
Future<Uint8List> _renderLyricCard({
  required BuildContext context,
  required SongRow song,
  required List<String> lines,
  required List<Color> colors,
}) async {
  final boundaryKey = GlobalKey();
  final overlay = Overlay.of(context, rootOverlay: true);
  final entry = OverlayEntry(
    builder: (_) => Positioned(
      left: -10000,
      top: -10000,
      child: Material(
        type: MaterialType.transparency,
        child: RepaintBoundary(
          key: boundaryKey,
          child: SizedBox(
            width: _kCanvasWidth,
            height: _kCanvasHeight,
            child: _LyricCard(song: song, lines: lines, colors: colors),
          ),
        ),
      ),
    ),
  );
  overlay.insert(entry);

  try {
    // Two end-of-frame waits — first for layout, second for paint.
    await WidgetsBinding.instance.endOfFrame;
    await WidgetsBinding.instance.endOfFrame;

    final boundary =
        boundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) {
      throw StateError('lyric-card boundary not mounted');
    }
    final image = await boundary.toImage(pixelRatio: 1.0);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) {
      throw StateError('lyric-card encode returned null');
    }
    return bytes.buffer.asUint8List(
      bytes.offsetInBytes,
      bytes.lengthInBytes,
    );
  } finally {
    entry.remove();
  }
}

/// Renders an Apple-Music-style lyric card and fires the OS share sheet
/// with the PNG.
Future<void> shareLyricsAsImage({
  required BuildContext context,
  required SongRow song,
  required List<String> lines,
  required List<Color> colors,
}) async {
  if (lines.isEmpty) return;
  final png = await _renderLyricCard(
    context: context, song: song, lines: lines, colors: colors,
  );
  final dir = await getTemporaryDirectory();
  final file = File(p.join(
    dir.path,
    'lyrics_${DateTime.now().millisecondsSinceEpoch}.png',
  ));
  await file.writeAsBytes(png);
  await Share.shareXFiles(
    [XFile(file.path, mimeType: 'image/png')],
    subject: '${song.title} — ${song.artist ?? ""}'.trim(),
  );
}

/// Renders the same card and saves it to the device's Photos / Gallery.
/// Throws if the system denies the photo-library permission.
Future<void> saveLyricsAsImage({
  required BuildContext context,
  required SongRow song,
  required List<String> lines,
  required List<Color> colors,
}) async {
  if (lines.isEmpty) return;
  final png = await _renderLyricCard(
    context: context, song: song, lines: lines, colors: colors,
  );

  // Some Android versions need an explicit access request; ask once and
  // bail with a friendly error if denied.
  final granted = await Gal.hasAccess(toAlbum: false);
  if (!granted) {
    final ok = await Gal.requestAccess(toAlbum: false);
    if (!ok) {
      throw StateError('Photo-library access was denied.');
    }
  }
  await Gal.putImageBytes(png, name: 'lyrics_${song.id}');
}

class _LyricCard extends StatelessWidget {
  const _LyricCard({
    required this.song,
    required this.lines,
    required this.colors,
  });

  final SongRow song;
  final List<String> lines;
  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    // Background gradient — wash from the album palette. Darkened
    // enough to keep the card legible, but lifted compared to the
    // previous near-black so the album hue actually shows through the
    // translucent card. The card's "glass" effect needs colour behind
    // it to tint through — a near-black bg made the glass invisible.
    final base = colors.isNotEmpty ? colors.first : const Color(0xFF1A1A1C);
    final accent = colors.length > 1 ? colors[1] : base;
    final bgTop = Color.lerp(accent, Colors.black, 0.35)!;
    final bgBottom = Color.lerp(base, Colors.black, 0.75)!;

    return Container(
      width: _kCanvasWidth,
      height: _kCanvasHeight,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [bgTop, bgBottom],
        ),
      ),
      child: Stack(
        children: [
          // Soft top-left highlight — a subtle radial light source the
          // Apple Music share card always has in the upper-left quadrant.
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(-0.85, -0.95),
                  radius: 1.2,
                  colors: [
                    Colors.white.withValues(alpha: 0.06),
                    Colors.transparent,
                  ],
                  stops: const [0, 0.55],
                ),
              ),
            ),
          ),
          // The card — vertically centered, 75 % of canvas width.
          Center(
            child: Padding(
              // (1080 − 810) / 2 = 135 horizontal margin → card is 810 wide.
              padding: const EdgeInsets.symmetric(horizontal: 135),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(36),
                // Outer card wrapper. The previous build's BackdropFilter
                // was wasted — it can only blur whatever sits at the same
                // render layer behind it (a smooth gradient) so visually
                // there was nothing to blur. Replaced with two visibly
                // layered inner sections — a lighter top compartment for
                // the lyrics, then a hairline, then a darker bottom
                // compartment for the song info. That layering is what
                // the Apple Music card actually relies on for its glass
                // feel, not a frosted blur.
                child: Container(
                  decoration: BoxDecoration(
                    // Base card fill. Translucent enough that the bg
                    // accent colour tints clearly through.
                    color: const Color(0xFF14141A).withValues(alpha: 0.55),
                    // 1 px white rim — the hairline edge Apple's glass
                    // surfaces always have.
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.12),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ─── TOP COMPARTMENT — LYRICS ────────────────────
                      // Has its own subtle top-edge highlight gradient,
                      // catching "light" on the upper rim of the glass.
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.white.withValues(alpha: 0.10),
                              Colors.transparent,
                            ],
                            stops: const [0, 0.45],
                          ),
                        ),
                        child: Padding(
                          padding:
                              const EdgeInsets.fromLTRB(56, 60, 56, 56),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (var i = 0; i < lines.length; i++) ...[
                                Text(
                                  lines[i],
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 58,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -1.0,
                                    height: 1.15,
                                  ),
                                ),
                                if (i != lines.length - 1)
                                  const SizedBox(height: 40),
                              ],
                            ],
                          ),
                        ),
                      ),
                      // ─── DIVIDER ─────────────────────────────────────
                      // More visible than before (alpha 0.07 → 0.14) so
                      // the seam between compartments actually reads.
                      Container(
                        height: 1,
                        color: Colors.white.withValues(alpha: 0.14),
                      ),
                      // ─── BOTTOM COMPARTMENT — SONG INFO ──────────────
                      // Additional black @ 0.28 fill stacks on top of the
                      // card's base fill, giving this compartment a
                      // visibly darker tone than the lyrics block above.
                      // That's the "two halves" feel.
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.28),
                        ),
                        child: Padding(
                          padding:
                              const EdgeInsets.fromLTRB(48, 36, 48, 48),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              AlbumArt(
                                artworkPath: song.localArtworkPath,
                                seed: song.id,
                                size: 168,
                                radius: 12,
                              ),
                              const SizedBox(width: 26),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      song.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: Colors.white
                                            .withValues(alpha: 0.78),
                                        fontSize: 42,
                                        fontWeight: FontWeight.w600,
                                        letterSpacing: -0.7,
                                        height: 1.05,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      song.artist ?? 'Unknown',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: Colors.white
                                            .withValues(alpha: 0.58),
                                        fontSize: 36,
                                        fontWeight: FontWeight.w400,
                                        letterSpacing: -0.4,
                                        height: 1.05,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        // Flacko brand mark — black wolf-
                                        // with-headphones logo tinted
                                        // white at 58 % alpha to match
                                        // the dimmer footer copy.
                                        ColorFiltered(
                                          colorFilter: ColorFilter.mode(
                                            Colors.white
                                                .withValues(alpha: 0.58),
                                            BlendMode.srcIn,
                                          ),
                                          child: Image.asset(
                                            'assets/icon/flacko_logo.png',
                                            width: 36,
                                            height: 36,
                                            fit: BoxFit.contain,
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          'flacko music',
                                          style: TextStyle(
                                            color: Colors.white
                                                .withValues(alpha: 0.58),
                                            fontSize: 26,
                                            fontWeight: FontWeight.w500,
                                            letterSpacing: -0.2,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
