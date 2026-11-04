package com.mounsokdara.video_player.accessibility.livecaption

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel

object CaptionHub : EventChannel.StreamHandler {
    @Volatile
    private var sink: EventChannel.EventSink? = null
    private val main = Handler(Looper.getMainLooper())

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        sink = events
    }

    override fun onCancel(arguments: Any?) {
        sink = null
    }

    fun emit(payload: Map<String, Any?>) {
        val copy = HashMap(payload)
        main.post {
            try {
                sink?.success(copy)
            } catch (_: Throwable) {
            }
        }
    }
}
