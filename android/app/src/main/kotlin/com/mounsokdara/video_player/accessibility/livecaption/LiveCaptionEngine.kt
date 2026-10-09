package com.mounsokdara.video_player.accessibility.livecaption

import android.content.Context
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.net.Uri
import android.os.Handler
import android.os.Looper
import com.mounsokdara.video_player.DeveloperLog
import com.k2fsa.sherpa.onnx.FeatureConfig
import com.k2fsa.sherpa.onnx.OfflineModelConfig
import com.k2fsa.sherpa.onnx.OfflineRecognizer
import com.k2fsa.sherpa.onnx.OfflineRecognizerConfig
import com.k2fsa.sherpa.onnx.OfflineWhisperModelConfig
import com.k2fsa.sherpa.onnx.SileroVadModelConfig
import com.k2fsa.sherpa.onnx.Vad
import com.k2fsa.sherpa.onnx.VadModelConfig
import java.io.FileInputStream
import java.nio.ByteOrder
import java.util.concurrent.atomic.AtomicInteger

/**
 * Live captions for the video being played. Decodes the file's audio from the current position,
 * finds speech with a voice detector, transcribes each phrase with Whisper and pushes caption cues
 * to Dart through [CaptionHub]. It stays at most [AHEAD_MS] ahead of the playhead.
 */
object LiveCaptionEngine {
    private const val AHEAD_MS = 90_000L
    private val gen = AtomicInteger()
    @Volatile private var playheadMs = 0L
    // createLock guards building/replacing the recognizer; decodeLock guards using/releasing it.
    private val createLock = Any()
    private val decodeLock = Any()
    private val main = Handler(Looper.getMainLooper())
    @Volatile private var rec: OfflineRecognizer? = null
    @Volatile private var recKey = ""

    fun start(ctx: Context, path: String, startMs: Long) {
        val g = gen.incrementAndGet()
        playheadMs = startMs
        val app = ctx.applicationContext
        Thread { run(app, path, startMs, g) }.start()
    }

    fun playhead(ms: Long) {
        playheadMs = ms
    }

    fun stop(release: Boolean) {
        val g = gen.incrementAndGet()
        if (release) {
            // Keep the model for a while: re-entering the player or seeking must not reload it.
            main.postDelayed({
                if (gen.get() == g) {
                    Thread {
                        synchronized(createLock) {
                            synchronized(decodeLock) {
                                try { rec?.release() } catch (_: Throwable) {}
                                rec = null
                                recKey = ""
                            }
                        }
                    }.start()
                }
            }, 20_000)
        }
    }

    fun status(ctx: Context): Map<String, Any?> {
        val runtime = ModelStore.isReady(ctx, ModelStore.RUNTIME)
        val chosen = LiveCaptionPrefs.model(ctx)
        val usable = if (ModelStore.isReady(ctx, chosen)) chosen else ModelStore.installedModels(ctx).firstOrNull()?.id
        return mapOf("ready" to (runtime && usable != null), "runtime" to runtime, "model" to (usable ?: ""))
    }

    private fun emitStatus(ctx: Context, state: String, msg: String = "") {
        try { DeveloperLog.append(ctx, "LiveCaption: $state $msg") } catch (_: Throwable) {}
        CaptionHub.emit(mapOf("type" to "status", "state" to state, "message" to msg))
    }

    private fun recognizerFor(ctx: Context, modelId: String, lang: String): OfflineRecognizer {
        val key = "$modelId|$lang"
        val cur = rec
        if (cur != null && recKey == key) return cur
        synchronized(createLock) {
            val again = rec
            if (again != null && recKey == key) return again
            synchronized(decodeLock) {
                try { rec?.release() } catch (_: Throwable) {}
                rec = null
                recKey = ""
            }
            return buildRecognizer(ctx, modelId, lang, key)
        }
    }

