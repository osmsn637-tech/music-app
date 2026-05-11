import 'package:flutter/material.dart';

import '../../data/database/app_database.dart';
import '../theme/app_theme.dart';
import 'album_art.dart';
import 'waveform.dart';

class SongTile extends StatelessWidget {
  const SongTile({
    super.key,
    required this.song,
    this.onTap,
    this.onLongPress,
    this.onFavoriteToggle,
    this.trailing,
    this.isPlaying = false,
    this.showArt = true,
  });

  final SongRow song;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onFavoriteToggle;
  final Widget? trailing;
  final bool isPlaying;
  final bool showArt;

  @override
  Widget build(BuildContext context) {
    final isFav = song.isFavorite == 1;
    final color = isPlaying ? LumenTokens.accent : null;
    final subtitle = [song.artist, song.album]
        .whereType<String>()
        .where((s) => s.isNotEmpty)
        .join(' · ');

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        child: Row(
          children: [
            if (isPlaying)
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: VisualizerBars(color: LumenTokens.accent, height: 14),
              ),
            if (showArt)
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: AlbumArt(
                  artworkPath: song.localArtworkPath,
                  seed: song.id,
                  size: 48,
                  radius: 8,
                ),
              ),
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
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: color,
                    ),
                  ),
                  if (subtitle.isNotEmpty)
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: LumenTokens.fgDim,
                      ),
                    ),
                ],
              ),
            ),
            if (trailing != null)
              trailing!
            else if (onFavoriteToggle != null)
              IconButton(
                icon: Icon(isFav
                    ? Icons.favorite
                    : Icons.more_horiz),
                color: isFav ? LumenTokens.accent : LumenTokens.fgDim,
                onPressed: onFavoriteToggle,
                splashRadius: 20,
              ),
          ],
        ),
      ),
    );
  }
}
