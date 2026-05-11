class RemoteArtist {
  const RemoteArtist({
    required this.id,
    required this.name,
    required this.imageUrl,
  });

  /// Stable, normalized id — the filename stem on the server. Matches the
  /// output of [normalizeArtistId] so the app can derive an id from a song's
  /// `artist` field locally and look up the picture.
  final String id;

  /// Original casing / punctuation of the artist name. Used for display.
  final String name;

  /// Server-side absolute URL to the picture. Sync downloads it once.
  final String imageUrl;

  factory RemoteArtist.fromJson(Map<String, dynamic> json) {
    return RemoteArtist(
      id: json['id'] as String,
      name: (json['name'] as String?) ?? (json['id'] as String),
      imageUrl: json['imageUrl'] as String,
    );
  }
}

/// Server-side `normalize_artist_id` mirrored in Dart so the app produces
/// the same id from a song's `artist` field as the server stored on disk.
String normalizeArtistId(String name) {
  final replaced = name.replaceAllMapped(
    RegExp(r'[^a-zA-Z0-9]+'),
    (_) => '_',
  );
  final trimmed = replaced
      .replaceAll(RegExp(r'^_+'), '')
      .replaceAll(RegExp(r'_+$'), '')
      .toLowerCase();
  return trimmed.isEmpty ? 'unknown' : trimmed;
}

/// Splits a multi-artist field ("Drake, 21 Savage", "X & Y", "X feat. Y")
/// into individual names. Mirrors the server's `_split_multi_artist`.
List<String> splitMultiArtist(String? field) {
  if (field == null || field.trim().isEmpty) return const [];
  return field
      .split(RegExp(
        r'\s*(?:,|&|\bfeat\.?\b|\bft\.?\b)\s*',
        caseSensitive: false,
      ))
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
}
