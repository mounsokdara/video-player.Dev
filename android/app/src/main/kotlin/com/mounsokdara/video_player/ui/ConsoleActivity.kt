package com.mounsokdara.video_player

import android.content.ClipData
import android.content.ClipboardManager
import android.os.Bundle
import android.widget.TextView
import com.google.android.material.appbar.MaterialToolbar
import com.google.android.material.snackbar.Snackbar

class ConsoleActivity : PageActivity() {
    private lateinit var text: TextView

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_console)
        val toolbar = findViewById<MaterialToolbar>(R.id.toolbar)
        setupPage(findViewById(R.id.root), toolbar, getString(R.string.console_title), findViewById(R.id.scroll))
        text = findViewById(R.id.console_text)
        toolbar.inflateMenu(R.menu.console_menu)
        toolbar.setOnMenuItemClickListener { item ->
            when (item.itemId) {
                R.id.action_copy -> {
                    val cm = getSystemService(CLIPBOARD_SERVICE) as ClipboardManager
                    cm.setPrimaryClip(ClipData.newPlainText("console", body()))
                    Snackbar.make(text, R.string.console_copied, Snackbar.LENGTH_SHORT).show()
                    true
                }
                R.id.action_clear -> {
                    DeveloperLog.append(this, "__clear__")
                    NativeCrashLog.clear(this)
                    refresh()
                    true
                }
                else -> false
            }
        }
    }

    override fun onResume() {
        super.onResume()
        refresh()
    }

    private fun body(): String {
        val debug = DeveloperLog.read(this).ifBlank { getString(R.string.console_empty_debug) }
        return "=== debug ===\n$debug\n\n=== crash ===\n${NativeCrashLog.peek(this)}"
    }

    private fun refresh() {
        text.text = body()
    }
}
