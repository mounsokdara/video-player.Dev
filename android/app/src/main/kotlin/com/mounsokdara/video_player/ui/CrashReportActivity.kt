package com.mounsokdara.video_player

import android.app.Activity
import android.content.ClipData
import android.content.ClipboardManager
import android.os.Build
import android.os.Bundle
import android.widget.TextView
import android.widget.Toast

class CrashReportActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val report = intent.getStringExtra(EXTRA_REPORT)
            ?: NativeCrashLog.readLast(this)
            ?: getString(R.string.crash_empty)

        setContentView(R.layout.activity_crash_report)
        SafeZone.install(this, findViewById(R.id.root), forceDarkSurface = true)
        findViewById<TextView>(R.id.crash_body).text = report
        findViewById<android.view.View>(R.id.crash_copy).setOnClickListener {
            val cm = getSystemService(ClipboardManager::class.java) ?: return@setOnClickListener
            cm.setPrimaryClip(ClipData.newPlainText(getString(R.string.crash_clip_label), report))
            if (Build.VERSION.SDK_INT < 33) {
                Toast.makeText(this, getString(R.string.crash_copied), Toast.LENGTH_SHORT).show()
            }
        }
        findViewById<android.view.View>(R.id.crash_close).setOnClickListener { finish() }
    }

    companion object {
        const val EXTRA_REPORT = "report"
    }
}
