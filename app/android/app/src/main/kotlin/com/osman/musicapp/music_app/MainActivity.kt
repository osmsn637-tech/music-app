package com.osman.musicapp.music_app

import com.ryanheise.audioservice.AudioServiceActivity

// audio_service requires the host Activity to extend AudioServiceActivity
// (its own subclass of FlutterFragmentActivity). Using the default
// FlutterActivity causes JustAudioBackground.init to fail with
// "The Activity class declared in your AndroidManifest.xml is wrong".
class MainActivity : AudioServiceActivity()
