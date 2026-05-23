package com.osman.musicapp.music_app

import android.os.Build
import android.os.Bundle
import com.ryanheise.audioservice.AudioServiceActivity

// audio_service requires the host Activity to extend AudioServiceActivity
// (its own subclass of FlutterFragmentActivity). The audio engine itself
// is now flutter_soloud, which exposes the FFT directly — no native
// Visualizer plugin needed.
class MainActivity : AudioServiceActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        requestHighRefreshRate()
    }

    // Android defaults to whatever the system picks as the "preferred"
    // display mode, which on most phones with 90/120 Hz panels is still
    // 60 Hz unless the app explicitly opts in. We pick the highest
    // refresh-rate mode that matches the panel's native resolution and
    // set it as the window's preferredDisplayModeId — this is the
    // approach Google recommends for high-frame-rate apps.
    //
    // On 60 Hz devices the loop just finds the 60 Hz mode and is a
    // no-op. On 90 Hz devices we get 90; on 120 Hz devices we get 120.
    private fun requestHighRefreshRate() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return
        @Suppress("DEPRECATION")
        val display = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            display
        } else {
            windowManager.defaultDisplay
        } ?: return
        val currentMode = display.mode
        val best = display.supportedModes
            .filter {
                it.physicalWidth == currentMode.physicalWidth &&
                    it.physicalHeight == currentMode.physicalHeight
            }
            .maxByOrNull { it.refreshRate }
            ?: return
        if (best.modeId == currentMode.modeId) return
        val params = window.attributes
        params.preferredDisplayModeId = best.modeId
        window.attributes = params
    }
}
