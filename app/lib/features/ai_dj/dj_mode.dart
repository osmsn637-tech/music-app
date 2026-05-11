/// DJ modes used by the AI DJ (Phase 7) and as the `context` field on
/// listening events. Stored as lowercase strings in the database.
enum DjMode {
  general,
  study,
  chill,
  workout,
  night,
  favorites,
  discover,
  smartShuffle,
}

extension DjModeName on DjMode {
  String get id {
    switch (this) {
      case DjMode.general:
        return 'general';
      case DjMode.study:
        return 'study';
      case DjMode.chill:
        return 'chill';
      case DjMode.workout:
        return 'workout';
      case DjMode.night:
        return 'night';
      case DjMode.favorites:
        return 'favorites';
      case DjMode.discover:
        return 'discover';
      case DjMode.smartShuffle:
        return 'smart_shuffle';
    }
  }

  String get label {
    switch (this) {
      case DjMode.general:
        return 'General';
      case DjMode.study:
        return 'Study';
      case DjMode.chill:
        return 'Chill';
      case DjMode.workout:
        return 'Workout';
      case DjMode.night:
        return 'Night';
      case DjMode.favorites:
        return 'Favorites';
      case DjMode.discover:
        return 'Discover';
      case DjMode.smartShuffle:
        return 'Smart Shuffle';
    }
  }
}
