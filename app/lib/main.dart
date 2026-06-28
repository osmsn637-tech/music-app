import 'dart:io' show Platform;

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'core/services/audio_handler.dart';
import 'core/utils/path_rebaser.dart';
import 'data/database/app_database.dart';
import 'data/database/providers.dart';
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

  // Opt into the panel's highest refresh rate on Android. Many 90/120 Hz
  // devices clamp apps to 60 Hz until one explicitly requests the high
  // mode, which makes scrolling and the player animations feel choppy.
  // Best-effort: a failure here must never block launch.
  if (!kIsWeb && Platform.isAndroid) {
    try {
      await FlutterDisplayMode.setHighRefreshRate();
    } catch (_) {
      // No high-refresh mode available / plugin unavailable — stay at default.
    }
  }

  // Desktop window control (floating mini-player needs this initialised
  // before any window_manager call). Force a sane full-size window on every
  // launch so a persisted mini-player frame can't bring the app up tiny.
  final isDesktop =
      !kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux);
  if (isDesktop) {
    await windowManager.ensureInitialized();
  }

  if (!kIsWeb && (Platform.isAndroid || Platform.isIOS || Platform.isMacOS)) {
    try {
      // 1. iOS / Android audio category. Used to advertise that we're a
      //    music app (allows background playback, ducks Siri, respects
      //    AirPods route changes). Was implicitly handled by
      //    just_audio_background; now explicit.
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());
      // Activate the .playback session BEFORE SoLoud opens its CoreAudio
      // device. flutter_soloud's miniaudio backend starts the output unit
      // inside init() but deliberately never calls setActive — it expects
      // the app to already own an active session. Activating here is what
      // promotes us to the iOS "Now Playing" app so the lock-screen /
      // Control Center widget actually appears. (Our only other setActive
      // lived in a lazy path that runs on first play — far too late.)
      if (!await session.setActive(true)) {
        // ignore: avoid_print
        print('[audio] AudioSession activation denied (pre-SoLoud)');
      }

      // 2. Boot the SoLoud engine. Idempotent if already initialised by
      //    a previous hot restart.
      await SoLoud.instance.init();

      // Re-assert active state after SoLoud opened its device, in case the
      // device start nudged the session — cheap and idempotent.
      await session.setActive(true);

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

  // Database bootstrap. Construct the DB here and rebase any stored
  // absolute file paths onto the CURRENT app container BEFORE the first UI
  // read — iOS/macOS rotate the container UUID on reinstall, so without
  // this every song's localFilePath points at a dead path and the library
  // looks empty. Awaited (not fire-and-forget) so no screen renders stale
  // rows. A failure here mustn't brick launch — the app still runs with
  // whatever paths are stored.
  final db = AppDatabase();
  try {
    await rebasePathsIfNeeded(db);
  } catch (e) {
    // ignore: avoid_print
    print('[db] path rebase failed: $e');
  }

  runApp(
    ProviderScope(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
      child: const MusicApp(),
    ),
  );

  // Reset any leftover mini-player window state once the window is realized,
  // so the app always opens as the normal full window (the frame is
  // OS-autosaved across launches). Done post-first-frame to avoid the
  // before-runApp window calls leaving the window unrealized/hidden.
  if (isDesktop) {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await windowManager.setResizable(true);
      await windowManager.setAlwaysOnTop(false);
      // Frameless Spotify-style window: no native title bar, but keep the
      // macOS traffic lights floating over the custom top bar.
      await windowManager.setTitleBarStyle(
        TitleBarStyle.hidden,
        windowButtonVisibility: true,
      );
      await windowManager.setMinimumSize(const Size(720, 480));
      final size = await windowManager.getSize();
      if (size.width < 700 || size.height < 460) {
        await windowManager.setSize(const Size(1040, 720));
        await windowManager.center();
      }
    });
  }
}
