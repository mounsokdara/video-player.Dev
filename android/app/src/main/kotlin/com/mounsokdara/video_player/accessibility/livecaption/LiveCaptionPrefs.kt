package com.mounsokdara.video_player.accessibility.livecaption

import android.content.Context

/** Native-side Live Caption preferences (default model and language). */
object LiveCaptionPrefs {
    /** id to display name. Ids match [ModelStore] model items. */
    val MODELS = listOf("base" to "Whisper Base", "small" to "Whisper Small")

    /** Whisper language code ("" = auto-detect) to display name. */
    val LANGS = listOf(
        "" to "Auto-detect", "en" to "English", "km" to "Khmer", "zh" to "Chinese", "ja" to "Japanese",
        "ko" to "Korean", "fr" to "French", "de" to "German", "es" to "Spanish", "ru" to "Russian",
        "ar" to "Arabic", "hi" to "Hindi", "th" to "Thai", "vi" to "Vietnamese", "id" to "Indonesian",
    )

    private fun sp(c: Context) = c.getSharedPreferences("live_caption", Context.MODE_PRIVATE)

    fun model(c: Context): String = sp(c).getString("default_model", "base") ?: "base"
    fun setModel(c: Context, id: String) = sp(c).edit().putString("default_model", id).apply()
    fun lang(c: Context): String = sp(c).getString("default_lang", "") ?: ""
    fun setLang(c: Context, code: String) = sp(c).edit().putString("default_lang", code).apply()

    fun modelName(c: Context): String = MODELS.firstOrNull { it.first == model(c) }?.second ?: "Whisper Base"
    fun langName(c: Context): String = LANGS.firstOrNull { it.first == lang(c) }?.second ?: "Auto-detect"
}
