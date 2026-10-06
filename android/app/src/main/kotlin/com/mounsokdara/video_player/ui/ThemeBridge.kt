package com.mounsokdara.video_player

import android.app.Activity
import android.content.Context
import android.content.res.Configuration
import androidx.appcompat.app.AppCompatDelegate
import com.google.android.material.color.ColorResourcesOverride
import com.google.android.material.color.DynamicColors
import com.google.android.material.color.DynamicColorsOptions
import org.json.JSONObject

/**
 * Cross-activity theme. Dart owns the theme (AppTheme / materialYouScheme / high contrast); it publishes the
 * resolved light+dark ColorScheme to prefs (`flutter.themeScheme`, see lib/core/theme_export.dart) and every
 * native activity applies exactly those colors. Fallbacks, in order: exact Dart scheme (Android 11+),
 * dynamic color / seed color (Android 12+), baseline Material 3.
 */
object ThemeBridge {
    private val ROLES: Map<String, Int> = mapOf(
        "primary" to R.color.vp_scheme_primary,
        "onPrimary" to R.color.vp_scheme_on_primary,
        "primaryContainer" to R.color.vp_scheme_primary_container,
        "onPrimaryContainer" to R.color.vp_scheme_on_primary_container,
        "secondary" to R.color.vp_scheme_secondary,
        "onSecondary" to R.color.vp_scheme_on_secondary,
        "secondaryContainer" to R.color.vp_scheme_secondary_container,
        "onSecondaryContainer" to R.color.vp_scheme_on_secondary_container,
        "tertiary" to R.color.vp_scheme_tertiary,
        "onTertiary" to R.color.vp_scheme_on_tertiary,
        "tertiaryContainer" to R.color.vp_scheme_tertiary_container,
        "onTertiaryContainer" to R.color.vp_scheme_on_tertiary_container,
        "error" to R.color.vp_scheme_error,
        "onError" to R.color.vp_scheme_on_error,
        "errorContainer" to R.color.vp_scheme_error_container,
        "onErrorContainer" to R.color.vp_scheme_on_error_container,
        "surface" to R.color.vp_scheme_surface,
        "onSurface" to R.color.vp_scheme_on_surface,
        "onSurfaceVariant" to R.color.vp_scheme_on_surface_variant,
        "surfaceContainerLowest" to R.color.vp_scheme_surface_container_lowest,
        "surfaceContainerLow" to R.color.vp_scheme_surface_container_low,
        "surfaceContainer" to R.color.vp_scheme_surface_container,
        "surfaceContainerHigh" to R.color.vp_scheme_surface_container_high,
        "surfaceContainerHighest" to R.color.vp_scheme_surface_container_highest,
        "outline" to R.color.vp_scheme_outline,
        "outlineVariant" to R.color.vp_scheme_outline_variant,
        "inverseSurface" to R.color.vp_scheme_inverse_surface,
        "onInverseSurface" to R.color.vp_scheme_on_inverse_surface,
        "inversePrimary" to R.color.vp_scheme_inverse_primary,
    )

    /** ThemeModePref: 0 system, 1 light, 2 dark. */
    fun isNight(context: Context): Boolean = when (FlutterPrefs.int(context, "themeMode", 0)) {
        1 -> false
        2 -> true
        else -> (context.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK) == Configuration.UI_MODE_NIGHT_YES
    }

    /** Call before super.onCreate of an AppCompat activity using Theme.VideoPlayer.Page. */
    fun apply(activity: Activity) {
        AppCompatDelegate.setDefaultNightMode(
            when (FlutterPrefs.int(activity, "themeMode", 0)) {
                1 -> AppCompatDelegate.MODE_NIGHT_NO
                2 -> AppCompatDelegate.MODE_NIGHT_YES
                else -> AppCompatDelegate.MODE_NIGHT_FOLLOW_SYSTEM
            }
        )
        try {
            if (FlutterPrefs.bool(activity, "dynamicColor", false)) {
                DynamicColors.applyToActivityIfAvailable(activity)
            } else {
                val seed = FlutterPrefs.int(activity, "seedColor", 0xFF38618D.toInt())
                DynamicColors.applyToActivityIfAvailable(
                    activity,
                    DynamicColorsOptions.Builder().setContentBasedSource(seed).build()
                )
            }
        } catch (_: Throwable) {
        }
        try {
            applyDartScheme(activity)
        } catch (_: Throwable) {
        }
    }

    private fun applyDartScheme(activity: Activity): Boolean {
        val raw = FlutterPrefs.string(activity, "themeScheme") ?: return false
        val scheme = JSONObject(raw).getJSONObject(if (isNight(activity)) "dark" else "light")
        val colors = HashMap<Int, Int>()
        for ((role, res) in ROLES) {
            if (scheme.has(role)) colors[res] = scheme.getLong(role).toInt()
        }
        if (colors.isEmpty()) return false
        val override = ColorResourcesOverride.getInstance() ?: return false
        if (!override.applyIfPossible(activity, colors)) return false
        activity.theme.applyStyle(R.style.ThemeOverlay_VideoPlayer_AppScheme, true)
        return true
    }
}
