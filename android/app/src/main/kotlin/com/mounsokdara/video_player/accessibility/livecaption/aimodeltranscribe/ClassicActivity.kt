package com.mounsokdara.video_player.accessibility.livecaption.aimodeltranscribe

import android.app.Activity
import android.graphics.Color
import android.os.Bundle
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView

/**
 * Base for the classic (Android 4 era) Live Caption screens: black legacy theme, gray title bar,
 * big white list rows with gray captions and thin dividers. Built in code, no Flutter.
 */
abstract class ClassicActivity : Activity() {
    protected lateinit var list: LinearLayout
    protected val dp: Float get() = resources.displayMetrics.density

    protected class Row(val root: LinearLayout, val title: TextView, val sub: TextView, val extra: LinearLayout)

    abstract val screenTitle: String
    abstract fun build()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        title = screenTitle
        list = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        setContentView(
            ScrollView(this).apply {
                setBackgroundColor(Color.BLACK)
                isFillViewport = true
                addView(list, ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))
            }
        )
        build()
    }

    /** A list row. [trailing] is shown on the right; [onClick] runs when the row is tapped. */
    protected fun addRow(titleText: String, subtitle: String?, trailing: View?, onClick: () -> Unit): Row {
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            minimumHeight = (64 * dp).toInt()
            setPadding((14 * dp).toInt(), (10 * dp).toInt(), (10 * dp).toInt(), (10 * dp).toInt())
            setBackgroundResource(android.R.drawable.list_selector_background)
            isClickable = true
            isFocusable = true
            setOnClickListener { onClick() }
        }
        val col = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        val t = TextView(this).apply {
            text = titleText
            textSize = 21f
            setTextColor(Color.WHITE)
        }
        val s = TextView(this).apply {
            text = subtitle ?: ""
            textSize = 15f
            setTextColor(Color.parseColor("#B0B0B0"))
            visibility = if (subtitle.isNullOrEmpty()) View.GONE else View.VISIBLE
        }
        val extra = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        col.addView(t)
        col.addView(s)
        col.addView(extra)
        root.addView(col, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
        if (trailing != null) {
            root.addView(
                trailing,
                LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT)
                    .apply { leftMargin = (8 * dp).toInt() }
            )
        }
        list.addView(root, ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))
        list.addView(
            View(this).apply { setBackgroundColor(Color.parseColor("#2E2E2E")) },
            ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 1)
        )
        return Row(root, t, s, extra)
    }

    protected fun chevron(): TextView = TextView(this).apply {
        text = "\u203A"
        textSize = 32f
        setTextColor(Color.parseColor("#888888"))
    }
}
