package com.mounsokdara.video_player

import android.media.audiofx.BassBoost
import android.media.audiofx.Equalizer
import android.media.audiofx.Virtualizer
import android.os.Handler
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import java.io.File

class EqualizerController(
    private val activity: FlutterActivity,
    private val engine: () -> FlutterEngine?,
    private val mainHandler: Handler,
    private val breadcrumb: (String) -> Unit,
    private val writeCrash: (String) -> Unit
) {
    private val tenBandHz = NativeConstants.TEN_BAND_HZ
    private var tenBandLevels = IntArray(NativeConstants.EQ_BANDS)
    private var equalizer: Equalizer? = null
    private var bassBoostFx: BassBoost? = null
    private var virtualizerFx: Virtualizer? = null
    private var fxSession = 0
    var blocked = false
        private set

    init {
        blocked = File(activity.filesDir, NativeConstants.FILE_EQ_DIRTY).exists()
        if (blocked) {
            try {
                File(activity.filesDir, NativeConstants.FILE_EQ_DIRTY).delete()
            } catch (_: Exception) {
            }
            breadcrumb("equalizer blocked after previous crash")
        }
    }

    fun audioSessionId(): Int {
        // Our own engine owns the AudioTrack; its session id is what the effects must attach to.
        val own = com.mounsokdara.video_player.engine.PlayerHolder.player?.audioSessionId() ?: 0
        if (own > 0) return own
        val exo = findExoPlayer() ?: return 0
        return try {
            val m = exo.javaClass.methods.firstOrNull { it.name == "getAudioSessionId" && it.parameterCount == 0 }
            (m?.invoke(exo) as? Number)?.toInt() ?: 0
        } catch (_: Throwable) {
            0
        }
    }

    fun release() {
        try { equalizer?.enabled = false } catch (_: Throwable) {}
        try { bassBoostFx?.enabled = false } catch (_: Throwable) {}
        try { virtualizerFx?.enabled = false } catch (_: Throwable) {}
        try { equalizer?.release() } catch (_: Throwable) {}
        try { bassBoostFx?.release() } catch (_: Throwable) {}
        try { virtualizerFx?.release() } catch (_: Throwable) {}
        equalizer = null
        bassBoostFx = null
        virtualizerFx = null
        fxSession = 0
    }

    fun apply(
        enabled: Boolean,
        bands: List<Int>,
        bassOn: Boolean,
        bass: Int,
        surroundOn: Boolean,
        surround: Int,
        retry: Boolean = true
    ) {
        for (i in 0 until minOf(NativeConstants.EQ_BANDS, bands.size)) tenBandLevels[i] = bands[i]
        applyEq(enabled, bands, bassOn, bass, surroundOn, surround)
        if (retry && enabled && equalizer == null && !blocked) {
            mainHandler.postDelayed({
                applyEq(enabled, bands, bassOn, bass, surroundOn, surround)
            }, NativeConstants.EQ_RETRY_MS)
        }
    }

    private fun ensureFx(session: Int): Boolean {
        if (blocked || session <= 0) return false
        if (equalizer != null && fxSession == session) return true
        release()
        val dirty = File(activity.filesDir, NativeConstants.FILE_EQ_DIRTY)
        return try {
            dirty.writeText("eq")
            val eq = Equalizer(0, session)
            equalizer = eq
            fxSession = session
            try {
                bassBoostFx = BassBoost(0, session)
            } catch (_: Throwable) {
            }
            try {
                virtualizerFx = Virtualizer(0, session)
            } catch (_: Throwable) {
            }
            dirty.delete()
            breadcrumb("equalizer attached session=$session bands=${eq.numberOfBands}")
            true
        } catch (t: Throwable) {
            blocked = true
            try { dirty.delete() } catch (_: Exception) {}
            release()
            writeCrash("equalizer attach: ${t.message}\n${android.util.Log.getStackTraceString(t)}")
            false
        }
    }

    private fun interpolateBand(hz: Int, bands: List<Int>): Int {
        if (bands.isEmpty()) return 0
        val last = minOf(bands.size, tenBandHz.size) - 1
        if (last < 0) return 0
        if (hz <= tenBandHz[0]) return bands[0]
        if (hz >= tenBandHz[last]) return bands[last]
        for (i in 0 until last) {
            val a = tenBandHz[i]
            val b = tenBandHz[i + 1]
            if (hz in a..b) {
                val t = (hz - a).toFloat() / (b - a).coerceAtLeast(1).toFloat()
                val va = bands[i]
                val vb = bands[i + 1]
                return (va + (vb - va) * t).toInt()
            }
        }
        return 0
    }

    private fun applyEq(
        enabled: Boolean,
        bands: List<Int>,
        bassOn: Boolean,
        bass: Int,
        surroundOn: Boolean,
        surround: Int
    ) {
        if (!enabled) {
            try { equalizer?.enabled = false } catch (_: Throwable) {}
            try { bassBoostFx?.enabled = false } catch (_: Throwable) {}
            try { virtualizerFx?.enabled = false } catch (_: Throwable) {}
            return
        }
        val session = audioSessionId()
        if (!ensureFx(session)) return
        val eq = equalizer ?: return
        try {
            eq.enabled = true
            val n = eq.numberOfBands.toInt()
            val range = eq.bandLevelRange
            val min = range[0].toInt()
            val max = range[1].toInt()
            for (i in 0 until n) {
                val hz = eq.getCenterFreq(i.toShort()) / 1000
                val milli = interpolateBand(hz, bands).coerceIn(min, max)
                eq.setBandLevel(i.toShort(), milli.toShort())
            }
        } catch (t: Throwable) {
            breadcrumb("eq bands: ${t.message}")
        }
        try {
            bassBoostFx?.setStrength(bass.coerceIn(0, NativeConstants.BASS_MAX).toShort())
            bassBoostFx?.enabled = bassOn
        } catch (_: Throwable) {
        }
        try {
            virtualizerFx?.setStrength(surround.coerceIn(0, NativeConstants.BASS_MAX).toShort())
            virtualizerFx?.enabled = surroundOn
        } catch (_: Throwable) {
        }
    }

    fun setStereoVolume(left: Float, right: Float) {
        val l = left.coerceIn(0f, 1f)
        val r = right.coerceIn(0f, 1f)
        val own = com.mounsokdara.video_player.engine.PlayerHolder.player
        if (own != null) {
            own.setBalance(l, r)
            return
        }
        val exo = findExoPlayer() ?: return
        try {
            val two = exo.javaClass.methods.firstOrNull {
                it.name == "setVolume" && it.parameterCount == 2
            }
            if (two != null) {
                two.invoke(exo, l, r)
                return
            }
        } catch (_: Throwable) {
        }
        try {
            val one = exo.javaClass.methods.firstOrNull {
                it.name == "setVolume" && it.parameterCount == 1
            }
            one?.invoke(exo, maxOf(l, r))
        } catch (_: Throwable) {
        }
        applyAudioTrackBalance(exo, l, r)
    }

    private fun applyAudioTrackBalance(exo: Any, left: Float, right: Float) {
        try {
            val renderers = fieldValue(exo, "renderers") as? Array<*> ?: return
            for (ren in renderers) {
                if (ren == null) continue
                val sink = fieldValue(ren, "audioSink") ?: fieldValue(ren, "sink")
                val track = if (sink != null) {
                    fieldValue(sink, "audioTrack") ?: fieldValue(sink, "track")
                } else {
                    null
                }
                if (track is android.media.AudioTrack) {
                    @Suppress("DEPRECATION")
                    track.setStereoVolume(left, right)
                }
            }
        } catch (_: Throwable) {
        }
    }

    private fun findExoPlayer(): Any? {
        val engine = engine() ?: return null
        return try {
            val registry = engine.plugins
            val map = fieldValue(registry, "map") ?: fieldValue(registry, "pluginMap") ?: fieldValue(registry, "plugins")
            val plugins: Collection<Any?> = when (map) {
                is Map<*, *> -> map.values
                else -> emptyList()
            }
            for (plugin in plugins) {
                if (plugin == null) continue
                val name = plugin.javaClass.name
                if (!name.contains("videoplayer", ignoreCase = true)) continue
                val array = fieldValue(plugin, "videoPlayers") ?: continue
                val wrapper = lastSparseValue(array) ?: continue
                val exo = fieldValue(wrapper, "exoPlayer")
                    ?: fieldValue(wrapper, "player")
                    ?: fieldValue(wrapper, "exo")
                if (exo != null) return exo
            }
            null
        } catch (_: Throwable) {
            null
        }
    }

    @Suppress("DiscouragedPrivateApi")
    private fun findField(obj: Any, name: String): java.lang.reflect.Field? {
        var c: Class<*>? = obj.javaClass
        while (c != null) {
            try {
                val f = c.getDeclaredField(name)
                @Suppress("DEPRECATION")
                f.isAccessible = true
                return f
            } catch (_: NoSuchFieldException) {
                c = c.superclass
            }
        }
        return null
    }

    private fun fieldValue(obj: Any, name: String): Any? {
        return try {
            findField(obj, name)?.get(obj)
        } catch (_: Throwable) {
            null
        }
    }

    private fun lastSparseValue(array: Any): Any? {
        return try {
            val size = array.javaClass.getMethod("size").invoke(array) as Int
            if (size <= 0) return null
            array.javaClass.getMethod("valueAt", Int::class.javaPrimitiveType)
                .invoke(array, size - 1)
        } catch (_: Throwable) {
            null
        }
    }
}
