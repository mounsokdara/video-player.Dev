package com.mounsokdara.video_player

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import com.google.android.material.appbar.MaterialToolbar
import com.google.android.material.dialog.MaterialAlertDialogBuilder
import java.util.TreeMap
import java.util.zip.GZIPInputStream

class LicensesActivity : PageActivity() {
    private class Pkg(val name: String) {
        val texts = LinkedHashSet<String>()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_licenses)
        setupPage(findViewById(R.id.root), findViewById<MaterialToolbar>(R.id.toolbar), getString(R.string.licenses_title))
        findViewById<TextView>(R.id.header).text =
            "${AboutInfo.NAME} ${AboutInfo.VERSION}\nLocal-only Android player. Material 3.\nCreated by ${AboutInfo.AUTHOR}."
        val list = findViewById<RecyclerView>(R.id.list)
        list.layoutManager = LinearLayoutManager(this)
        Thread {
            val pkgs = load()
            runOnUiThread {
                if (isFinishing || isDestroyed) return@runOnUiThread
                if (pkgs.isEmpty()) findViewById<View>(R.id.empty).visibility = View.VISIBLE
                list.adapter = Adapter(pkgs)
            }
        }.start()
    }

    /** Flutter bundles every Dart/plugin license in flutter_assets/NOTICES.Z (gzip): entries split by an 80-dash line, package names first, blank line, then the text. */
    private fun load(): List<Pkg> {
        val raw = try {
            assets.open("flutter_assets/NOTICES.Z").use { GZIPInputStream(it).readBytes().toString(Charsets.UTF_8) }
        } catch (_: Exception) {
            return emptyList()
        }
        val sep = "\n" + "-".repeat(80) + "\n"
        val map = TreeMap<String, Pkg>(String.CASE_INSENSITIVE_ORDER)
        for (entry in raw.split(sep)) {
            val cut = entry.indexOf("\n\n")
            if (cut < 0) continue
            val names = entry.substring(0, cut).lines().map { it.trim() }.filter { it.isNotEmpty() }
            val body = entry.substring(cut + 2).trim()
            if (body.isEmpty()) continue
            for (n in names) map.getOrPut(n) { Pkg(n) }.texts.add(body)
        }
        return map.values.toList()
    }

    private inner class Adapter(private val items: List<Pkg>) : RecyclerView.Adapter<Adapter.VH>() {
        inner class VH(v: View) : RecyclerView.ViewHolder(v) {
            val title: TextView = v.findViewById(R.id.row_title)
            val sub: TextView = v.findViewById(R.id.row_subtitle)
        }

        override fun onCreateViewHolder(parent: ViewGroup, viewType: Int) =
            VH(LayoutInflater.from(parent.context).inflate(R.layout.row_item, parent, false))

        override fun getItemCount() = items.size

        override fun onBindViewHolder(h: VH, position: Int) {
            val p = items[position]
            h.title.text = p.name
            h.sub.text = if (p.texts.size == 1) "1 license" else "${p.texts.size} licenses"
            h.itemView.setOnClickListener {
                MaterialAlertDialogBuilder(this@LicensesActivity)
                    .setTitle(p.name)
                    .setMessage(p.texts.joinToString("\n\n--------\n\n"))
                    .setPositiveButton(R.string.crash_close, null)
                    .show()
            }
        }
    }
}
