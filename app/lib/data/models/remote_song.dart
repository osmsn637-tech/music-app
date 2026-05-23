class RemoteSong {
  const RemoteSong({
    required this.id,
    required this.title,
    required this.fileName,
    required this.audioUrl,
    this.artist,
    this.album,
    this.genre,
    this.mood,
    this.bpm,
    this.durationMs,
    this.lyricsUrl,
    this.artworkUrl,
    this.lyricsSize,
    this.artworkSize,
  });

  final String id;
  final String title;
  final String? artist;
  final String? album;
  final String? genre;
  final String? mood;
  final int? bpm;
  final int? durationMs;
  final String fileName;
  final String audioUrl;
  final String? lyricsUrl;
  final String? artworkUrl;
  /// Byte size of the server's lyrics file at manifest-generation time.
  /// Used by sync repair to detect "server replaced this file with a
  /// new version" — same URL, different bytes, different size.
  final int? lyricsSize;
  /// Same fingerprint trick for artwork: covers swapped manually on the
  /// server (without a metadata change) get re-downloaded only because
  /// the local file's size no longer matches.
  final int? artworkSize;

  factory RemoteSong.fromJson(Map<String, dynamic> json) {
    return RemoteSong(
      id: json['id'] as String,
      title: json['title'] as String,
      artist: json['artist'] as String?,
      album: json['album'] as String?,
      genre: json['genre'] as String?,
      mood: json['mood'] as String?,
      bpm: (json['bpm'] as num?)?.toInt(),
      durationMs: (json['durationMs'] as num?)?.toInt(),
      fileName: json['fileName'] as String,
      audioUrl: json['audioUrl'] as String,
      lyricsUrl: json['lyricsUrl'] as String?,
      artworkUrl: json['artworkUrl'] as String?,
      lyricsSize: (json['lyricsSize'] as num?)?.toInt(),
      artworkSize: (json['artworkSize'] as num?)?.toInt(),
    );
  }

  String get searchText {
    return [title, artist, album, genre, mood]
        .whereType<String>()
        .join(' ')
        .toLowerCase();
  }
}
