package com.mounsokdara.video_player.accessibility.livecaption.aimodeltranscribe.settings

import android.view.View
import android.widget.RadioButton
import com.mounsokdara.video_player.accessibility.livecaption.LiveCaptionPrefs
import com.mounsokdara.video_player.accessibility.livecaption.ModelStore
import com.mounsokdara.video_player.accessibility.livecaption.aimodeltranscribe.ClassicActivity

/** Settings > Default model: one radio button per row. */
class DefaultModelActivity : ClassicActivity() {
    override val screenTitle: String get() = "Default model"

    private val radios = LinkedHashMap<String, RadioButton>()

    override fun build() {
        val current = LiveCaptionPrefs.model(this)
        for ((id, name) in LiveCaptionPrefs.MODELS) {
            val rb = RadioButton(this).apply {
                isChecked = id == current
                isClickable = false
                isFocusable = false
            }
            val sub = ModelStore.item(id).note + if (ModelStore.isReady(this, id)) "" else "  \u2022  not downloaded"
            addRow(name, sub, rb) {
                LiveCaptionPrefs.setModel(this, id)
                for ((k, r) in radios) r.isChecked = k == id
            }
            rb.visibility = View.VISIBLE
            radios[id] = rb
        }
    }
}
