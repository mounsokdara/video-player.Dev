package com.mounsokdara.video_player

import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ResolveInfo
import android.net.Uri
import android.os.Build
import android.provider.Settings

/**
 * Builds the "Open in app" list from what Android itself resolves for this app, so it always
 * reflects the real manifest intent filters (nothing is hand-maintained).
 */
object OpenInApp {
    private fun probes(): List<Pair<String, Intent>> = listOf(
        "view_content" to Intent(Intent.ACTION_VIEW)
            .setDataAndType(Uri.parse("content://media/external/video/media/1"), "video/mp4"),
        "view_file" to Intent(Intent.ACTION_VIEW)
            .setDataAndType(Uri.parse("file:///sdcard/video.mp4"), "video/mp4"),
        "send" to Intent(Intent.ACTION_SEND).setType("video/mp4"),
        "get_content" to Intent(Intent.ACTION_GET_CONTENT).setType("video/*")
            .addCategory(Intent.CATEGORY_OPENABLE),
        "pick" to Intent(Intent.ACTION_PICK).setType("video/*"),
    )

    @Suppress("DEPRECATION")
    private fun query(pm: PackageManager, i: Intent): List<ResolveInfo> =
        if (Build.VERSION.SDK_INT >= 33) {
            pm.queryIntentActivities(i, PackageManager.ResolveInfoFlags.of(PackageManager.MATCH_DEFAULT_ONLY.toLong()))
        } else {
            pm.queryIntentActivities(i, PackageManager.MATCH_DEFAULT_ONLY)
        }

    @Suppress("DEPRECATION")
    private fun resolve(pm: PackageManager, i: Intent): ResolveInfo? =
        if (Build.VERSION.SDK_INT >= 33) {
            pm.resolveActivity(i, PackageManager.ResolveInfoFlags.of(PackageManager.MATCH_DEFAULT_ONLY.toLong()))
        } else {
            pm.resolveActivity(i, PackageManager.MATCH_DEFAULT_ONLY)
        }

    fun entries(activity: Activity): List<Map<String, Any>> {
        val pm = activity.packageManager
        val me = activity.packageName
        return probes().map { (id, intent) ->
            val handlers = try { query(pm, intent) } catch (_: Exception) { emptyList() }
            val handled = handlers.any { it.activityInfo?.packageName == me }
            val isDefault = try { resolve(pm, intent)?.activityInfo?.packageName == me } catch (_: Exception) { false }
            mapOf("id" to id, "handled" to handled, "isDefault" to (handled && isDefault))
        }
    }

    /** System "Open by default" page for this app (API 31+), else the app details page. */
    fun openByDefaultSettings(activity: Activity): Boolean {
        val pkg = Uri.parse("package:${activity.packageName}")
        val intents = buildList {
            if (Build.VERSION.SDK_INT >= 31) add(Intent(Settings.ACTION_APP_OPEN_BY_DEFAULT_SETTINGS, pkg))
            add(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, pkg))
        }
        for (i in intents) {
            try {
                activity.startActivity(i)
                return true
            } catch (_: Exception) {
            }
        }
        return false
    }
}
