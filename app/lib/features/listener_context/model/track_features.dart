import '../../automix/model/automix_enums.dart';
import '../../automix/model/track_analysis.dart';
import '../../../data/database/app_database.dart';

/// The feature view the context engine scores tracks on. Bridges a [SongRow]
/// (catalog metadata) with its AutoMix [TrackAnalysis] sidecar (the real
/// energy/BPM/key/loudness). When no sidecar exists yet, fields fall back to
/// metadata proxies so the engine still functions on an un-analysed library.
class TrackFeatures {
  const TrackFeatures({
    required this.songId,
    required this.artist,
    required this.album,
    required this.genre,
    required this.mood,
    required this.bpm,
    required this.energy,
    required this.valence,
    required this.loudnessLufs,
    required this.durationSec,
    required this.hasAnalysis,
  });

  final String songId;
  final String? artist;
  final String? album;
  final String? genre;
  final String? mood;

  /// Beats per minute (0 if unknown).
  final double bpm;

  /// Perceived intensity, 0..1.
  final double energy;

  /// Musical positivity, 0..1 (major/bright/up-tempo → high).
  final double valence;

  /// Integrated loudness in LUFS (≈ −24..−5 typical).
  final double loudnessLufs;

  final double durationSec;
  final bool hasAnalysis;

  /// Energy on the spec's 0–100 scale.
  int get energyScore => (energy * 100).round().clamp(0, 100);

  /// Build features from a song + its (optional) analysis sidecar.
  factory TrackFeatures.fromSong(SongRow song, TrackAnalysis? a) {
    if (a != null) {
      final energy = _trackEnergy(a);
      return TrackFeatures(
        songId: song.id,
        artist: song.artist,
        album: song.album,
        genre: song.genre,
        mood: song.mood,
        bpm: a.bpm,
        energy: energy,
        valence: _valence(a, energy),
        loudnessLufs: a.lufs,
        durationSec: a.durationSec,
        hasAnalysis: true,
      );
    }
    // No sidecar: proxy from metadata.
    final bpm = (song.bpm ?? 0).toDouble();
    final energy = _proxyEnergy(bpm, song.mood);
    return TrackFeatures(
      songId: song.id,
      artist: song.artist,
      album: song.album,
      genre: song.genre,
      mood: song.mood,
      bpm: bpm,
      energy: energy,
      valence: _proxyValence(song.mood, energy),
      loudnessLufs: -14,
      durationSec: (song.durationMs ?? 0) / 1000.0,
      hasAnalysis: false,
    );
  }

  /// Duration-weighted mean section energy, nudged by loudness + tempo.
  static double _trackEnergy(TrackAnalysis a) {
    var sum = 0.0, wsum = 0.0;
    for (final s in a.sections) {
      final w = s.durationSec.clamp(0.1, double.infinity);
      sum += s.energy * w;
      wsum += w;
    }
    final sectionEnergy = wsum > 0 ? sum / wsum : 0.5;
    final bpmNorm = ((a.bpm - 60) / 120).clamp(0.0, 1.0); // 60..180 → 0..1
    final loudNorm = ((a.lufs + 30) / 24).clamp(0.0, 1.0); // −30..−6 → 0..1
    final e = 0.6 * sectionEnergy + 0.25 * bpmNorm + 0.15 * loudNorm;
    return e.clamp(0.0, 1.0);
  }

  /// Valence proxy: major key + brighter + up-tempo reads more positive.
  static double _valence(TrackAnalysis a, double energy) {
    final modeTerm = a.key.mode == KeyMode.major ? 0.18 : -0.12;
    final tempoTerm = ((a.bpm - 90) / 200).clamp(-0.15, 0.15);
    final v = 0.5 + modeTerm + tempoTerm + 0.15 * (energy - 0.5) * 2;
    // weight the key contribution by detection confidence
    final conf = a.key.confidence.clamp(0.0, 1.0);
    final blended = 0.5 + (v - 0.5) * (0.4 + 0.6 * conf);
    return blended.clamp(0.0, 1.0);
  }

  static double _proxyEnergy(double bpm, String? mood) {
    final m = (mood ?? '').toLowerCase();
    if (m.contains('workout') || m.contains('hype') || m.contains('party')) {
      return 0.85;
    }
    if (m.contains('calm') ||
        m.contains('chill') ||
        m.contains('sleep') ||
        m.contains('lofi') ||
        m.contains('study')) {
      return 0.3;
    }
    if (bpm > 0) return ((bpm - 60) / 120).clamp(0.1, 0.95);
    return 0.5;
  }

  static double _proxyValence(String? mood, double energy) {
    final m = (mood ?? '').toLowerCase();
    if (m.contains('happy') || m.contains('party')) return 0.8;
    if (m.contains('sad') || m.contains('melancholic') || m.contains('dark')) {
      return 0.25;
    }
    return (0.45 + 0.2 * (energy - 0.5) * 2).clamp(0.0, 1.0);
  }
}
