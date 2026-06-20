import 'package:flutter/foundation.dart';
import 'package:volume_controller/volume_controller.dart';

/// Thin, session-safe wrapper around [VolumeController].
///
/// The plugin's volume *listener* is the only part that touches the shared
/// iOS `AVAudioSession`, and it does so destructively:
///   * on add → sets the category to `.playback, .mixWithOthers` and
///     activates — `.mixWithOthers` makes the app relinquish "Now Playing",
///     killing the lock-screen widget — and re-asserts this on every
///     app-foreground;
///   * on remove → calls `setActive(false)`, which suspends the very
///     session `flutter_soloud` plays through, so playback stops whenever
///     the volume row unmounts (player collapse / lyrics).
///
/// `getVolume()` and `setVolume()`, by contrast, never touch the session
/// (verified against volume_controller 3.5.0's native source). So we use
/// ONLY those: read the level when the volume UI appears, write it on drag,
/// and never register the listener. The trade-off — the slider won't
/// live-track the hardware volume buttons while it's open — is well worth
/// not having playback and the now-playing widget torn down underneath us.
class VolumeService {
  VolumeService._() {
    // Never flash the system volume HUD when we set the value.
    VolumeController.instance.showSystemUI = false;
  }
  static final VolumeService instance = VolumeService._();

  /// Latest known system volume (0..1). The volume slider binds to this.
  final ValueNotifier<double> volume = ValueNotifier<double>(0.5);

  /// Re-read the current system volume into [volume]. Call when the volume
  /// UI appears so the thumb starts at the right place. Read-only — does
  /// not touch the audio session.
  Future<void> refresh() async {
    final v = await VolumeController.instance.getVolume();
    volume.value = v.clamp(0.0, 1.0);
  }

  /// Set the system volume and reflect it locally.
  void setVolume(double v) {
    final clamped = v.clamp(0.0, 1.0);
    volume.value = clamped;
    VolumeController.instance.setVolume(clamped);
  }
}
