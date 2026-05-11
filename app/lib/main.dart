import 'dart:io' show Platform;

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import 'app.dart';
import 'core/services/audio_handler.dart';
import 'features/player/player_service.dart';

/// True once AudioService.init() completed. While false, the audio_service
/// plugin auto-registers as the platform but its handler is null — touching
/// any AudioPlayer.setAudioSource would crash. PlayerService gates on this.
bool audioBackgroundReady = false;
String? audioBackgroundInitError;

/// Process-wide audio handler created by AudioService.init. Exposed via a
/// Riverpod provider in `features/player/providers.dart`. Null if init
/// failed or hasn't run yet.
AppAudioHandler? globalAudioHandler;

/// Process-wide PlayerService. The handler holds a reference too; this
/// global is what the Riverpod provider returns. Single instance.
PlayerService? globalPlayerService;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Background playback only works on Android / iOS / macOS. On other
  // platforms (Windows desktop, Linux, web) skipping init avoids
  // UnimplementedError from blocking app boot.
  if (!kIsWeb && (Platform.isAndroid || Platform.isIOS || Platform.isMacOS)) {
    try {
      final service = PlayerService(AudioPlayer(), AudioPlayer());
      globalPlayerService = service;
      globalAudioHandler = await AudioService.init(
        builder: () => AppAudioHandler(service),
        config: const AudioServiceConfig(
          androidNotificationChannelId: 'com.music_app.audio',
          androidNotificationChannelName: 'Music playback',
          // `androidNotificationOngoing: true` requires the FG service to
          // stop on pause (an audio_service assertion — otherwise the app
          // becomes non-stoppable). For a music app we want the OPPOSITE:
          // the notification has to survive audio-focus changes (when
          // another app plays) without the user losing control. So we
          // skip the "ongoing" flag and instead keep the FG service alive
          // across pauses — that's what actually anchors the notification.
          androidNotificationOngoing: false,
          androidStopForegroundOnPause: false,
          androidResumeOnClick: true,
          preloadArtwork: true,
        ),
      );
      audioBackgroundReady = true;
      // ignore: avoid_print
      print('[audio] AudioService.init OK');
    } catch (e, st) {
      audioBackgroundInitError = '$e';
      // Loud, never-stripped output so we can see this in flutter logs
      // even on release. The app cannot play audio in this state.
      // ignore: avoid_print
      print('==========================================');
      // ignore: avoid_print
      print('[audio] AudioService.init FAILED');
      // ignore: avoid_print
      print('[audio] error: $e');
      // ignore: avoid_print
      print('[audio] stack:\n$st');
      // ignore: avoid_print
      print('==========================================');
    }
  } else {
    // Desktop / web — no background audio plugin to worry about, so
    // plain just_audio works. Treat as "ready" to skip the gate.
    audioBackgroundReady = true;
    globalPlayerService = PlayerService(AudioPlayer(), AudioPlayer());
  }

  runApp(const ProviderScope(child: MusicApp()));
}
