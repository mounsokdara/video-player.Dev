package com.mounsokdara.video_player

import android.os.Bundle
import android.view.View
import androidx.appcompat.app.AppCompatActivity
import androidx.appcompat.app.AppCompatDelegate
import com.google.android.material.appbar.MaterialToolbar
import com.google.android.material.color.DynamicColors
import com.google.android.material.color.DynamicColorsOptions

/** Base for every native XML page: follows the app's theme prefs, edge-to-edge, back-arrow toolbar. */
open class PageActivity : AppCompatActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        applyAppTheme()
        super.onCreate(savedInstanceState)
    }

    private fun applyAppTheme() {
        // ThemeModePref: 0 system, 1 light, 2 dark
        AppCompatDelegate.setDefaultNightMode(
            when (FlutterPrefs.int(this, "themeMode", 0)) {
                1 -> AppCompatDelegate.MODE_NIGHT_NO
                2 -> AppCompatDelegate.MODE_NIGHT_YES
                else -> AppCompatDelegate.MODE_NIGHT_FOLLOW_SYSTEM
            }
        )
        try {
            if (FlutterPrefs.bool(this, "dynamicColor", false)) {
                DynamicColors.applyToActivityIfAvailable(this)
            } else {
                val seed = FlutterPrefs.int(this, "seedColor", 0xFF38618D.toInt())
                DynamicColors.applyToActivityIfAvailable(
                    this,
                    DynamicColorsOptions.Builder().setContentBasedSource(seed).build()
                )
            }
        } catch (_: Throwable) {
            // Older devices: keep the baseline Material 3 scheme.
        }
    }

    /** [scrollers]: lists/scroll views that should scroll under the navigation bar (see [SafeZone]). */
    protected fun setupPage(root: View, toolbar: MaterialToolbar, title: CharSequence, vararg scrollers: View) {
        toolbar.title = title
        toolbar.setNavigationIcon(R.drawable.ic_arrow_back)
        toolbar.setNavigationContentDescription(R.string.navigate_back)
        toolbar.setNavigationOnClickListener { finish() }
        SafeZone.install(this, root, scrollers.toList())
    }
}
