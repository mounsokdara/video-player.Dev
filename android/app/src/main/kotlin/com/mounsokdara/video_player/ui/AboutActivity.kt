package com.mounsokdara.video_player

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.os.SystemClock
import android.view.HapticFeedbackConstants
import android.view.LayoutInflater
import android.view.View
import android.widget.LinearLayout
import android.widget.TextView
import com.google.android.material.appbar.MaterialToolbar
import com.google.android.material.materialswitch.MaterialSwitch
import com.google.android.material.snackbar.Snackbar

object AboutInfo {
    const val NAME = "Video Player"
    const val AUTHOR = "Moun Sokdara"
    const val VERSION = "1.0.2.1" // keep in sync with lib/settings/about.dart AboutInfo.displayVersion
    const val REPO = "https://github.com/mounsokdara/video-player"
}

class AboutActivity : PageActivity() {
    private data class DevOption(val key: String, val title: String, val subtitle: String, val def: Boolean)

    private val devOptions = listOf(
        DevOption("debugLog", "Log debug", "Enable developer logging", false),
        DevOption("videoLogOverlay", "VideoLogOverlay", "Show live yellow diagnostic text over the video", false),
        DevOption("videoLogShowState", "Overlay: playback state", "Position, duration, play/pause, buffering, size and FPS", true),
        DevOption("videoLogShowMedia", "Overlay: media info", "Pixel format, transfer, primaries, matrix and HDR detection", true),
        DevOption("videoLogShowRender", "Overlay: render info", "Render mode and active video filter", true),
        DevOption("videoLogShowDecoder", "Overlay: decoder info", "Hardware/software decoder and render capability", true),
        DevOption("videoLogShowTiming", "Overlay: timing / screen", "Display resolution, refresh rate and render timing data", false),
        DevOption("logPlayerEvents", "Log player events", "Open, play, pause, seek, repeat and close events", false),
        DevOption("logGestureEvents", "Log gesture events", "Pinch, seek, brightness, volume and tap gesture events", false),
        DevOption("logLifecycleEvents", "Log lifecycle events", "App/player resume, pause and background transitions", false),
    )

    private var taps = 0
    private var lastTap = 0L
    private lateinit var root: View
    private lateinit var devSection: View

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_about)
        root = findViewById(R.id.root)
        setupPage(root, findViewById<MaterialToolbar>(R.id.toolbar), getString(R.string.about_title))
        findViewById<TextView>(R.id.about_name).text = AboutInfo.NAME

        bindRow(R.id.row_author, getString(R.string.about_created_by), AboutInfo.AUTHOR)
        bindRow(R.id.row_version, getString(R.string.about_version), AboutInfo.VERSION).setOnClickListener { onVersionTap() }
        bindRow(R.id.row_licenses, getString(R.string.about_licenses), null).setOnClickListener {
            startActivity(Intent(this, LicensesActivity::class.java))
        }
        bindRow(R.id.row_source, getString(R.string.about_source), "github.com/mounsokdara/video-player").setOnClickListener {
            try {
                startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(AboutInfo.REPO)))
            } catch (_: Exception) {
            }
        }

        devSection = findViewById(R.id.dev_section)
        buildDevOptions()
        bindRow(R.id.row_console, getString(R.string.about_console), getString(R.string.about_console_desc)).setOnClickListener {
            startActivity(Intent(this, ConsoleActivity::class.java))
        }
        refreshDevSection()
    }

    private fun bindRow(id: Int, title: String, subtitle: String?): View {
        val row = findViewById<View>(id)
        row.findViewById<TextView>(R.id.row_title).text = title
        val sub = row.findViewById<TextView>(R.id.row_subtitle)
        if (subtitle == null) sub.visibility = View.GONE else sub.text = subtitle
        return row
    }

    private fun buildDevOptions() {
        val container = findViewById<LinearLayout>(R.id.dev_switches)
        val inflater = LayoutInflater.from(this)
        for (opt in devOptions) {
            val row = inflater.inflate(R.layout.row_switch, container, false)
            row.findViewById<TextView>(R.id.row_title).text = opt.title
            row.findViewById<TextView>(R.id.row_subtitle).text = opt.subtitle
            val sw = row.findViewById<MaterialSwitch>(R.id.row_switch)
            sw.isChecked = FlutterPrefs.bool(this, opt.key, opt.def)
            sw.setOnCheckedChangeListener { _, on ->
                FlutterPrefs.putBool(this, opt.key, on)
                if (opt.key == "debugLog") DeveloperLog.append(this, "debugLog=$on")
            }
            row.setOnClickListener { sw.toggle() }
            container.addView(row)
        }
    }

    private fun refreshDevSection() {
        devSection.visibility = if (DeveloperLog.developerEnabled(this)) View.VISIBLE else View.GONE
    }

    private fun onVersionTap() {
        val now = SystemClock.elapsedRealtime()
        if (now - lastTap > 2000) taps = 0
        lastTap = now
        taps += 1
        if (DeveloperLog.developerEnabled(this)) {
            snack("Developer options are on")
            return
        }
        val left = 10 - taps
        if (left in 1..3) snack("$left tap${if (left == 1) "" else "s"} away from developer options")
        if (taps >= 10) {
            taps = 0
            DeveloperLog.setDeveloperEnabled(this, true)
            root.performHapticFeedback(HapticFeedbackConstants.LONG_PRESS)
            refreshDevSection()
            snack("Developer options enabled")
        }
    }

    private fun snack(msg: String) = Snackbar.make(root, msg, Snackbar.LENGTH_SHORT).show()
}
