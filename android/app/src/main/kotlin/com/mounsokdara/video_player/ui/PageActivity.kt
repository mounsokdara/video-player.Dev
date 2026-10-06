package com.mounsokdara.video_player

import android.os.Bundle
import android.view.View
import androidx.appcompat.app.AppCompatActivity
import com.google.android.material.appbar.MaterialToolbar

/** Base for every native XML page: Dart-driven theme (ThemeBridge), shared safe zone (SafeZone), back-arrow toolbar. */
open class PageActivity : AppCompatActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        ThemeBridge.apply(this)
        super.onCreate(savedInstanceState)
    }

    /** [scrollers]: lists/scroll views that should scroll under the navigation bar (see [SafeZone]). */
    protected fun setupPage(root: View, toolbar: MaterialToolbar, title: CharSequence, vararg scrollers: View) {
        toolbar.title = title
        toolbar.setNavigationIcon(R.drawable.ic_arrow_back)
        toolbar.setNavigationContentDescription(R.string.navigate_back)
        toolbar.setNavigationOnClickListener { finish() }
        SafeZone.install(this, root, scrollers.toList())
    }
}
