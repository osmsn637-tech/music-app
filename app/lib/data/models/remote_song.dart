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
    );
  }

  String get searchText {
    return [title, artist, album, genre, mood]
        .whereType<String>()
        .join(' ')
        .toLowerCase();
  }
}
