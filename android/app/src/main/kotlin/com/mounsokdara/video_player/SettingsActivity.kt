package com.mounsokdara.video_player

import android.graphics.drawable.ColorDrawable
import android.os.Bundle

/**
 * Dedicated Settings screen. Same native bridge as [MainActivity] (equalizer,
 * crash report, system bars) but starts on the Flutter `/settings` route, which
 * shows a category list on phones and a sidebar + detail pane on large screens.
 * Changes are saved to SharedPreferences; the main screen reloads them on resume.
 */
class SettingsActivity : MainActivity() {
    override fun getInitialRoute(): String = "/settings"

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
        // Settings is not a player; never enter PiP.
    }
}
