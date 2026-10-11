package com.mounsokdara.video_player.accessibility.livecaption.aimodeltranscribe.settings

import android.widget.RadioButton
import com.mounsokdara.video_player.accessibility.livecaption.LiveCaptionPrefs
import com.mounsokdara.video_player.accessibility.livecaption.aimodeltranscribe.ClassicActivity

/** Settings > Default language: one radio button per row. */
class DefaultLangActivity : ClassicActivity() {
    override val screenTitle: String get() = "Default language"

    private val radios = LinkedHashMap<String, RadioButton>()

    override fun build() {
        val current = LiveCaptionPrefs.lang(this)
        for ((code, name) in LiveCaptionPrefs.LANGS) {
            val rb = RadioButton(this).apply {
                isChecked = code == current
                isClickable = false
                isFocusable = false
            }
            val sub = if (code.isEmpty()) "Let the AI detect the spoken language" else null
            addRow(name, sub, rb) {
                LiveCaptionPrefs.setLang(this, code)
                for ((k, r) in radios) r.isChecked = k == code
            }
            radios[code] = rb
        }
    }
}
