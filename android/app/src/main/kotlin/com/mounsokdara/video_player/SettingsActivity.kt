package com.mounsokdara.video_player

/**
 * Dedicated Settings screen. Starts on the Flutter `/settings` route, which shows a category list
 * on phones and a sidebar + detail pane on large screens. Changes are saved to SharedPreferences;
 * the main screen reloads them on resume.
 */
class SettingsActivity : FlutterPageActivity() {
    override fun getInitialRoute(): String = "/settings"
}
