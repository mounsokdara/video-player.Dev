package com.mounsokdara.video_player.accessibility.livecaption.aimodeltranscribe

import android.content.Intent
import com.mounsokdara.video_player.accessibility.livecaption.aimodeltranscribe.download.DownloadActivity
import com.mounsokdara.video_player.accessibility.livecaption.aimodeltranscribe.settings.SettingsActivity

/** Accessibility > Live Caption > Manage AI model. Entry list for downloads and settings. */
class AiModelTranscribeActivity : ClassicActivity() {
    override val screenTitle: String get() = "Manage AI model"

    override fun build() {
        addRow("Download", "Get or remove the speech engine and AI models", chevron()) {
            startActivity(Intent(this, DownloadActivity::class.java))
        }
        addRow("Settings", "Default model and language", chevron()) {
            startActivity(Intent(this, SettingsActivity::class.java))
        }
    }
}