    private fun buildRecognizer(ctx: Context, modelId: String, lang: String, key: String): OfflineRecognizer {
        val dir = ModelStore.modelDir(ctx, modelId)
        val r = OfflineRecognizer(
            config = OfflineRecognizerConfig(
                featConfig = FeatureConfig(sampleRate = 16000, featureDim = 80),
                modelConfig = OfflineModelConfig(
                    whisper = OfflineWhisperModelConfig(
                        encoder = java.io.File(dir, "encoder.int8.onnx").path,
                        decoder = java.io.File(dir, "decoder.int8.onnx").path,
                        language = lang,
                        task = "transcribe",
                        tailPaddings = 1000,
                    ),
                    tokens = java.io.File(dir, "tokens.txt").path,
                    numThreads = 4,
                    provider = "cpu",
                    modelType = "whisper",
                ),
            )
        )
        rec = r
        recKey = key
        return r
    }

    private fun run(ctx: Context, path: String, startMs: Long, g: Int) {
        fun alive() = gen.get() == g
        var extractor: MediaExtractor? = null
        var codec: MediaCodec? = null
        var vad: Vad? = null
        try {
            if (!ModelStore.isReady(ctx, ModelStore.RUNTIME)) {
                emitStatus(ctx, "needs_model", "Download the speech engine and an AI model first")
                return
            }
            val chosen = LiveCaptionPrefs.model(ctx)
            val modelId = if (ModelStore.isReady(ctx, chosen)) chosen else ModelStore.installedModels(ctx).firstOrNull()?.id
            if (modelId == null) {
                emitStatus(ctx, "needs_model", "Download an AI model first")
                return
            }
            emitStatus(ctx, "loading", "Loading speech engine...")
            ModelStore.loadNative(ctx)
            if (!alive()) return
            val lang = LiveCaptionPrefs.lang(ctx)
            emitStatus(ctx, "loading", "Loading AI model ($modelId)...")
            recognizerFor(ctx, modelId, lang)
            if (!alive()) return
            emitStatus(ctx, "loading", "Opening audio...")
            val v = Vad(
                config = VadModelConfig(
                    sileroVadModelConfig = SileroVadModelConfig(
                        model = ModelStore.file(ctx, "silero_vad.onnx").path,
                        threshold = 0.5f,
                        minSilenceDuration = 0.5f,
                        minSpeechDuration = 0.25f,
                        windowSize = 512,
                        maxSpeechDuration = 25f,
                    ),
                    sampleRate = 16000,
                    numThreads = 1,
                    provider = "cpu",
                )
            )
            vad = v

            val ex = MediaExtractor()
            extractor = ex
            if (path.startsWith("content:")) {
                ex.setDataSource(ctx, Uri.parse(path), null)
            } else {
                val p = if (path.startsWith("file:")) Uri.parse(path).path ?: path else path
                FileInputStream(p).use { ex.setDataSource(it.fd) }
            }
            var track = -1
            var fmt: MediaFormat? = null
            for (i in 0 until ex.trackCount) {
                val f = ex.getTrackFormat(i)
                if (f.getString(MediaFormat.KEY_MIME)?.startsWith("audio/") == true) { track = i; fmt = f; break }
            }
            if (track < 0 || fmt == null) {
                emitStatus(ctx, "error", "This video has no audio track")
                return
            }
            ex.selectTrack(track)
            ex.seekTo(startMs * 1000L, MediaExtractor.SEEK_TO_PREVIOUS_SYNC)
            var rate = fmt.getInteger(MediaFormat.KEY_SAMPLE_RATE)
            var channels = fmt.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
            val cd = MediaCodec.createDecoderByType(fmt.getString(MediaFormat.KEY_MIME)!!)
            codec = cd
            cd.configure(fmt, null, null, 0)
            cd.start()
            emitStatus(ctx, "running")

            var baseSec = -1.0

            fun drain() {
                while (!v.empty()) {
                    val seg = v.front()
                    v.pop()
                    if (!alive()) continue
                    val text = synchronized(decodeLock) {
                        val r = rec ?: return@synchronized ""
                        val s = r.createStream()
                        s.acceptWaveform(seg.samples, 16000)
                        r.decode(s)
                        val t = r.getResult(s).text.trim()
                        s.release()
                        t
                    }
                    if (text.isNotEmpty() && alive()) {
                        val t0 = (if (baseSec < 0) 0.0 else baseSec) + seg.start / 16000.0
                        emitCues(t0, seg.samples.size / 16000.0, text)
                    }
                }
            }

            val info = MediaCodec.BufferInfo()
            val win = FloatArray(512)
            var wn = 0
            var inputDone = false
            var outputDone = false
            var pos = 0.0

            while (!outputDone && alive()) {
                if (!inputDone) {
                    val ii = cd.dequeueInputBuffer(10_000)
                    if (ii >= 0) {
                        val buf = cd.getInputBuffer(ii)!!
                        val n = ex.readSampleData(buf, 0)
                        if (n < 0) {
                            cd.queueInputBuffer(ii, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                            inputDone = true
                        } else {
                            cd.queueInputBuffer(ii, 0, n, ex.sampleTime, 0)
                            ex.advance()
                        }
                    }
                }
                val oi = cd.dequeueOutputBuffer(info, 10_000)
                if (oi >= 0) {
                    if (info.size > 0) {
                        if (baseSec < 0) baseSec = info.presentationTimeUs / 1_000_000.0
                        val buf = cd.getOutputBuffer(oi)!!
                        buf.position(info.offset)
                        buf.limit(info.offset + info.size)
                        val sb = buf.order(ByteOrder.nativeOrder()).asShortBuffer()
                        val total = sb.remaining()
                        val shorts = ShortArray(total)
                        sb.get(shorts)
                        val frames = total / channels
                        val step = rate / 16000.0
                        while (pos + step <= frames) {
                            val s = pos.toInt()
                            val e = maxOf((pos + step).toInt(), s + 1)
                            var acc = 0L
                            var cnt = 0
                            for (f in s until minOf(e, frames)) {
                                for (c in 0 until channels) { acc += shorts[f * channels + c]; cnt++ }
                            }
                            win[wn++] = if (cnt > 0) acc.toFloat() / cnt / 32768f else 0f
                            if (wn == 512) {
                                v.acceptWaveform(win.copyOf())
                                wn = 0
                                drain()
                            }
                            pos += step
                        }
                        pos -= frames
                        if (pos < 0) pos = 0.0
                        // Do not run far ahead of what is being watched.
                        val decodedMs = info.presentationTimeUs / 1000L
                        while (alive() && decodedMs > playheadMs + AHEAD_MS) Thread.sleep(400)
                    }
                    cd.releaseOutputBuffer(oi, false)
                    if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) outputDone = true
                } else if (oi == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                    val nf = cd.outputFormat
                    rate = nf.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                    channels = nf.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                    pos = 0.0
                }
            }
            if (alive()) {
                v.flush()
                drain()
                emitStatus(ctx, "done")
            }
        } catch (e: Throwable) {
            // Always report: a superseded run still tells why it failed (the log keeps the full story).
            val msg = "${e.javaClass.simpleName}: ${e.message ?: ""}"
            try { DeveloperLog.append(ctx, "LiveCaption: failed $msg") } catch (_: Throwable) {}
            if (alive()) emitStatus(ctx, "error", msg)
        } finally {
            try { vad?.release() } catch (_: Throwable) {}
            try { codec?.stop() } catch (_: Throwable) {}
            try { codec?.release() } catch (_: Throwable) {}
            try { extractor?.release() } catch (_: Throwable) {}
        }
    }

    /** Splits a phrase into short, readable caption lines spread over the phrase's time span. */
    private fun emitCues(t0: Double, dur: Double, text: String) {
        val parts = ArrayList<String>()
        if (text.contains(' ')) {
            var cur = StringBuilder()
            var n = 0
            for (w in text.split(Regex("\\s+"))) {
                if (cur.isNotEmpty() && (n >= 9 || cur.length + w.length > 42)) {
                    parts.add(cur.toString()); cur = StringBuilder(); n = 0
                }
                if (cur.isNotEmpty()) cur.append(' ')
                cur.append(w); n++
            }
            if (cur.isNotEmpty()) parts.add(cur.toString())
        } else {
            text.chunked(24).forEach { parts.add(it) }
        }
        val total = parts.sumOf { it.length }.toDouble().coerceAtLeast(1.0)
        var t = t0
        for (p in parts) {
            val d = dur * p.length / total
            CaptionHub.emit(
                mapOf(
                    "type" to "cue",
                    "startMs" to (t * 1000).toLong(),
                    "endMs" to ((t + d) * 1000).toLong(),
                    "text" to p,
                )
            )
            t += d
        }
    }
}
