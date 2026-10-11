package com.mounsokdara.video_player.accessibility.livecaption

import android.content.Context
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.net.Uri
import android.os.Handler
import android.os.Looper
import com.k2fsa.sherpa.onnx.FeatureConfig
import com.k2fsa.sherpa.onnx.OfflineModelConfig
import com.k2fsa.sherpa.onnx.OfflineRecognizer
import com.k2fsa.sherpa.onnx.OfflineRecognizerConfig
import com.k2fsa.sherpa.onnx.OfflineWhisperModelConfig
import com.k2fsa.sherpa.onnx.SileroVadModelConfig
import com.k2fsa.sherpa.onnx.Vad
import com.k2fsa.sherpa.onnx.VadModelConfig
import com.mounsokdara.video_player.DeveloperLog
import java.io.File
import java.io.FileInputStream
import java.nio.ByteOrder
import java.util.concurrent.atomic.AtomicInteger

/**
 * Live captions for the video being played. Works through the audio phrase by phrase, starting at
 * the playhead: each phrase is transcribed with Whisper as soon as the voice detector closes it,
 * saved to the cache file and pushed to Dart right away (no waiting for the whole audio). Parts
 * already in the cache are skipped. It stays at most [AHEAD_MS] ahead of what is being watched.
 */
object LiveCaptionEngine {
    private const val AHEAD_MS = 120_000L
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

    private fun send(path: String, m: Map<String, Any?>) {
        val p = HashMap(m)
        p["path"] = path
        CaptionHub.emit(p)
    }

    private fun emitStatus(ctx: Context, path: String, state: String, msg: String = "") {
        try { DeveloperLog.append(ctx, "LiveCaption: $state $msg") } catch (_: Throwable) {}
        send(path, mapOf("type" to "status", "state" to state, "message" to msg))
    }

    private fun emitProgress(path: String, cache: CaptionCache, durationMs: Long) {
        send(path, mapOf("type" to "progress", "coveredMs" to cache.coveredMs(durationMs), "durationMs" to durationMs))
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
                        encoder = File(dir, "encoder.int8.onnx").path,
                        decoder = File(dir, "decoder.int8.onnx").path,
                        language = lang,
                        task = "transcribe",
                        tailPaddings = 1000,
                    ),
                    tokens = File(dir, "tokens.txt").path,
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

    private fun newVad(ctx: Context) = Vad(
        config = VadModelConfig(
            sileroVadModelConfig = SileroVadModelConfig(
                model = ModelStore.file(ctx, "silero_vad.onnx").path,
                threshold = 0.5f,
                minSilenceDuration = 0.4f,
                minSpeechDuration = 0.25f,
                windowSize = 512,
                maxSpeechDuration = 15f,
            ),
            sampleRate = 16000,
            numThreads = 1,
            provider = "cpu",
        )
    )

