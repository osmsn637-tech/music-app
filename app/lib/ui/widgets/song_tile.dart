import 'package:flutter/material.dart';

import '../../data/database/app_database.dart';
import '../screens/entity_nav.dart';
import '../theme/app_theme.dart';
import 'album_art.dart';
import 'explicit_badge.dart';
import 'tempo_sheet.dart';
import 'waveform.dart';

class SongTile extends StatelessWidget {
  const SongTile({
    super.key,
    required this.song,
    this.onTap,
    this.onLongPress,
    this.onMore,
    this.onFavoriteToggle,
    this.trailing,
    this.isPlaying = false,
    this.showArt = true,
    this.linkEntities = true,
  });

  final SongRow song;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// Opens the actions ("…") sheet. Shown as a tap target so it works on
  /// desktop (where long-press isn't available) as well as touch.
  final VoidCallback? onMore;
  final VoidCallback? onFavoriteToggle;
  final Widget? trailing;
  final bool isPlaying;
  final bool showArt;

  /// When true, the artist and album names in the subtitle become tappable
  /// links to their detail pages. Off on the artist/album pages themselves
  /// (you're already there) and in pickers where a stray tap shouldn't
  /// navigate away.
  final bool linkEntities;

  @override
  Widget build(BuildContext context) {
    final isFav = song.isFavorite == 1;
    final color = isPlaying ? LumenTokens.accent : null;
    final artist = song.artist;
    final album = song.album;
    final hasArtist = artist != null && artist.isNotEmpty;
    final hasAlbum = album != null && album.isNotEmpty;
    final subStyle = TextStyle(
      fontSize: 13,
      color: LumenTokens.fgDimOf(context),
    );

    Widget linkText(String text, VoidCallback onTap) => GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: subStyle,
      ),
    );

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
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          song.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: color,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      const ExplicitBadge(),
                    ],
                  ),
                  if (hasArtist || hasAlbum)
                    (linkEntities
                        ? Row(
                            children: [
                              if (hasArtist)
                                Flexible(
                                  child: linkText(
                                    artist,
                                    () => openArtist(context, artist),
                                  ),
                                ),
                              if (hasArtist && hasAlbum)
                                Text(' · ', style: subStyle),
                              if (hasAlbum)
                                Flexible(
                                  child: linkText(
                                    album,
                                    () => openAlbum(context, album),
                                  ),
                                ),
                            ],
                          )
                        : Text(
                            [artist, album]
                                .whereType<String>()
                                .where((s) => s.isNotEmpty)
                                .join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: subStyle,
                          )),
                  // ↑/↓ + BPM under the name when this song's tempo is changed.
                  TempoBadge(song: song),
                ],
              ),
            ),
            if (trailing != null)
              trailing!
            else if (onFavoriteToggle != null || onMore != null)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (onFavoriteToggle != null)
                    IconButton(
                      icon: AnimatedSwitcher(
                        duration: LumenTokens.mBase,
                        switchInCurve: LumenTokens.lumenOvershoot,
                        transitionBuilder: (child, anim) =>
                            ScaleTransition(scale: anim, child: child),
                        child: Icon(
                          isFav ? Icons.favorite : Icons.favorite_border,
                          key: ValueKey(isFav),
                          color: isFav
                              ? LumenTokens.accent
                              : LumenTokens.fgDimOf(context),
                        ),
                      ),
                      onPressed: onFavoriteToggle,
                      splashRadius: 20,
                    ),
                  if (onMore != null)
                    IconButton(
                      icon: Icon(
                        Icons.more_horiz,
                        color: LumenTokens.fgDimOf(context),
                      ),
                      onPressed: onMore,
                      splashRadius: 20,
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
