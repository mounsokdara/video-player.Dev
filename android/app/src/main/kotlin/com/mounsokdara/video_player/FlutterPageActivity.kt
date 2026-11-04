package com.mounsokdara.video_player

import android.graphics.drawable.ColorDrawable
import android.os.Bundle

open class FlutterPageActivity : MainActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        paintWindow()
        super.onCreate(savedInstanceState)
        paintWindow()
    }

    private fun paintWindow() {
        try {
            val argb = getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
                .getLong("flutter.windowBgArgb", 0L).toInt()
            if (argb != 0) window.setBackgroundDrawable(ColorDrawable(argb))
        } catch (_: Exception) {
        }
    }

    override fun onUserLeaveHint() {
    }
}
