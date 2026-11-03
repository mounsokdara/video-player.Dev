package com.mounsokdara.video_player.engine

import android.content.Context
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.util.IdentityHashMap

/**
 * Connects our own playback engine (NativePlayer) to one FlutterEngine.
 * The player is created lazily on the first open(), so screens that never play video
 * (Settings, Console, licenses all run as their own Flutter activity) cost nothing.
 */
object EngineBridge {
    const val METHODS = "app.videoplayer/engine"
    const val EVENTS = "app.videoplayer/engine_events"

    private val players = IdentityHashMap<FlutterEngine, NativePlayer>()

    private fun num(a: Map<*, *>, k: String): Number = (a[k] as? Number) ?: 0

    fun register(context: Context, engine: FlutterEngine) {
        val messenger = engine.dartExecutor.binaryMessenger
        val app = context.applicationContext
        var sink: EventChannel.EventSink? = null

        EventChannel(messenger, EVENTS).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(args: Any?, events: EventChannel.EventSink?) { sink = events }
            override fun onCancel(args: Any?) { sink = null }
        })

        fun player(): NativePlayer = players[engine] ?: NativePlayer(app, engine.renderer) { m -> sink?.success(m) }.also {
            players[engine] = it
            PlayerHolder.player = it
        }

        MethodChannel(messenger, METHODS).setMethodCallHandler { call, result ->
            val a = (call.arguments as? Map<*, *>) ?: emptyMap<String, Any>()
            try {
                when (call.method) {
                    "open" -> player().open(
                        a["path"] as String,
                        a["preferSoftware"] as? Boolean ?: false
                    ) { info, err ->
                        if (err != null) result.error("OPEN", err, null) else result.success(info)
                    }
                    "play" -> { player().play(); result.success(null) }
                    "pause" -> { players[engine]?.pause(); result.success(null) }
                    "stop" -> { players[engine]?.stop(); result.success(null) }
                    "seek" -> player().seek(
                        num(a, "positionMs").toLong() * 1000L,
                        a["accurate"] as? Boolean ?: true
                    ) { result.success(null) }
                    "setSpeed" -> { player().setSpeed(num(a, "value").toFloat()); result.success(null) }
                    "setPitch" -> { player().setPitch(num(a, "value").toFloat()); result.success(null) }
                    "setVolume" -> { player().setVolume(num(a, "value").toFloat()); result.success(null) }
                    "setBalance" -> {
                        player().setBalance(num(a, "left").toFloat(), num(a, "right").toFloat())
                        result.success(null)
                    }
                    "setTuning" -> {
                        player().setTuning(num(a, "peak").toInt(), num(a, "gamma").toInt())
                        result.success(null)
                    }
                    "audioSession" -> result.success(players[engine]?.audioSessionId() ?: 0)
                    "diagnose" -> {
                        val path = a["path"] as String
                        val p = player()
                        Thread {
                            p.setDiagnosing(true)
                            val report = try {
                                Diagnostics.run(path)
                            } catch (e: Exception) {
                                "Diagnostics failed: " + e.javaClass.simpleName + ": " + e.message
                            } finally {
                                p.setDiagnosing(false)
                            }
                            android.os.Handler(android.os.Looper.getMainLooper()).post { result.success(report) }
                        }.start()
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("ENGINE", e.message ?: e.toString(), null)
            }
        }
    }

    /** Called when the hosting activity / engine goes away. */
    fun release(engine: FlutterEngine?) {
        if (engine == null) return
        val p = players.remove(engine) ?: return
        if (PlayerHolder.player === p) PlayerHolder.player = null
        p.release()
    }
}
