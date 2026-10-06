package com.mounsokdara.video_player

import android.content.Context
import java.io.File

object DeveloperLog {
    private const val PREFS = "FlutterSharedPreferences"
    private const val DEV = "flutter.developerEnabled"
    private const val DEBUG = "flutter.debugLog"
    private const val MAX_BYTES = 96 * 1024

    fun developerEnabled(context: Context): Boolean =
        prefs(context).getBoolean(DEV, false)

    fun debugEnabled(context: Context): Boolean =
        prefs(context).getBoolean(DEBUG, false)

    fun setDeveloperEnabled(context: Context, on: Boolean) {
        prefs(context).edit().putBoolean(DEV, on).apply()
    }

    fun append(context: Context, line: String) {
        if (line == "__clear__") {
            try {
                file(context).writeText("")
            } catch (_: Exception) {
            }
            return
        }
        if (!developerEnabled(context) || !debugEnabled(context)) return
        try {
            val f = file(context)
            f.appendText(line.trimEnd() + "\n")
            if (f.length() > MAX_BYTES) {
                val keep = f.readText().takeLast(MAX_BYTES / 2)
                f.writeText(keep)
            }
        } catch (_: Exception) {
        }
    }

    fun read(context: Context): String {
        return try {
            val f = file(context)
            if (f.exists()) f.readText() else ""
        } catch (_: Exception) {
            ""
        }
    }

    private fun prefs(context: Context) =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    private fun file(context: Context) = File(context.filesDir, NativeConstants.FILE_DEBUG)
}
