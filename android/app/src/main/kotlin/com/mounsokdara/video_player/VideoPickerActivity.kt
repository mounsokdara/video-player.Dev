package com.mounsokdara.video_player

class VideoPickerActivity : MainActivity() {
    override fun getInitialRoute(): String = "/pick"

    override fun onUserLeaveHint() {
        // Picker is not a player; never enter PiP.
    }
}
