package com.mounsokdara.video_player.accessibility.livecaption.aimodeltranscribe.settings

import android.content.Intent
import com.mounsokdara.video_player.accessibility.livecaption.LiveCaptionPrefs
import com.mounsokdara.video_player.accessibility.livecaption.aimodeltranscribe.ClassicActivity

/** Accessibility > Live Caption > Manage AI model > Settings. */
class SettingsActivity : ClassicActivity() {
    override val screenTitle: String get() = "Settings"

    private lateinit var modelRow: Row
    private lateinit var langRow: Row

    override fun build() {
        modelRow = addRow("Default model", null, chevron()) {
            startActivity(Intent(this, DefaultModelActivity::class.java))
        }
        langRow = addRow("Default language", null, chevron()) {
            startActivity(Intent(this, DefaultLangActivity::class.java))
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
    }
}
