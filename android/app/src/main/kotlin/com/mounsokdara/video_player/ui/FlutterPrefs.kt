package com.mounsokdara.video_player

import android.content.Context

/** Native view of the same store the Dart side uses (shared_preferences: "flutter." key prefix, ints stored as Long). */
object FlutterPrefs {
    private const val FILE = "FlutterSharedPreferences"

    private fun p(c: Context) = c.getSharedPreferences(FILE, Context.MODE_PRIVATE)

    fun bool(c: Context, key: String, def: Boolean): Boolean = p(c).getBoolean("flutter.$key", def)

    fun string(c: Context, key: String): String? = p(c).getString("flutter.$key", null)

    fun int(c: Context, key: String, def: Int): Int =
        (p(c).all["flutter.$key"] as? Number)?.toInt() ?: def
}
