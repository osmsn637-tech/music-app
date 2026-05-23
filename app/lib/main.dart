import 'dart:io' show Platform;

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_soloud/flutter_soloud.dart';

import 'app.dart';
import 'core/services/audio_handler.dart';
import 'features/player/player_service.dart';

/// True once SoLoud.init() and AudioService.init() completed. While false
/// PlayerService.playSong throws — there's no functional audio engine
/// to play into.
bool audioBackgroundReady = false;
String? audioBackgroundInitError;

/// Process-wide audio handler created by AudioService.init. Exposed via a
/// Riverpod provider in `features/player/providers.dart`. Null if init
/// failed or hasn't run yet.
AppAudioHandler? globalAudioHandler;

/// Process-wide PlayerService (soloud-backed). The handler holds a
/// reference too; this global is what the Riverpod provider returns.
PlayerService? globalPlayerService;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!kIsWeb && (Platform.isAndroid || Platform.isIOS || Platform.isMacOS)) {
    try {
      // 1. iOS / Android audio category. Used to advertise that we're a
      //    music app (allows background playback, ducks Siri, respects
      //    AirPods route changes). Was implicitly handled by
      //    just_audio_background; now explicit.
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());

      // 2. Boot the SoLoud engine. Idempotent if already initialised by
      //    a previous hot restart.
      await SoLoud.instance.init();

      // 3. Build the player service + audio_service handler. The
      //    service's enableVisualization() sets BOTH the visualisation
      //    flag AND drops FFT smoothing — necessary for the
      //    bass-onset detector to see kick transients instead of a
      //    pre-averaged mush.
      final service = PlayerService();
      service.enableVisualization();
      globalPlayerService = service;
      globalAudioHandler = await AudioService.init(
        builder: () => AppAudioHandler(service),
        config: const AudioServiceConfig(
          androidNotificationChannelId: 'com.music_app.audio',
          androidNotificationChannelName: 'Music playback',
          // Same rationale as before — we want the FG service to outlive
          // pauses so the lockscreen notification stays alive across
          // audio-focus changes.
          androidNotificationOngoing: false,
          androidStopForegroundOnPause: false,
          androidResumeOnClick: true,
          preloadArtwork: true,
        ),
      );
      audioBackgroundReady = true;
      // ignore: avoid_print
      print('[audio] SoLoud + AudioService init OK');
    } catch (e, st) {
      audioBackgroundInitError = '$e';
      // Loud, never-stripped output so we can see this in flutter logs
      // even on release. The app cannot play audio in this state.
      // ignore: avoid_print
      print('==========================================');
      // ignore: avoid_print
      print('[audio] SoLoud / AudioService init FAILED');
      // ignore: avoid_print
      print('[audio] error: $e');
      // ignore: avoid_print
      print('[audio] stack:\n$st');
      // ignore: avoid_print
      print('==========================================');
    }
  } else {
    // Desktop / web — soloud can still run, but skip the audio_service
    // wrapping (no mobile-style lockscreen there anyway).
    try {
      await SoLoud.instance.init();
      final service = PlayerService();
      service.enableVisualization();
      audioBackgroundReady = true;
      globalPlayerService = service;
    } catch (e) {
      audioBackgroundInitError = '$e';
    }
  }

  runApp(const ProviderScope(child: MusicApp()));
}
