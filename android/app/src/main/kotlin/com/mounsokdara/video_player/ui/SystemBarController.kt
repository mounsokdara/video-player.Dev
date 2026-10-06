package com.mounsokdara.video_player

import android.app.Activity
import android.graphics.Color
import android.os.Build
import android.view.View
import android.view.Window
import android.view.WindowInsets
import android.view.WindowInsetsController
import android.view.WindowManager

class SystemBarController(private val activity: Activity) {
    private var lastLightIcons = true
    private var lastContrast = false
    private var lastHide = false
    private var hideGen = 0
    private var uiListenerAttached = false

    /** The window's own navigation bar color, so leaving a transparent screen (the player) restores it. */
    private var defaultNavColor: Int? = null

    private fun rememberDefaultNavColor(window: Window) {
        if (defaultNavColor == null) defaultNavColor = window.navigationBarColor
    }

    fun enableEdgeToEdge() {
        val window = activity.window
        rememberDefaultNavColor(window)
        try {
            if (Build.VERSION.SDK_INT >= 30) {
                window.setDecorFitsSystemWindows(false)
            }
            if (Build.VERSION.SDK_INT >= 28) {
                window.attributes.layoutInDisplayCutoutMode =
                    WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
            }
            window.clearFlags(WindowManager.LayoutParams.FLAG_FULLSCREEN)
            window.statusBarColor = Color.TRANSPARENT
            // Always transparent with no system scrim: the solid color behind the bar is painted
            // by the app (SolidNavBarStrip), so every screen and every Android version looks the same.
            window.navigationBarColor = Color.TRANSPARENT
            if (Build.VERSION.SDK_INT >= 29) {
                window.isNavigationBarContrastEnforced = false
                window.isStatusBarContrastEnforced = false
            }
            attachUiListener(window)
        } catch (_: Exception) {
        }
    }

    fun apply(lightIcons: Boolean, contrast: Boolean, hide: Boolean) {
        lastLightIcons = lightIcons
        lastContrast = contrast
        lastHide = hide
        hideGen++
        val gen = hideGen
        activity.runOnUiThread {
            try {
                val window = activity.window
                attachUiListener(window)
                window.clearFlags(WindowManager.LayoutParams.FLAG_FULLSCREEN)
                if (Build.VERSION.SDK_INT >= 30) {
                    window.setDecorFitsSystemWindows(false)
                }
                if (hide) {
                    hideBars(window)
                    window.decorView.post { if (lastHide && hideGen == gen) hideBars(window) }
                    window.decorView.postDelayed({ if (lastHide && hideGen == gen) hideBars(window) }, NativeConstants.HIDE_RETRY_MS)
                } else {
                    showBars(window, lightIcons, contrast)
                }
            } catch (_: Exception) {
            }
        }
    }

    fun reapply() {
        apply(lastLightIcons, lastContrast, lastHide)
    }

    @Suppress("DEPRECATION")
    private fun attachUiListener(window: Window) {
        if (uiListenerAttached) return
        uiListenerAttached = true
        window.decorView.setOnSystemUiVisibilityChangeListener { vis ->
            if (lastHide && vis and View.SYSTEM_UI_FLAG_HIDE_NAVIGATION == 0) {
                window.decorView.post { if (lastHide) hideBars(window) }
            }
        }
    }

    @Suppress("DEPRECATION")
    private fun hideBars(window: Window) {
        window.clearFlags(WindowManager.LayoutParams.FLAG_FULLSCREEN)
        if (Build.VERSION.SDK_INT >= 29) {
            window.isNavigationBarContrastEnforced = false
            window.isStatusBarContrastEnforced = false
        }
        window.statusBarColor = Color.TRANSPARENT
        window.navigationBarColor = Color.TRANSPARENT
        if (Build.VERSION.SDK_INT >= 30) {
            window.setDecorFitsSystemWindows(false)
            val controller = window.insetsController ?: window.decorView.windowInsetsController
            controller?.hide(WindowInsets.Type.statusBars() or WindowInsets.Type.navigationBars())
            controller?.systemBarsBehavior =
                WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            return
        }
        window.decorView.systemUiVisibility = (
            View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY or
                View.SYSTEM_UI_FLAG_LAYOUT_STABLE or
                View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION or
                View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN or
                View.SYSTEM_UI_FLAG_HIDE_NAVIGATION or
                View.SYSTEM_UI_FLAG_FULLSCREEN
            )
    }

    @Suppress("DEPRECATION")
    @Suppress("UNUSED_PARAMETER")
    private fun showBars(window: Window, lightIcons: Boolean, contrast: Boolean) {
        window.clearFlags(WindowManager.LayoutParams.FLAG_FULLSCREEN)
        window.statusBarColor = Color.TRANSPARENT
        // Always fully transparent. A solid bar is the app's SolidNavBarStrip; letting the system
        // draw its default color / contrast scrim here is what tinted the strip gray.
        window.navigationBarColor = Color.TRANSPARENT
        if (Build.VERSION.SDK_INT >= 30) {
            window.setDecorFitsSystemWindows(false)
            val controller = window.insetsController ?: window.decorView.windowInsetsController
            controller?.show(WindowInsets.Type.statusBars() or WindowInsets.Type.navigationBars() or WindowInsets.Type.systemBars())
            val light = WindowInsetsController.APPEARANCE_LIGHT_STATUS_BARS or
                WindowInsetsController.APPEARANCE_LIGHT_NAVIGATION_BARS
            controller?.setSystemBarsAppearance(if (lightIcons) 0 else light, light)
        }
        window.decorView.systemUiVisibility = (
            View.SYSTEM_UI_FLAG_LAYOUT_STABLE or
                View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION or
                View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
            )
        if (Build.VERSION.SDK_INT >= 29) {
            window.isNavigationBarContrastEnforced = false
            window.isStatusBarContrastEnforced = false
        }
    }
}