    private fun run(ctx: Context, path: String, startMs: Long, g: Int) {
        fun alive() = gen.get() == g
        var extractor: MediaExtractor? = null
        try {
            if (!ModelStore.isReady(ctx, ModelStore.RUNTIME)) {
                emitStatus(ctx, path, "needs_model", "Download the speech engine and an AI model first")
                return
            }
            val chosen = LiveCaptionPrefs.model(ctx)
            val modelId = if (ModelStore.isReady(ctx, chosen)) chosen else ModelStore.installedModels(ctx).firstOrNull()?.id
            if (modelId == null) {
                emitStatus(ctx, path, "needs_model", "Download an AI model first")
                return
            }
            val lang = LiveCaptionPrefs.lang(ctx)

            // The cache is read first: cached captions show at once, before any model is loaded.
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
                emitStatus(ctx, path, "error", "This video has no audio track")
                return
            }
            ex.selectTrack(track)
            val durationMs = if (fmt.containsKey(MediaFormat.KEY_DURATION)) fmt.getLong(MediaFormat.KEY_DURATION) / 1000L else 0L

            val cache = CaptionCache.open(ctx, path, modelId, lang)
            send(
                path,
                mapOf(
                    "type" to "cues",
                    "list" to cache.cues.map { mapOf("s" to it.start, "e" to it.end, "t" to it.text) },
                )
            )
            emitProgress(path, cache, durationMs)
            if (cache.nextGap(startMs, durationMs) == null) {
                emitStatus(ctx, path, "done")
                return
            }

            emitStatus(ctx, path, "loading", "Loading speech engine...")
            ModelStore.loadNative(ctx)
            if (!alive()) return
            emitStatus(ctx, path, "loading", "Loading AI model ($modelId)...")
            recognizerFor(ctx, modelId, lang)
            if (!alive()) return
            emitStatus(ctx, path, "running")

            var cursor = startMs
            while (alive()) {
                val gap = cache.nextGap(cursor, durationMs) ?: break
                decodePass(ctx, path, ex, fmt, gap[0], gap[1], durationMs, cache, g)
                cursor = gap[1]
            }
            if (alive()) {
                emitProgress(path, cache, durationMs)
                emitStatus(ctx, path, "done")
            }
        } catch (e: Throwable) {
            val msg = "${e.javaClass.simpleName}: ${e.message ?: ""}"
            try { DeveloperLog.append(ctx, "LiveCaption: failed $msg") } catch (_: Throwable) {}
            if (alive()) emitStatus(ctx, path, "error", msg)
        } finally {
            try { extractor?.release() } catch (_: Throwable) {}
        }
    }

    /**
     * Transcribes the audio between [from] and [until] (ms), phrase by phrase. Every finished phrase
     * is cached and sent immediately; the processed time range is saved as the pass moves on.
     */
    private fun decodePass(
        ctx: Context, path: String, ex: MediaExtractor, fmt: MediaFormat,
        from: Long, until: Long, durationMs: Long, cache: CaptionCache, g: Int,
    ) {
        fun alive() = gen.get() == g
        val cd = MediaCodec.createDecoderByType(fmt.getString(MediaFormat.KEY_MIME)!!)
        val v = newVad(ctx)
        try {
            cd.configure(fmt, null, null, 0)
            cd.start()
            ex.seekTo(from * 1000L, MediaExtractor.SEEK_TO_PREVIOUS_SYNC)
            var rate = fmt.getInteger(MediaFormat.KEY_SAMPLE_RATE)
            var channels = fmt.getInteger(MediaFormat.KEY_CHANNEL_COUNT)

            var baseSec = -1.0
            var fed = 0L
            var frontier = from
            var saved = from
            var waiting = false

            fun fedMs(): Long = ((if (baseSec < 0) from / 1000.0 else baseSec) * 1000.0 + fed / 16.0).toLong()

            fun saveFrontier(force: Boolean) {
                if (frontier - saved >= 2000 || (force && frontier > saved)) {
                    cache.addRange(saved, frontier)
                    saved = frontier
                    emitProgress(path, cache, durationMs)
                }
            }

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
                        val t0 = (if (baseSec < 0) from / 1000.0 else baseSec) + seg.start / 16000.0
                        publish(path, cache, from, t0, seg.samples.size / 16000.0, text)
                    }
                }
                // All audio fed so far is final once no speech is in progress.
                if (alive() && !v.isSpeechDetected()) {
                    frontier = maxOf(frontier, minOf(fedMs(), until))
                    saveFrontier(false)
                }
            }

            val info = MediaCodec.BufferInfo()
            val win = FloatArray(512)
            var wn = 0
            var inputDone = false
            var outputDone = false
            var reachedEnd = false
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
                                fed += 512
                                wn = 0
                                drain()
                            }
                            pos += step
                        }
                        pos -= frames
                        if (pos < 0) pos = 0.0

                        val decodedMs = info.presentationTimeUs / 1000L
                        // Stay near the playhead instead of racing through the whole file.
                        while (alive() && decodedMs > playheadMs + AHEAD_MS) {
                            if (!waiting) {
                                waiting = true
                                send(path, mapOf("type" to "status", "state" to "waiting", "message" to ""))
                            }
                            Thread.sleep(400)
                        }
                        if (waiting && alive()) {
                            waiting = false
                            send(path, mapOf("type" to "status", "state" to "running", "message" to ""))
                        }
                        if (decodedMs >= until && until < Long.MAX_VALUE / 8) outputDone = true
                    }
                    cd.releaseOutputBuffer(oi, false)
                    if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) {
                        outputDone = true
                        reachedEnd = true
                    }
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
                frontier = maxOf(frontier, if (reachedEnd) maxOf(durationMs, fedMs()) else minOf(until, fedMs()))
                saveFrontier(true)
            }
        } finally {
            try { v.release() } catch (_: Throwable) {}
            try { cd.stop() } catch (_: Throwable) {}
            try { cd.release() } catch (_: Throwable) {}
        }
    }

    /** Splits a phrase into short, readable caption lines spread over its time span, then caches and sends them. */
    private fun publish(path: String, cache: CaptionCache, from: Long, t0: Double, dur: Double, text: String) {
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
            val s = (t * 1000).toLong()
            val e = ((t + d) * 1000).toLong()
            t += d
            if (e < from) continue // belongs to a part that is already cached
            cache.addCue(s, e, p)
            send(path, mapOf("type" to "cue", "startMs" to s, "endMs" to e, "text" to p))
        }
    }
}
