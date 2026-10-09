package com.mounsokdara.video_player.accessibility.livecaption.aimodeltranscribe.settings

import android.app.AlertDialog
import android.content.Intent
import com.mounsokdara.video_player.accessibility.livecaption.CaptionCache
import com.mounsokdara.video_player.accessibility.livecaption.LiveCaptionPrefs
import com.mounsokdara.video_player.accessibility.livecaption.aimodeltranscribe.ClassicActivity

/** Accessibility > Live Caption > Manage AI model > Settings. */
class SettingsActivity : ClassicActivity() {
    override val screenTitle: String get() = "Settings"

    private lateinit var modelRow: Row
    private lateinit var langRow: Row
    private lateinit var cacheRow: Row

    override fun build() {
        modelRow = addRow("Default model", null, chevron()) {
            startActivity(Intent(this, DefaultModelActivity::class.java))
        }
        langRow = addRow("Default language", null, chevron()) {
            startActivity(Intent(this, DefaultLangActivity::class.java))
        }
        cacheRow = addRow("Caption cache", null, null) {
            AlertDialog.Builder(this)
                .setTitle("Clear caption cache?")
                .setMessage("Saved captions are removed. They are extracted again when you watch the video.")
                .setPositiveButton("Clear") { _, _ ->
                    CaptionCache.clear(this)
                    refresh()
                }
                .setNegativeButton("Cancel", null)
                .show()
        }
        refresh()
    }

    override fun onResume() {
        super.onResume()
        if (::modelRow.isInitialized) refresh()
    }

    private fun refresh() {
        modelRow.sub.text = LiveCaptionPrefs.modelName(this)
        modelRow.sub.visibility = android.view.View.VISIBLE
        langRow.sub.text = LiveCaptionPrefs.langName(this)
        langRow.sub.visibility = android.view.View.VISIBLE
        val (count, bytes) = CaptionCache.stats(this)
        cacheRow.sub.text = if (count == 0) "Empty  \u2022  tap to clear" else "$count video(s), ${bytes / 1024} KB  \u2022  tap to clear"
        cacheRow.sub.visibility = android.view.View.VISIBLE
    }
}
