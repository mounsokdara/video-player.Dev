package com.mounsokdara.video_player.accessibility.livecaption.aimodeltranscribe.download

import android.app.AlertDialog
import android.view.View
import android.widget.ImageView
import android.widget.ProgressBar
import android.widget.TextView
import com.mounsokdara.video_player.accessibility.livecaption.ModelStore
import com.mounsokdara.video_player.accessibility.livecaption.aimodeltranscribe.ClassicActivity

/**
 * Accessibility > Live Caption > Manage AI model > Download.
 * One clickable row per download: arrow icon to download, progress bar while downloading
 * (tap to pause), trash can once downloaded (tap to delete).
 */
class DownloadActivity : ClassicActivity() {
    override val screenTitle: String get() = "Download"

    private class RowViews(val sub: TextView, val bar: ProgressBar, val icon: ImageView)

    private val rows = LinkedHashMap<ModelStore.Item, RowViews>()
    private val listener = Runnable { refresh() }

    override fun build() {
        for (item in ModelStore.items()) {
            val icon = ImageView(this)
            val row = addRow(item.title, item.note, icon) { onTap(item) }
            val bar = ProgressBar(this, null, android.R.attr.progressBarStyleHorizontal).apply {
                max = 1000
                visibility = View.GONE
            }
            row.extra.addView(bar)
            rows[item] = RowViews(row.sub, bar, icon)
        }
        refresh()
    }

    override fun onStart() {
        super.onStart()
        ModelStore.addListener(listener)
        refresh()
    }

    override fun onStop() {
        ModelStore.removeListener(listener)
        super.onStop()
    }

    private fun mb(item: ModelStore.Item) = "~${item.totalApprox / 1_000_000} MB"

    private fun refresh() {
        for ((item, v) in rows) {
            val st = ModelStore.state(item.id)
            val ready = ModelStore.isReady(this, item.id)
            when {
                st.downloading -> {
                    v.bar.visibility = View.VISIBLE
                    v.bar.progress = st.progress
                    v.sub.visibility = View.VISIBLE
                    v.sub.text = "Downloading ${st.progress / 10}%  \u2022  tap to pause"
                    v.icon.setImageResource(android.R.drawable.ic_menu_close_clear_cancel)
                }
                ready -> {
                    v.bar.visibility = View.GONE
                    v.sub.visibility = View.VISIBLE
                    v.sub.text = "Downloaded  \u2022  ${mb(item)}"
                    v.icon.setImageResource(android.R.drawable.ic_menu_delete)
                }
                else -> {
                    v.bar.visibility = View.GONE
                    v.sub.visibility = View.VISIBLE
                    v.sub.text = st.error ?: "${item.note}  \u2022  ${mb(item)}"
                    v.icon.setImageResource(android.R.drawable.stat_sys_download)
                }
            }
        }
    }

    private fun onTap(item: ModelStore.Item) {
        val st = ModelStore.state(item.id)
        when {
            st.downloading -> ModelStore.cancel(item.id)
            ModelStore.isReady(this, item.id) ->
                AlertDialog.Builder(this)
                    .setTitle("Delete ${item.title}?")
                    .setMessage("You can download it again later.")
                    .setPositiveButton("Delete") { _, _ -> ModelStore.delete(this, item.id) }
                    .setNegativeButton("Cancel", null)
                    .show()
            else -> ModelStore.download(this, item.id)
        }
    }
}
