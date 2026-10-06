package com.mounsokdara.video_player

import android.graphics.drawable.ColorDrawable
import android.os.Bundle

/**
 * Base for the dedicated Flutter screens that run as their own launchable activity
 * (Settings, Open source licenses, Console). Same native bridge as [MainActivity], but the
 * subclass picks the Dart route to start on and PiP is never entered.
 */
open class FlutterPageActivity : MainActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        paintWindow()
        super.onCreate(savedInstanceState)
        // FlutterActivity switches to NormalTheme during onCreate; paint again.
        paintWindow()
    }

    /** Uses the surface color the app last drew (saved by Flutter), so the window
     *  matches the app theme instead of showing black before the first frame. */
    private fun paintWindow() {
        try {
            val argb = getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
                .getLong("flutter.windowBgArgb", 0L).toInt()
            if (argb != 0) window.setBackgroundDrawable(ColorDrawable(argb))
        } catch (_: Exception) {
        }
    }

    override fun onUserLeaveHint() {
        // These screens are not players; never enter PiP.
    }
}
