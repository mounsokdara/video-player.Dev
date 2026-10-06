package com.mounsokdara.video_player

/**
 * Dedicated Settings screen. Same native bridge as [MainActivity] (equalizer,
 * crash report, system bars) but starts on the Flutter `/settings` route, which
 * shows a category list on phones and a sidebar + detail pane on large screens.
 * Changes are saved to SharedPreferences; the main screen reloads them on resume.
 */
class SettingsActivity : MainActivity() {
    override fun getInitialRoute(): String = "/settings"

    override fun onUserLeaveHint() {
        // Settings is not a player; never enter PiP.
    }
}
