import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:gal/gal.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/utils/album_colors.dart';
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
  // Decode the artwork up front. The card paints the cover as a blurred
  // full-bleed background via Image.file; if it isn't already in the
  // image cache it decodes async and the two end-of-frame waits below
  // capture a blank background. Precaching forces a synchronous paint.
  final artPath = song.localArtworkPath;
  if (context.mounted &&
      artPath != null &&
      artPath.isNotEmpty &&
      File(artPath).existsSync()) {
    try {
      await precacheImage(FileImage(File(artPath)), context);
    } catch (_) {
      // Decode failure → card falls back to the palette gradient.
    }
  }
  if (!context.mounted) {
    throw StateError('context unmounted before lyric-card render');
  }

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
        boundaryKey.currentContext?.findRenderObject()
            as RenderRepaintBoundary?;
    if (boundary == null) {
      throw StateError('lyric-card boundary not mounted');
    }
    final image = await boundary.toImage(pixelRatio: 1.0);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) {
      throw StateError('lyric-card encode returned null');
    }
    return bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes);
  } finally {
    entry.remove();
  }
}

/// Anchor rect for the iOS share popover. iPad REQUIRES a non-null
/// `sharePositionOrigin` or share_plus throws / presents blank; iPhone is
/// more forgiving but Apple still wants one. Derives it from the invoking
/// widget, with a centred-screen fallback so it's never null.
Rect shareOriginFor(BuildContext context) {
  final box = context.findRenderObject() as RenderBox?;
  if (box != null && box.hasSize) {
    return box.localToGlobal(Offset.zero) & box.size;
  }
  final size = MediaQuery.of(context).size;
  return Rect.fromCenter(
    center: Offset(size.width / 2, size.height / 2),
    width: 1,
    height: 1,
  );
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
  // Capture the popover anchor BEFORE any await — the context may unmount
  // (or its render box change) across the async render gap.
  final origin = shareOriginFor(context);
  final png = await _renderLyricCard(
    context: context,
    song: song,
    lines: lines,
    colors: colors,
  );
  final dir = await getTemporaryDirectory();
  final file = File(
    p.join(dir.path, 'lyrics_${DateTime.now().millisecondsSinceEpoch}.png'),
  );
  await file.writeAsBytes(png);
  await Share.shareXFiles(
    [XFile(file.path, mimeType: 'image/png')],
    subject: '${song.title} — ${song.artist ?? ""}'.trim(),
    sharePositionOrigin: origin,
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
    context: context,
    song: song,
    lines: lines,
    colors: colors,
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
    // Background — Apple Music uses the album cover itself, heavily
    // blurred and over-scanned, so the wash carries *every* hue in the
    // art instead of one flat extracted colour. We do the same when
    // artwork is present; otherwise fall back to a vivid palette
    // gradient (still better than a single dull hue, see
    // vibrantFromPalette).
    final artPath = song.localArtworkPath;
    final hasArt =
        artPath != null && artPath.isNotEmpty && File(artPath).existsSync();

    final vivid = AlbumColors.vibrantFromPalette(
      colors,
      fallback: const Color(0xFF7A4FB0),
    );
    final deep = Color.lerp(vivid, Colors.black, 0.74)!;
    final deepest = Color.lerp(vivid, Colors.black, 0.90)!;

    return SizedBox(
      width: _kCanvasWidth,
      height: _kCanvasHeight,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // ─── BACKGROUND WASH ─────────────────────────────────────
          if (hasArt)
            Positioned.fill(
              child: ClipRect(
                child: Transform.scale(
                  // Over-scan ~1.5× so the heavy blur doesn't bleed
                  // transparent edges into the frame.
                  scale: 1.5,
                  child: ImageFiltered(
                    imageFilter: ui.ImageFilter.blur(sigmaX: 80, sigmaY: 80),
                    child: Image.file(
                      File(artPath),
                      fit: BoxFit.cover,
                      width: _kCanvasWidth,
                      height: _kCanvasHeight,
                    ),
                  ),
                ),
              ),
            )
          else
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topRight,
                    end: Alignment.bottomLeft,
                    colors: [deep, deepest],
                  ),
                ),
              ),
            ),
          // Dark scrim — Apple's wash is muted, not bright. Keeps the
          // colours readable behind white text and lifts card contrast.
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.30),
                    Colors.black.withValues(alpha: 0.48),
                  ],
                ),
              ),
            ),
          ),
          // Corner vignette for depth.
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.center,
                  radius: 1.15,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.38),
                  ],
                  stops: const [0.55, 1.0],
                ),
              ),
            ),
          ),
          // The card — vertically centred, ~78 % of canvas width.
          Center(
            child: Padding(
              // (1080 − 840) / 2 = 120 horizontal margin → card is 840 wide.
              padding: const EdgeInsets.symmetric(horizontal: 120),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(44),
                // One unified translucent-glass card (Apple's is a single
                // panel, not two compartments). The card fill is light
                // enough that the vivid bg tints through it. Inside, the
                // lyric lines live in their own brighter glass pill.
                child: Container(
                  decoration: BoxDecoration(
                    // Dark translucent glass over the blurred art — opaque
                    // enough to keep white lyrics crisp, sheer enough that
                    // the art's colour still tints the panel. The card
                    // *is* the glass pill now; no nested box.
                    color: const Color(0xFF111114).withValues(alpha: 0.55),
                    // 1 px white rim — the hairline edge Apple's glass
                    // surfaces always have.
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.12),
                      width: 1,
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ─── LYRICS ──────────────────────────────────────
                      // Sit directly on the card, like Apple — no inner
                      // box. A subtle top-edge highlight catches "light"
                      // on the upper rim of the glass.
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.white.withValues(alpha: 0.07),
                              Colors.transparent,
                            ],
                            stops: const [0, 0.4],
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(50, 54, 50, 24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (var i = 0; i < lines.length; i++) ...[
                                Text(
                                  lines[i],
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 56,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -1.0,
                                    height: 1.2,
                                  ),
                                ),
                                if (i != lines.length - 1)
                                  const SizedBox(height: 30),
                              ],
                            ],
                          ),
                        ),
                      ),
                      // ─── SONG INFO ROW ───────────────────────────────
                      // Sits directly on the card (no hard divider) so the
                      // panel reads as one unified surface like Apple's.
                      Padding(
                        padding: const EdgeInsets.fromLTRB(36, 6, 36, 40),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            AlbumArt(
                              artworkPath: song.localArtworkPath,
                              seed: song.id,
                              size: 150,
                              radius: 14,
                            ),
                            const SizedBox(width: 24),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    song.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: Colors.white.withValues(
                                        alpha: 0.95,
                                      ),
                                      fontSize: 40,
                                      fontWeight: FontWeight.w700,
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
                                      color: Colors.white.withValues(
                                        alpha: 0.6,
                                      ),
                                      fontSize: 34,
                                      fontWeight: FontWeight.w400,
                                      letterSpacing: -0.4,
                                      height: 1.05,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      // Flacko brand mark — wolf-with-
                                      // headphones logo tinted white at
                                      // 55 % to match the dimmer footer.
                                      ColorFiltered(
                                        colorFilter: ColorFilter.mode(
                                          Colors.white.withValues(alpha: 0.55),
                                          BlendMode.srcIn,
                                        ),
                                        child: Image.asset(
                                          'assets/icon/flacko_logo.png',
                                          width: 34,
                                          height: 34,
                                          fit: BoxFit.contain,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        'flacko music',
                                        style: TextStyle(
                                          color: Colors.white.withValues(
                                            alpha: 0.55,
                                          ),
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
