package com.mounsokdara.video_player

import android.app.Activity
import android.content.res.Configuration
import android.graphics.Color
import android.graphics.Rect
import android.os.Build
import android.view.View
import android.view.ViewGroup
import androidx.core.view.ViewCompat
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat

/**
 * One place for status bar / navigation bar / cutout / keyboard handling in every native activity.
 *
 * - Window is edge-to-edge with transparent bars (no contrast scrim).
 * - [root] always receives the left/top/right insets.
 * - Bottom inset (navigation bar or keyboard, whichever is larger) goes to [scrollers] so their
 *   content scrolls underneath the bar and stops clear of it at the end. With no scrollers
 *   (fixed bottom buttons) the bottom inset goes to [root] instead.
 */
object SafeZone {
    fun install(activity: Activity, root: View, scrollers: List<View> = emptyList(), forceDarkSurface: Boolean = false) {
        val window = activity.window
        WindowCompat.setDecorFitsSystemWindows(window, false)
        @Suppress("DEPRECATION")
        run {
            window.statusBarColor = Color.TRANSPARENT
            window.navigationBarColor = Color.TRANSPARENT
        }
        if (Build.VERSION.SDK_INT >= 29) {
            window.isNavigationBarContrastEnforced = false
            window.isStatusBarContrastEnforced = false
        }

        val rootBase = Rect(root.paddingLeft, root.paddingTop, root.paddingRight, root.paddingBottom)
        val bases = scrollers.map { Rect(it.paddingLeft, it.paddingTop, it.paddingRight, it.paddingBottom) }
        ViewCompat.setOnApplyWindowInsetsListener(root) { v, insets ->
            val bars = insets.getInsets(WindowInsetsCompat.Type.systemBars() or WindowInsetsCompat.Type.displayCutout())
            val ime = insets.getInsets(WindowInsetsCompat.Type.ime())
            val bottom = maxOf(bars.bottom, ime.bottom)
            v.setPadding(
                rootBase.left + bars.left,
                rootBase.top + bars.top,
                rootBase.right + bars.right,
                rootBase.bottom + if (scrollers.isEmpty()) bottom else 0
            )
            scrollers.forEachIndexed { i, s ->
                val b = bases[i]
                s.setPadding(b.left, b.top, b.right, b.bottom + bottom)
                (s as? ViewGroup)?.clipToPadding = false
            }
            WindowInsetsCompat.CONSUMED
        }
        ViewCompat.requestApplyInsets(root)

        val night = forceDarkSurface ||
            (activity.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK) == Configuration.UI_MODE_NIGHT_YES
        WindowCompat.getInsetsController(window, root).apply {
            isAppearanceLightStatusBars = !night
            isAppearanceLightNavigationBars = !night
        }
    }
}
