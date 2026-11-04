package com.mounsokdara.video_player.engine

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTimestamp
import android.media.AudioTrack
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaCodecList
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.PlaybackParams
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.view.Surface
import io.flutter.view.TextureRegistry
import java.io.ByteArrayOutputStream
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import kotlin.math.max

/** No decoder on this device can handle the stream at all (not a transient failure). */
class UnsupportedStreamException(message: String) : Exception(message)

object PlayerHolder {
    @Volatile
    var player: NativePlayer? = null
}

/**
 * Our own playback engine. No third-party player code:
 *   MediaExtractor (demux)  ->  MediaCodec (decode)  ->  Surface / AudioTrack (output)
 *
 * Everything runs on one player thread, so there is no locking. Video renders straight to a
 * SurfaceView (the system compositor does HDR / tone mapping). Audio goes to an AudioTrack, which
 * is also the master clock; AudioTrack.PlaybackParams gives independent speed and pitch.
 */
class NativePlayer(
    ctx: Context,
    private val textures: TextureRegistry,
    private val sink: (Map<String, Any?>) -> Unit,
) {
    private val thread = HandlerThread("native-player").also { it.start() }
    private val h = Handler(thread.looper)
    private val main = Handler(Looper.getMainLooper())
    private val appCtx = ctx.applicationContext
    private val audioManager = appCtx.getSystemService(Context.AUDIO_SERVICE) as AudioManager

    private var released = false
    private var opened = false

    // ---- media ----
    private var vEx: MediaExtractor? = null
    private var aEx: MediaExtractor? = null
    private var vFormat: MediaFormat? = null
    private var aFormat: MediaFormat? = null
    private var vCodec: MediaCodec? = null
    private var aCodec: MediaCodec? = null
    private var durationUs = 0L

    // The decoder renders into a Flutter texture we own (valid for the whole file), not a view's surface.
    private var producer: TextureRegistry.SurfaceProducer? = null
    private var codecSurface: Surface? = null

    // Software path (FFmpeg decode) for streams no phone decoder supports, e.g. HEVC Main 10.
    private var softwareMode = false
    private var stEntry: TextureRegistry.SurfaceTextureEntry? = null
    private var stSurface: Surface? = null
    private var sw = 0L
    private var swBuf: java.nio.ByteBuffer? = null
    private var swHave = false
    private var swPts = 0L
    private var swEos = false
    private var swSkip = 0

    // ---- transport ----
    private var playing = false
    private var atEnd = false
    private var speed = 1f
    private var pitch = 1f
    private var pausedUs = 0L
    private var anchorUs = 0L
    private var anchorNs = 0L

    // ---- seek ----
    private var skipBeforeUs = Long.MIN_VALUE
    private var needFirstFrame = true
    private var seekDone: (() -> Unit)? = null
    private var seekStartNs = 0L

    // ---- video pipeline ----
    private val vInfo = MediaCodec.BufferInfo()
    private var vInEos = false
    private var vOutDone = false
    private var pendingV = -1
    private var pendingVPts = 0L
    private var pendingVFlags = 0
    private var lastRenderNs = 0L

    // ---- audio pipeline ----
    private val aInfo = MediaCodec.BufferInfo()
    private var aInEos = false
    private var aOutDone = false
    private var pendingA = -1
    private var pendingAOff = 0
    private var pendingARemain = 0
    private var pendingAPts = 0L
    private var pendingAFlags = 0
    private var track: AudioTrack? = null
    private var sampleRate = 48000
    private var bytesPerFrame = 4
    private var audioBaseSet = false
    private var audioBaseUs = 0L
    private var headBase = 0L
    private var audioStarted = false
    private var writtenSinceFlush = 0L
    private val ts = AudioTimestamp()

    private var lastEmitNs = 0L
    private var lastVOutNs = 0L
    private var lastAOutNs = 0L

    // Volume / balance / effects session (the app's equalizer attaches to this session id).
    @Volatile private var audioSession = 0
    private var volume = 1f
    private var balL = 1f
    private var balR = 1f
    private var tunePeak = 203
    private var tuneGamma = 0
    private var decoderName = ""
    private val badDecoders = HashSet<String>()
    private val decoderLog = StringBuilder()
    private var videoDisabled = false
    private var audioDisabled = false

    init {
        h.post(object : Runnable {
            override fun run() {
                if (released) return
                var busy = false
                try {
                    busy = tick()
                } catch (e: Exception) {
                    fail(e)
                }
                h.postDelayed(this, if (busy) 2L else 10L)
            }
        })
    }

    // =====================================================================================
    // Public API (any thread)
    // =====================================================================================

    fun open(source: String, preferSoftware: Boolean, done: (Map<String, Any?>?, String?) -> Unit) {
        h.post {
            try {
                teardown()
                val info = doOpen(source, preferSoftware)
                main.post { done(info, null) }
            } catch (e: Exception) {
                teardown()
                val msg = describe(e)
                main.post { done(null, msg) }
            }
        }
    }

    fun audioSessionId(): Int = audioSession

    fun setVolume(v: Float) {
        h.post {
            volume = v.coerceIn(0f, 1f)
            applyVolume()
        }
    }

    fun setBalance(l: Float, r: Float) {
        h.post {
            balL = l.coerceIn(0f, 1f)
            balR = r.coerceIn(0f, 1f)
            applyVolume()
        }
    }

    @Suppress("DEPRECATION")
    private fun applyVolume() {
        quiet { track?.setStereoVolume(volume * balL, volume * balR) }
    }

    /** HDR -> SDR tuning for the software path: peak in nits (203 = SDR white), gamma -100..100. */
    fun setTuning(peakNits: Int, gammaPct: Int) {
        h.post {
            tunePeak = peakNits
            tuneGamma = gammaPct
            if (sw != 0L) SwNative.nSetTuning(sw, tunePeak, tuneGamma)
        }
    }

    /** Stops and frees the current file but keeps the player usable for the next open(). */
    fun stop() { h.post { teardown() } }

    fun play() { h.post { doPlay() } }

    fun pause() { h.post { doPause() } }

    /** done() is called after the first frame following the seek is on screen (or on timeout). */
    fun seek(positionUs: Long, accurate: Boolean, done: () -> Unit) {
        h.post {
            finishSeek() // a newer seek supersedes the older one
            seekDone = { main.post { done() } }
            if (!opened) {
                finishSeek()
            } else {
                val max = if (durationUs > 0) durationUs else Long.MAX_VALUE
                doSeek(positionUs.coerceIn(0L, max), accurate)
            }
        }
    }

    fun setSpeed(v: Float) {
        h.post {
            val c = if (opened) clockUs() else 0L
            anchorUs = c
            anchorNs = System.nanoTime()
            speed = v
            applyParams()
        }
    }

    fun setPitch(v: Float) {
        h.post {
            pitch = v
            applyParams()
        }
    }

    /** Frees the video decoder (and keeps it free) so the decoder test can use it. Blocks briefly. */
    fun setDiagnosing(on: Boolean) {
        val latch = CountDownLatch(1)
        h.post {
            try {
                diagnosing = on
                if (on) {
                    val at = if (playing) clockUs() else pausedUs
                    if (playing) doPause()
                    pausedUs = at
                    dropVideoCodec()
                } else {
                    needFirstFrame = vFormat != null
                }
            } finally {
                latch.countDown()
            }
        }
        latch.await(1500, TimeUnit.MILLISECONDS)
    }

    fun release() {
        h.post {
            released = true
            teardown()
            thread.quitSafely()
        }
    }

    // =====================================================================================
    // Open / teardown
    // =====================================================================================

    /** Class, message, codec error details and the first frame in our own code. */
    private fun describe(e: Throwable): String {
        val sb = StringBuilder(e.javaClass.simpleName)
        e.message?.let { sb.append(": ").append(it) }
        if (e is MediaCodec.CodecException) {
            sb.append(" [code=").append(e.errorCode).append(" recoverable=").append(e.isRecoverable)
            e.diagnosticInfo.let { d -> sb.append(" ").append(d) }
            sb.append("]")
        }
        val frames = e.stackTrace.take(4).joinToString(" < ") {
            it.className.substringAfterLast('.') + "." + it.methodName + ":" + it.lineNumber
        }
        if (frames.isNotEmpty()) sb.append(" {").append(frames).append("}")
        return sb.toString()
    }

    /** Flutter texture calls belong on the platform thread; block briefly until they ran. */
    private fun <T> onMain(block: () -> T): T {
        if (Looper.myLooper() == Looper.getMainLooper()) return block()
        val latch = CountDownLatch(1)
        var out: Result<T>? = null
        main.post {
            out = runCatching(block)
            latch.countDown()
        }
        if (!latch.await(3, TimeUnit.SECONDS)) throw IllegalStateException("Timed out waiting for the UI thread")
        return out!!.getOrThrow()
    }

    /** True when the stream is 10-bit HEVC and no decoder on this phone lists a 10-bit profile. */
    private fun noHardwareFor(f: MediaFormat): Boolean {
        val mime = f.getString(MediaFormat.KEY_MIME) ?: return false
        if (!mime.equals("video/hevc", true) || !f.containsKey(MediaFormat.KEY_PROFILE)) return false
        val p = f.getInteger(MediaFormat.KEY_PROFILE)
        if (!(p == 2 || p == 4096 || p == 8192)) return false
        val any = MediaCodecList(MediaCodecList.REGULAR_CODECS).codecInfos.any { info ->
            !info.isEncoder && info.supportedTypes.any { t -> t.equals(mime, true) } && try {
                info.getCapabilitiesForType(mime).profileLevels.any { it.profile == 2 || it.profile == 4096 || it.profile == 8192 }
            } catch (ignored: Exception) {
                false
            }
        }
        return !any
    }

    private inline fun quiet(block: () -> Unit) {
        try {
            block()
        } catch (ignored: Exception) {
        }
    }

    private fun MediaFormat.durationUs(): Long =
        if (containsKey(MediaFormat.KEY_DURATION)) getLong(MediaFormat.KEY_DURATION) else 0L

    private fun attach(ex: MediaExtractor, src: String) {
        when {
            src.startsWith("content://") || src.startsWith("android.resource://") ->
                ex.setDataSource(appCtx, Uri.parse(src), null)
            src.startsWith("http://") || src.startsWith("https://") ->
                ex.setDataSource(src, HashMap<String, String>())
            else -> ex.setDataSource(src.removePrefix("file://"))
        }
    }

    private fun intOrNull(f: MediaFormat, k: String): Int? =
        if (f.containsKey(k)) try { f.getInteger(k) } catch (e: Exception) { null } else null

    private fun fpsOf(f: MediaFormat): Double {
        if (f.containsKey(MediaFormat.KEY_FRAME_RATE)) {
            try { return f.getInteger(MediaFormat.KEY_FRAME_RATE).toDouble() } catch (e: Exception) {}
            try { return f.getFloat(MediaFormat.KEY_FRAME_RATE).toDouble() } catch (e: Exception) {}
        }
        val frames = try { if (f.containsKey("frame-count")) f.getInteger("frame-count") else 0 } catch (e: Exception) { 0 }
        val dur = f.durationUs()
        return if (frames > 0 && dur > 0) frames * 1_000_000.0 / dur else 0.0
    }

    /** Bit depth from the codec profile (MediaExtractor does not expose it directly). */
    private fun bitDepthOf(mime: String, p: Int?): Int {
        if (mime.contains("dolby-vision")) return 10
        if (p == null) return 8
        return when {
            mime.endsWith("hevc") || mime.endsWith("av01") -> if (p == 2 || p == 4096 || p == 8192 || p == 0x4000) 10 else 8
            mime.endsWith("vp9") -> if (p == 4 || p == 8 || p == 4096 || p == 8192 || p == 16384) 10 else 8
            mime.endsWith("avc") -> if (p == 16 || p == 32 || p == 64) 10 else 8
            else -> 8
        }
    }

    private fun softwareCodecId(mime: String): Int = when {
        mime.equals("video/hevc", true) -> 0
        mime.equals("video/avc", true) -> 1
        else -> -1
    }

    private fun createHardwareOutput(w: Int, hgt: Int) {
        producer = onMain {
            val created = textures.createSurfaceProducer()
            created.setSize(w, hgt)
            created
        }
        softwareMode = false
    }

    private fun releaseHardwareOutput() {
        dropVideoCodec()
        producer?.let { p -> quiet { onMain { p.release() } } }
        producer = null
    }

    /** CPU-written frames: a SurfaceTexture entry accepts ANativeWindow_lock writes. */
    private fun createSoftwareOutput(w: Int, hgt: Int) {
        val pair = onMain {
            val e = textures.createSurfaceTexture()
            e.surfaceTexture().setDefaultBufferSize(w, hgt)
            Pair(e, Surface(e.surfaceTexture()))
        }
        stEntry = pair.first
        stSurface = pair.second
        softwareMode = true
    }

    private fun doOpen(source: String, preferSoftware: Boolean): Map<String, Any?> {
        val ex = MediaExtractor()
        attach(ex, source)
        var vi = -1
        var ai = -1
        for (i in 0 until ex.trackCount) {
            val mime = ex.getTrackFormat(i).getString(MediaFormat.KEY_MIME) ?: continue
            if (vi < 0 && mime.startsWith("video/")) vi = i
            else if (ai < 0 && mime.startsWith("audio/")) ai = i
        }
        if (vi < 0 && ai < 0) {
            ex.release()
            throw IllegalStateException("No playable audio or video track")
        }
        if (vi >= 0) {
            ex.selectTrack(vi)
            vEx = ex
            vFormat = ex.getTrackFormat(vi)
        } else {
            ex.release()
        }

        audioSession = try { audioManager.generateAudioSessionId() } catch (e: Exception) { 0 }
        if (audioSession <= 0) audioSession = 0
        if (ai >= 0) {
            val ex2 = MediaExtractor()
            attach(ex2, source)
            ex2.selectTrack(ai)
            aEx = ex2
            aFormat = ex2.getTrackFormat(ai)
            aCodec = createDecoder(aFormat!!, null)
        }

        durationUs = max(vFormat?.durationUs() ?: 0L, aFormat?.durationUs() ?: 0L)
        badDecoders.clear(); decoderLog.setLength(0); videoDisabled = false; audioDisabled = false
        playing = false
        atEnd = false
        pausedUs = 0L
        anchorUs = 0L
        anchorNs = System.nanoTime()
        skipBeforeUs = Long.MIN_VALUE
        needFirstFrame = vFormat != null
        lastVOutNs = System.nanoTime(); lastAOutNs = lastVOutNs
        vInEos = false; vOutDone = false; pendingV = -1
        aInEos = false; aOutDone = false; pendingA = -1
        audioBaseSet = false; audioStarted = false; writtenSinceFlush = 0
        opened = true

        val vf = vFormat
        var w = 0
        var hgt = 0
        var rot = 0
        var textureId = -1L
        var mime = ""
        var profile: Int? = null
        var maxLum = 0.0
        var maxCll = 0.0
        if (vf != null) {
            mime = vf.getString(MediaFormat.KEY_MIME) ?: ""
            w = intOrNull(vf, MediaFormat.KEY_WIDTH) ?: 0
            hgt = intOrNull(vf, MediaFormat.KEY_HEIGHT) ?: 0
            rot = intOrNull(vf, MediaFormat.KEY_ROTATION) ?: 0
            profile = intOrNull(vf, MediaFormat.KEY_PROFILE)
            // Texture consumers ignore the codec's rotation hint, so Flutter rotates instead.
            if (vf.containsKey(MediaFormat.KEY_ROTATION)) vf.setInteger(MediaFormat.KEY_ROTATION, 0)
            if (vf.containsKey(MediaFormat.KEY_HDR_STATIC_INFO)) {
                val b = vf.getByteBuffer(MediaFormat.KEY_HDR_STATIC_INFO)!!.duplicate().order(java.nio.ByteOrder.LITTLE_ENDIAN)
                if (b.limit() >= 25 && b.get(0).toInt() == 0) {
                    maxLum = (b.getShort(17).toInt() and 0xFFFF).toDouble()
                    maxCll = (b.getShort(21).toInt() and 0xFFFF).toDouble()
                }
            }

            // Pick the decoder now so a failure is reported by open() and the app can retry.
            val canSoft = SwNative.available && softwareCodecId(mime) >= 0
            // Streams whose width is not a multiple of 16 (e.g. 886x1920 screen recordings) get a
            // padded decoder buffer. The hardware surface path can show that padding as a green
            // strip on the right edge, so decode those in software, which writes exact-size frames.
            val unalignedWidth = w > 0 && w % 16 != 0
            var wantSw = canSoft && (preferSoftware || noHardwareFor(vf) || unalignedWidth)
            if (!wantSw) {
                createHardwareOutput(w, hgt)
                try {
                    startHardwareVideo(vf)
                } catch (e: Exception) {
                    if (!canSoft) throw e
                    releaseHardwareOutput()
                    wantSw = true
                }
            }
            if (wantSw) {
                createSoftwareOutput(w, hgt)
                startSoftwareVideo(vf)
            }
            textureId = if (softwareMode) stEntry!!.id() else producer!!.id()
        }
        return mapOf(
            "durationMs" to durationUs / 1000,
            "width" to w,
            "height" to hgt,
            "rotation" to rot,
            "textureId" to textureId,
            "hasVideo" to (vf != null),
            "hasAudio" to (aFormat != null),
            "mime" to mime,
            "fps" to (if (vf != null) fpsOf(vf) else 0.0),
            "colorStandard" to (if (vf != null) intOrNull(vf, MediaFormat.KEY_COLOR_STANDARD) else null),
            "colorTransfer" to (if (vf != null) intOrNull(vf, MediaFormat.KEY_COLOR_TRANSFER) else null),
            "colorRange" to (if (vf != null) intOrNull(vf, MediaFormat.KEY_COLOR_RANGE) else null),
            "bitDepth" to bitDepthOf(mime, profile),
            "maxLuminance" to maxLum,
            "maxCll" to maxCll,
            "decoder" to (decoderName + decoderNote),
            "software" to softwareMode,
            "audioSession" to audioSession,
        )
    }

    private fun teardown() {
        val hadHardware = vCodec != null
        opened = false
        playing = false
        atEnd = false
        dropVideoCodec()
        // MediaTek decoders free their hardware slot asynchronously; opening the next video
        // right away could crash inside the native decoder. Give it a moment to settle.
        if (hadHardware) quiet { Thread.sleep(60) }
        aCodec?.let { c ->
            quiet { c.stop() }
            quiet { c.release() }
        }
        aCodec = null
        track?.let { t ->
            quiet { t.pause(); t.flush() }
            quiet { t.release() }
        }
        track = null
        quiet { vEx?.release() }
        quiet { aEx?.release() }
        producer?.let { p -> quiet { onMain { p.release() } } }
        producer = null
        stSurface?.let { quiet { it.release() } }
        stEntry?.let { e -> quiet { onMain { e.release() } } }
        stSurface = null; stEntry = null; softwareMode = false
        vEx = null; aEx = null; vFormat = null; aFormat = null
        pendingA = -1; pendingV = -1
        audioBaseSet = false; audioStarted = false
        finishSeek()
        audioSession = 0
    }

    private fun dropVideoCodec() {
        vCodec?.let { c ->
            quiet { c.stop() }
            quiet { c.release() }
        }
        vCodec = null
        codecSurface = null
        pendingV = -1
        if (sw != 0L) {
            SwNative.nRelease(sw)
            sw = 0L
        }
        swHave = false
    }

    // =====================================================================================
    // Decoder selection: hardware first, then software, no third-party fallback needed
    // =====================================================================================

    private fun isSoftware(i: MediaCodecInfo): Boolean =
        if (Build.VERSION.SDK_INT >= 29) i.isSoftwareOnly
        else i.name.startsWith("OMX.google.") || i.name.startsWith("c2.android.")

    private var decoderKey = ""
    @Volatile private var stage = ""
    @Volatile private var diagnosing = false
    private var decoderNote = ""

    private fun createDecoder(f: MediaFormat, s: Surface?): MediaCodec {
        val mime = f.getString(MediaFormat.KEY_MIME) ?: throw IllegalStateException("No mime")
        val candidates = MediaCodecList(MediaCodecList.REGULAR_CODECS).codecInfos
            .filter { !it.isEncoder && it.supportedTypes.any { t -> t.equals(mime, true) } }
            .sortedBy { info ->
                val claims = try {
                    info.getCapabilitiesForType(mime).isFormatSupported(f)
                } catch (ignored: Exception) {
                    false
                }
                (if (isSoftware(info)) 2 else 0) + (if (claims) 0 else 1)
            }
        // 10-bit HEVC (Main 10 / HDR10 / HDR10+): if no decoder lists such a profile, nothing below can work.
        val candidatesToTry = if (mime.equals("video/hevc", true) && f.containsKey(MediaFormat.KEY_PROFILE) &&
            f.getInteger(MediaFormat.KEY_PROFILE).let { it == 2 || it == 4096 || it == 8192 }
        ) {
            fun has10bit(info: MediaCodecInfo) = try {
                info.getCapabilitiesForType(mime).profileLevels.any { it.profile == 2 || it.profile == 4096 || it.profile == 8192 }
            } catch (ignored: Exception) {
                false
            }
            val capable = candidates.filter { has10bit(it) }
            if (capable.isEmpty()) {
                val list = candidates.joinToString("; ") { info ->
                    val profiles = try {
                        info.getCapabilitiesForType(mime).profileLevels.map { it.profile }.distinct().joinToString(",") {
                            when (it) { 1 -> "Main"; 2 -> "Main10"; 4 -> "MainStill"; 4096 -> "Main10HDR10"; 8192 -> "Main10HDR10Plus"; else -> "p$it" }
                        }
                    } catch (ignored: Exception) {
                        "?"
                    }
                    "${info.name} (${if (isSoftware(info)) "software" else "hardware"}): $profiles"
                }
                throw UnsupportedStreamException(
                    "This phone has no decoder for 10-bit HEVC (Main 10 / HDR10), which this video uses. " +
                        "Its HEVC decoders only support: $list. A software decoder would be needed."
                )
            }
            capable
        } else {
            candidates
        }
        val fails = StringBuilder()
        for (info in candidatesToTry) {
            val variants = codecConfigVariants(f, mime)
            for ((idx, fmt) in variants.withIndex()) {
                val key = "${info.name}#$idx"
                if (key in badDecoders) continue
                var c: MediaCodec? = null
                try {
                    c = MediaCodec.createByCodecName(info.name)
                    c.configure(fmt, s, null, 0)
                    c.start()
                    decoderName = info.name
                    decoderKey = key
                    decoderNote = if (idx == 0) "" else " (" + variantName(idx) + ")"
                    return c
                } catch (e: Exception) {
                    fails.append("\n").append(key).append(": ").append(describe(e))
                    quiet { c?.release() }
                }
            }
        }
        throw IllegalStateException("No decoder could start $mime$fails")
    }

    private fun ensureVideoCodec() {
        if (videoDisabled || diagnosing) return
        if (softwareMode) {
            ensureSoftware()
            return
        }
        val f = vFormat ?: return
        val s = producer?.surface ?: return
        if (vCodec != null || !s.isValid) return
        try {
            startHardwareVideo(f)
        } catch (e: Exception) {
            disableVideo(e)
        }
    }

    /** Creates the decoder on the engine-owned texture. Throws if no decoder can take the stream. */
    private fun startHardwareVideo(f: MediaFormat) {
        val s = producer?.surface ?: throw IllegalStateException("No output surface")
        val at = if (playing) clockUs() else pausedUs
        vCodec = createDecoder(f, s)
        codecSurface = s
        emit(mapOf("type" to "decoder", "name" to decoderName + decoderNote))
        quiet { vEx?.seekTo(at, MediaExtractor.SEEK_TO_PREVIOUS_SYNC) }
        skipBeforeUs = at
        vInEos = false; vOutDone = false; pendingV = -1
        needFirstFrame = true
        lastVOutNs = System.nanoTime()
        seekStartNs = System.nanoTime()
    }

    private fun ensureSoftware() {
        if (sw != 0L || vFormat == null) return
        try {
            startSoftwareVideo(vFormat!!)
        } catch (e: Exception) {
            disableVideo(e)
        }
    }

    /** Starts the FFmpeg decoder writing into the SurfaceTexture. Throws on failure. */
    private fun startSoftwareVideo(f: MediaFormat) {
        val surf = stSurface ?: throw IllegalStateException("No output surface")
        val mime = f.getString(MediaFormat.KEY_MIME) ?: ""
        val codecId = softwareCodecId(mime)
        if (codecId < 0) throw UnsupportedStreamException("No software decoder for $mime")
        val csd = ByteArrayOutputStream()
        for (k in listOf("csd-0", "csd-1")) {
            if (f.containsKey(k)) {
                val bb = f.getByteBuffer(k)!!.duplicate()
                val bytes = ByteArray(bb.remaining())
                bb.get(bytes)
                csd.write(bytes)
            }
        }
        val threads = Runtime.getRuntime().availableProcessors()
        val handle = SwNative.nCreate(csd.toByteArray(), threads, codecId)
        if (handle == 0L) throw UnsupportedStreamException("The software decoder could not start for this stream.")
        SwNative.nSetSurface(handle, surf)
        SwNative.nSetTuning(handle, tunePeak, tuneGamma)
        sw = handle
        val maxIn = intOrNull(f, MediaFormat.KEY_MAX_INPUT_SIZE) ?: 0
        swBuf = java.nio.ByteBuffer.allocateDirect(max(maxIn, 2 * 1024 * 1024))
        decoderName = "software (FFmpeg ${if (codecId == 0) "HEVC" else "H.264"}, $threads threads)"
        decoderNote = ""
        emit(mapOf("type" to "decoder", "name" to decoderName))
        val at = if (playing) clockUs() else pausedUs
        quiet { vEx?.seekTo(at, MediaExtractor.SEEK_TO_PREVIOUS_SYNC) }
        skipBeforeUs = at
        swHave = false; swEos = false; swSkip = 0
        vOutDone = false
        needFirstFrame = true
        seekStartNs = System.nanoTime()
    }

    /** Decode a few frames per tick, present the ones that are due, drop the late ones. */
    private fun swStep() {
        val h = sw
        val ex = vEx ?: return
        val buf = swBuf ?: return
        val t0 = System.nanoTime()
        var frames = 0
        while (frames < 3 && System.nanoTime() - t0 < 25_000_000L) {
            stage = "sw.receive"
            if (!swHave) {
                val r = SwNative.nReceive(h)
                if (r == SwNative.NONE) {
                    if (swEos) {
                        vOutDone = true
                        if (needFirstFrame) { needFirstFrame = false; finishSeek() }
                        return
                    }
                    stage = "sw.readSample"
                    buf.clear()
                    val size = ex.readSampleData(buf, 0)
                    stage = "sw.send"
                    if (size < 0) {
                        SwNative.nSendEos(h)
                        swEos = true
                    } else {
                        val rc = SwNative.nSend(h, buf, size, ex.sampleTime)
                        ex.advance()
                        if (rc < 0) throw IllegalStateException("software decoder rejected a packet (error $rc)")
                    }
                    continue
                }
                if (r == SwNative.EOS) {
                    vOutDone = true
                    swEos = true
                    if (needFirstFrame) { needFirstFrame = false; finishSeek() }
                    return
                }
                if (r == SwNative.ERR) throw IllegalStateException("software decoder error")
                swPts = r
                swHave = true
            }
            stage = "sw.present"
            if (swPts < skipBeforeUs) {
                SwNative.nDrop(h); swHave = false
                continue
            }
            val now = System.nanoTime()
            if (needFirstFrame) {
                SwNative.nPresent(h)
                swHave = false
                lastRenderNs = now
                pausedUs = swPts
                anchorUs = swPts
                anchorNs = now
                needFirstFrame = false
                finishSeek()
                if (!playing) return
                frames++
                continue
            }
            if (!playing) return
            val delayUs = ((swPts - clockUs()).toDouble() / speed).toLong()
            if (delayUs > 15_000L) return
            // Falling behind: stop decoding non-reference frames until we catch up.
            if (delayUs < -250_000L && swSkip != 1) { SwNative.nSetSkip(h, 1); swSkip = 1 }
            else if (delayUs > -60_000L && swSkip != 0) { SwNative.nSetSkip(h, 0); swSkip = 0 }
            if (delayUs < -40_000L && now - lastRenderNs < 250_000_000L) {
                SwNative.nDrop(h)
            } else {
                SwNative.nPresent(h)
                lastRenderNs = now
            }
            swHave = false
            frames++
        }
    }

    private fun onSwError(e: Exception) {
        decoderLog.append("software (runtime @").append(stage).append("): ").append(describe(e)).append('\n')
        if (sw != 0L) { SwNative.nRelease(sw); sw = 0L }
        swHave = false
        videoDisabled = true
        needFirstFrame = false
        finishSeek()
        emit(mapOf("type" to "error", "message" to "Software decoder failed at [$stage]: ${describe(e)}", "fatal" to (aCodec == null)))
    }

    /** A decoder died mid-stream: remember it and let ensureVideoCodec() pick the next candidate. */
    private fun onVideoError(e: Exception) {
        val name = decoderKey
        decoderLog.append(name).append(" (runtime @").append(stage).append("): ").append(describe(e)).append('\n')
        badDecoders.add(decoderKey)
        dropVideoCodec()
        emit(mapOf("type" to "error", "message" to "Decoder $name failed while decoding at [$stage] (${describe(e)}), trying the next one"))
    }

    /** No decoder works: keep going audio-only instead of dying. */
    private fun disableVideo(e: Exception) {
        videoDisabled = true
        needFirstFrame = false
        finishSeek()
        if (e is UnsupportedStreamException) {
            emit(mapOf("type" to "error", "message" to (e.message ?: "No decoder for this video"), "fatal" to (aCodec == null)))
            return
        }
        val log = if (decoderLog.isNotEmpty()) "\n" + decoderLog.toString().trim() else ""
        emit(mapOf("type" to "error", "message" to "No working video decoder: ${describe(e)}$log", "fatal" to (aCodec == null)))
    }

    private fun onAudioError(e: Exception) {
        val now = clockUs()
        audioDisabled = true
        aCodec?.let { c ->
            quiet { c.stop() }
            quiet { c.release() }
        }
        aCodec = null
        track?.let { t ->
            quiet { t.pause() }
            quiet { t.release() }
        }
        track = null
        audioStarted = false
        anchorUs = now
        anchorNs = System.nanoTime()
        emit(mapOf("type" to "error", "message" to "Audio disabled at [$stage]: ${describe(e)}"))
    }

    // =====================================================================================
    // Transport
    // =====================================================================================

    private fun doPlay() {
        if (!opened || playing) return
        if (atEnd) doSeek(0L, true)
        playing = true
        anchorUs = pausedUs
        anchorNs = System.nanoTime()
        emitState()
    }

    private fun doPause() {
        if (!playing) return
        pausedUs = clockUs()
        playing = false
        quiet { track?.pause() }
        audioStarted = false
        emitState()
    }

    /** A seek onto the very end is simply "the video ended": no decoding, same result as playing out. */
    private fun seekToEnd() {
        quiet { if (pendingV >= 0) vCodec?.releaseOutputBuffer(pendingV, false) }
        quiet { if (pendingA >= 0) aCodec?.releaseOutputBuffer(pendingA, false) }
        pendingV = -1; pendingA = -1
        needFirstFrame = false
        quiet { track?.pause(); track?.flush() }
        audioBaseSet = false; audioStarted = false; writtenSinceFlush = 0
        finishSeek()
        finish()
    }

    private fun doSeek(target: Long, wantAccurate: Boolean) {
        if (opened && durationUs > 0 && target >= durationUs - 500_000L) {
            seekToEnd()
            return
        }
        // A keyframe-only seek in the last seconds lands on an earlier keyframe, so playback
        // jumped back "a few seconds". Near the end always seek to the exact spot instead.
        val accurate = wantAccurate || (durationUs > 0 && target >= durationUs - 4_000_000L)
        val t = target
        atEnd = false
        pausedUs = t
        skipBeforeUs = if (accurate) t else Long.MIN_VALUE
        quiet {
            vEx?.seekTo(t, if (accurate) MediaExtractor.SEEK_TO_PREVIOUS_SYNC else MediaExtractor.SEEK_TO_CLOSEST_SYNC)
        }
        quiet { aEx?.seekTo(t, MediaExtractor.SEEK_TO_CLOSEST_SYNC) }
        quiet { vCodec?.flush() }
        if (sw != 0L) {
            SwNative.nFlush(sw)
            swHave = false
            swEos = false
        }
        pendingV = -1; vInEos = false; vOutDone = false
        quiet { aCodec?.flush() }
        pendingA = -1; aInEos = false; aOutDone = false
        quiet {
            track?.pause()
            track?.flush()
        }
        audioBaseSet = false; audioStarted = false; writtenSinceFlush = 0
        needFirstFrame = vFormat != null
        lastVOutNs = System.nanoTime(); lastAOutNs = lastVOutNs
        anchorUs = t
        anchorNs = System.nanoTime()
        seekStartNs = System.nanoTime()
        if (vFormat == null) finishSeek()
        emitState()
    }

    private fun finishSeek() {
        val cb = seekDone
        seekDone = null
        cb?.invoke()
    }

    private fun finish() {
        playing = false
        atEnd = true
        pausedUs = durationUs
        quiet { track?.pause() }
        audioStarted = false
        emit(mapOf("type" to "ended"))
        emitState()
    }

    private fun fail(e: Exception) {
        playing = false
        quiet { track?.pause() }
        emit(mapOf("type" to "error", "message" to describe(e), "fatal" to true))
        emitState()
    }

    // =====================================================================================
    // Clock
    // =====================================================================================

    /** Media time "now". Audio-master when the AudioTrack reports timestamps, wall clock otherwise. */
    private fun clockUs(): Long {
        if (!opened) return 0L
        if (!playing) return pausedUs
        val now = System.nanoTime()
        val t = track
        if (t != null && audioStarted && audioBaseSet) {
            try {
                if (t.getTimestamp(ts)) {
                    val frames = ts.framePosition - headBase
                    if (frames >= 0) {
                        val atTs = audioBaseUs + frames * 1_000_000L / sampleRate
                        val us = atTs + ((now - ts.nanoTime) / 1000.0 * speed).toLong()
                        anchorUs = us
                        anchorNs = now
                        return us
                    }
                }
            } catch (ignored: Exception) {
            }
        }
        return anchorUs + ((now - anchorNs) / 1000.0 * speed).toLong()
    }

    private fun positionUs(): Long {
        val p = if (playing) clockUs() else pausedUs
        return if (durationUs > 0) p.coerceIn(0L, durationUs) else max(p, 0L)
    }

    // =====================================================================================
    // Main loop
    // =====================================================================================

    private fun tick(): Boolean {
        if (!opened) return false
        val cur = producer?.surface
        if (!softwareMode && vCodec != null && cur !== codecSurface) dropVideoCodec()
        ensureVideoCodec()

        // A seek whose frame never shows (no surface, slow software decode) must still complete.
        if (seekDone != null && System.nanoTime() - seekStartNs > 1_500_000_000L) finishSeek()

        if (playing || needFirstFrame) {
            try {
                if (softwareMode) {
                    if (sw != 0L) swStep()
                } else {
                    vInEos = feed(vEx, vCodec, vInEos, "video")
                    drainVideo()
                }
            } catch (e: Exception) {
                if (softwareMode) onSwError(e) else onVideoError(e)
            }
        }
        if (playing) {
            try {
                aInEos = feed(aEx, aCodec, aInEos, "audio")
                drainAudio()
            } catch (e: Exception) {
                onAudioError(e)
            }
            checkEnded()
        }
        val now = System.nanoTime()
        if (playing && now - lastEmitNs > 100_000_000L) emitState()
        return playing || (needFirstFrame && (vCodec != null || sw != 0L))
    }

    private fun feed(ex: MediaExtractor?, c: MediaCodec?, eos: Boolean, tag: String): Boolean {
        if (ex == null || c == null || eos) return eos
        var n = 0
        while (n++ < 6) {
            stage = "$tag.dequeueInput"
            val i = c.dequeueInputBuffer(0)
            if (i < 0) return false
            stage = "$tag.getInputBuffer"
            val buf = c.getInputBuffer(i) ?: return false
            buf.clear()
            stage = "$tag.readSample"
            val size = ex.readSampleData(buf, 0)
            stage = "$tag.queueInput"
            if (size < 0) {
                c.queueInputBuffer(i, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                return true
            }
            c.queueInputBuffer(i, 0, size, ex.sampleTime, 0)
            stage = "$tag.advance"
            ex.advance()
        }
        return false
    }

    // ---- video ----

    private fun drainVideo() {
        val c = vCodec ?: return
        if (vOutDone) return
        if (!playing && !needFirstFrame) return
        var n = 0
        while (n++ < 4) {
            if (pendingV < 0) {
                stage = "video.dequeueOutput"
                val i = c.dequeueOutputBuffer(vInfo, 0)
                if (i == MediaCodec.INFO_TRY_AGAIN_LATER) return
                if (i < 0) continue // format / buffers changed
                pendingV = i
                lastVOutNs = System.nanoTime()
                pendingVPts = vInfo.presentationTimeUs
                pendingVFlags = vInfo.flags
            }
            stage = "video.releaseOutput"
            if (pendingVFlags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) {
                c.releaseOutputBuffer(pendingV, false)
                pendingV = -1
                vOutDone = true
                if (needFirstFrame) {
                    needFirstFrame = false
                    finishSeek()
                }
                return
            }
            // accurate seek: decode from the keyframe but never show frames before the target
            if (pendingVPts < skipBeforeUs) {
                c.releaseOutputBuffer(pendingV, false)
                pendingV = -1
                continue
            }
            val nowNs = System.nanoTime()
            if (needFirstFrame) {
                c.releaseOutputBuffer(pendingV, true)
                pendingV = -1
                lastRenderNs = nowNs
                pausedUs = pendingVPts
                anchorUs = pendingVPts
                anchorNs = nowNs
                needFirstFrame = false
                finishSeek()
                if (!playing) return
                continue
            }
            val delayUs = ((pendingVPts - clockUs()).toDouble() / speed).toLong()
            if (delayUs > 20_000L) return // not time yet, keep the frame for the next tick
            val dropIt = delayUs < -40_000L && nowNs - lastRenderNs < 250_000_000L
            if (dropIt) {
                c.releaseOutputBuffer(pendingV, false)
            } else {
                c.releaseOutputBuffer(pendingV, nowNs + max(delayUs, 0L) * 1000L)
                lastRenderNs = nowNs
            }
            pendingV = -1
        }
    }

    // ---- audio ----

    private fun setupTrack(fmt: MediaFormat) {
        val sr = fmt.getInteger(MediaFormat.KEY_SAMPLE_RATE)
        val ch = fmt.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
        val enc = if (fmt.containsKey(MediaFormat.KEY_PCM_ENCODING)) fmt.getInteger(MediaFormat.KEY_PCM_ENCODING)
        else AudioFormat.ENCODING_PCM_16BIT
        val mask = when (ch) {
            1 -> AudioFormat.CHANNEL_OUT_MONO
            2 -> AudioFormat.CHANNEL_OUT_STEREO
            4 -> AudioFormat.CHANNEL_OUT_QUAD
            6 -> AudioFormat.CHANNEL_OUT_5POINT1
            8 -> AudioFormat.CHANNEL_OUT_7POINT1_SURROUND
            else -> AudioFormat.CHANNEL_OUT_STEREO
        }
        val bps = when (enc) {
            AudioFormat.ENCODING_PCM_FLOAT -> 4
            AudioFormat.ENCODING_PCM_8BIT -> 1
            else -> 2
        }
        val minBuf = AudioTrack.getMinBufferSize(sr, mask, enc)
        val size = max(minBuf * 4, sr * ch * bps / 2) // at least half a second
        track?.let { t -> quiet { t.release() } }
        track = AudioTrack.Builder()
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_MOVIE)
                    .build()
            )
            .setAudioFormat(
                AudioFormat.Builder().setEncoding(enc).setSampleRate(sr).setChannelMask(mask).build()
            )
            .setBufferSizeInBytes(size)
            .setTransferMode(AudioTrack.MODE_STREAM)
            .setSessionId(audioSession)
            .build()
        applyVolume()
        sampleRate = sr
        bytesPerFrame = ch * bps
        audioBaseSet = false
        audioStarted = false
        writtenSinceFlush = 0
    }

    private fun startTrack() {
        val t = track ?: return
        t.play()
        audioStarted = true
        applyParams()
    }

    private fun applyParams() {
        val t = track ?: return
        if (!audioStarted) return // applied in startTrack(); setting params on a stopped track can restart it
        try {
            t.setPlaybackParams(
                PlaybackParams()
                    .setSpeed(speed)
                    .setPitch(pitch)
                    .setAudioFallbackMode(PlaybackParams.AUDIO_FALLBACK_MODE_DEFAULT)
            )
        } catch (e: Exception) {
            emit(mapOf("type" to "error", "message" to "Speed/pitch not supported here: ${e.message}"))
        }
    }

    private fun drainAudio() {
        val c = aCodec ?: return
        // (re)start the track once enough PCM is queued, also after pause/resume
        if (!audioStarted && track != null && playing &&
            (writtenSinceFlush >= sampleRate.toLong() * bytesPerFrame / 5 || aOutDone)
        ) startTrack()
        if (aOutDone) return
        var n = 0
        while (n++ < 8) {
            if (pendingA < 0) {
                val i = c.dequeueOutputBuffer(aInfo, 0)
                if (i == MediaCodec.INFO_TRY_AGAIN_LATER) return
                if (i == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                    setupTrack(c.outputFormat)
                    continue
                }
                if (i < 0) continue
                pendingA = i
                lastAOutNs = System.nanoTime()
                pendingAOff = aInfo.offset
                pendingARemain = aInfo.size
                pendingAPts = aInfo.presentationTimeUs
                pendingAFlags = aInfo.flags
            }
            val t = track
            if (pendingARemain > 0 && t != null) {
                val buf = c.getOutputBuffer(pendingA) ?: return
                buf.position(pendingAOff)
                buf.limit(pendingAOff + pendingARemain)
                if (!audioBaseSet) {
                    audioBaseUs = pendingAPts
                    headBase = t.playbackHeadPosition.toLong() and 0xFFFFFFFFL
                    audioBaseSet = true
                }
                val w = t.write(buf, pendingARemain, AudioTrack.WRITE_NON_BLOCKING)
                if (w < 0) throw IllegalStateException("AudioTrack write error $w")
                pendingAOff += w
                pendingARemain -= w
                writtenSinceFlush += w
                if (pendingARemain > 0) return // track buffer full, retry next tick
            }
            c.releaseOutputBuffer(pendingA, false)
            pendingA = -1
            if (pendingAFlags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) {
                aOutDone = true
                return
            }
        }
    }

    private fun checkEnded() {
        // Seeking into the last second right after a flush can make a hardware decoder swallow
        // its end-of-stream marker (seen on MediaTek). The stream is over when every sample was
        // fed, nothing is waiting to be shown/written and the decoder stayed silent for a while.
        val nowNs = System.nanoTime()
        val audioDrained = aInEos && pendingA < 0 && nowNs - lastAOutNs > 600_000_000L
        val videoDrained = vInEos && pendingV < 0 && nowNs - lastVOutNs > 600_000_000L
        val audioDone = aCodec == null || aOutDone || audioDrained
        val videoDone = when {
            vFormat == null -> true
            sw != 0L -> swEos && !swHave
            vCodec != null -> (vOutDone || videoDrained) && pendingV < 0
            else -> durationUs > 0 && clockUs() >= durationUs
        }
        if (audioDone && videoDone && pendingA < 0) {
            // let the tail of the audio buffer play out
            if (durationUs <= 0 || clockUs() >= durationUs - 150_000L) finish()
        }
    }

    // =====================================================================================
    // Events (audio focus is handled by the app's AudioFocusController)
    // =====================================================================================

    private fun emit(m: Map<String, Any?>) {
        main.post { sink(m) }
    }

    private fun emitState() {
        lastEmitNs = System.nanoTime()
        emit(
            mapOf(
                "type" to "state",
                "playing" to playing,
                "positionMs" to positionUs() / 1000,
                "durationMs" to durationUs / 1000,
            )
        )
    }
}
