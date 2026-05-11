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
            width: 1080,
            height: 1080,
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
    // Diagonal gradient sourced from the album palette — top-left in the
    // dominant color, bottom-right in a darker shade of the secondary,
    // for depth without competing with the lyrics on top.
    final raw = colors.isNotEmpty ? colors.first : const Color(0xFF14161A);
    final secondary = colors.length > 1 ? colors[1] : raw;
    final topColor = Color.lerp(raw, Colors.black, 0.10) ?? raw;
    final bottomColor =
        Color.lerp(secondary, Colors.black, 0.55) ?? Colors.black;

    final lineCount = lines.length;
    final lyricSize = lineCount <= 1
        ? 104.0
        : lineCount == 2
            ? 92.0
            : lineCount == 3
                ? 80.0
                : 68.0;

    return Container(
      width: 1080,
      height: 1080,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [topColor, bottomColor],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(72, 72, 72, 64),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header — big square art on the left, title + artist stacked.
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: AlbumArt(
                    artworkPath: song.localArtworkPath,
                    seed: song.id,
                    size: 200,
                    radius: 0,
                  ),
                ),
                const SizedBox(width: 28),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        song.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 44,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.8,
                          height: 1.05,
                        ),
                      ),
                      if (song.artist != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          song.artist!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.78),
                            fontSize: 28,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.3,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 56),
            // Lyrics — bold white, left-aligned, generous spacing. Sized
            // by line count so 1 line lands big and 4 lines still fit.
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (final line in lines)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 18),
                      child: Text(
                        line,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: lyricSize,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -1.2,
                          height: 1.14,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            // Footer pill — subtle "lyrics" attribution.
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18, vertical: 9),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.music_note,
                          color: Colors.white, size: 22),
                      const SizedBox(width: 6),
                      Text(
                        'lyrics',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.95),
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
