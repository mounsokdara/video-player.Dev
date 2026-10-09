package com.mounsokdara.video_player.accessibility.livecaption

import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Downloadable pieces of Live Caption: the speech engine (native libraries + voice detector) and
 * the Whisper models. Nothing is bundled in the APK; files live in `filesDir/livecaption`.
 */
object ModelStore {
    private const val REL = "https://github.com/mounsokdara/offline-video-captions/releases/download/"
    const val RUNTIME = "runtime"

    class FileSpec(val rel: String, val url: String, val approx: Long)
    class Item(val id: String, val title: String, val note: String, val files: List<FileSpec>) {
        val totalApprox: Long get() = files.sumOf { it.approx }
    }

    class State(val downloading: Boolean, val progress: Int, val error: String?)

    private class Cancelled : IOException("cancelled")

    private val states = ConcurrentHashMap<String, State>()
    private val cancels = ConcurrentHashMap<String, AtomicBoolean>()
    private val listeners = CopyOnWriteArrayList<Runnable>()
    private val main = Handler(Looper.getMainLooper())
    @Volatile private var lastNotify = 0L
    private var nativeLoaded = false

    fun abi(): String =
        Build.SUPPORTED_ABIS.firstOrNull { it == "arm64-v8a" || it == "armeabi-v7a" || it == "x86_64" } ?: ""

    fun items(): List<Item> = listOf(
        runtime(),
        model("base", "Whisper Base", "Faster, good accuracy", 29_100_000L, 130_700_000L),
        model("small", "Whisper Small", "Slower, most accurate", 112_400_000L, 262_200_000L),
    )

    fun item(id: String): Item = items().first { it.id == id }

    private fun runtime(): Item {
        val abi = abi()
        val (ort, jni) = when (abi) {
            "arm64-v8a" -> 22_250_000L to 4_770_000L
            "armeabi-v7a" -> 15_360_000L to 3_430_000L
            else -> 25_580_000L to 5_200_000L
        }
        val files = if (abi.isEmpty()) emptyList() else listOf(
            FileSpec("runtime-$abi/libonnxruntime.so", REL + "runtime/$abi-libonnxruntime.so", ort),
            FileSpec("runtime-$abi/libsherpa-onnx-jni.so", REL + "runtime/$abi-libsherpa-onnx-jni.so", jni),
            FileSpec("silero_vad.onnx", REL + "runtime/silero_vad.onnx", 640_000L),
        )
        return Item(RUNTIME, "Speech engine (required)", "Runs the AI on your phone", files)
    }

    private fun model(id: String, title: String, note: String, enc: Long, dec: Long) = Item(
        id, title, note,
        listOf(
            FileSpec("models/$id/encoder.int8.onnx", REL + "models/whisper-$id-encoder.int8.onnx", enc),
            FileSpec("models/$id/decoder.int8.onnx", REL + "models/whisper-$id-decoder.int8.onnx", dec),
            FileSpec("models/$id/tokens.txt", REL + "models/whisper-$id-tokens.txt", 800_000L),
        )
    )

    fun root(c: Context) = File(c.filesDir, "livecaption")
    fun file(c: Context, rel: String) = File(root(c), rel)

    fun isReady(c: Context, id: String): Boolean {
        val it = item(id)
        return it.files.isNotEmpty() && it.files.all { f -> file(c, f.rel).exists() }
    }

    fun installedModels(c: Context): List<Item> = items().filter { it.id != RUNTIME && isReady(c, it.id) }

    fun modelDir(c: Context, id: String) = file(c, "models/$id")

    fun state(id: String): State = states[id] ?: State(false, 0, null)

    fun addListener(r: Runnable) { listeners.addIfAbsent(r) }
    fun removeListener(r: Runnable) { listeners.remove(r) }

    private fun publish(id: String, st: State) {
        states[id] = st
        val now = System.currentTimeMillis()
        if (!st.downloading || now - lastNotify > 200) {
            lastNotify = now
            main.post { for (l in listeners) l.run() }
        }
    }

    @Synchronized
    fun loadNative(c: Context) {
        if (nativeLoaded) return
        val abi = abi()
        System.load(file(c, "runtime-$abi/libonnxruntime.so").absolutePath)
        System.load(file(c, "runtime-$abi/libsherpa-onnx-jni.so").absolutePath)
        nativeLoaded = true
    }

    fun download(ctx: Context, id: String) {
        val app = ctx.applicationContext
        if (states[id]?.downloading == true) return
        val cancel = AtomicBoolean(false)
        cancels[id] = cancel
        publish(id, State(true, 0, null))
        Thread {
            try {
                val chain = if (id != RUNTIME && !isReady(app, RUNTIME)) listOf(RUNTIME, id) else listOf(id)
                val total = chain.sumOf { item(it).totalApprox }.coerceAtLeast(1L)
                var base = 0L
                for (cid in chain) {
                    for (f in item(cid).files) {
                        fetch(app, f, cancel) { got ->
                            val p = ((base + got) * 1000L / total).toInt().coerceIn(0, 999)
                            publish(id, State(true, p, null))
                        }
                        base += f.approx
                    }
                }
                publish(id, State(false, 1000, null))
            } catch (_: Cancelled) {
                publish(id, State(false, 0, null))
            } catch (e: Throwable) {
                publish(id, State(false, 0, e.message ?: "Download failed"))
            }
        }.start()
    }

    fun cancel(id: String) {
        cancels[id]?.set(true)
    }

    fun delete(ctx: Context, id: String) {
        val app = ctx.applicationContext
        cancel(id)
        for (f in item(id).files) {
            file(app, f.rel).delete()
            File(file(app, f.rel).path + ".part").delete()
        }
        publish(id, State(false, 0, null))
    }

    private fun fetch(c: Context, f: FileSpec, cancel: AtomicBoolean, onBytes: (Long) -> Unit) {
        val dest = file(c, f.rel)
        if (dest.exists()) return
        dest.parentFile?.mkdirs()
        val part = File(dest.path + ".part")
        var existing = if (part.exists()) part.length() else 0L
        val conn = URL(f.url).openConnection() as HttpURLConnection
        conn.connectTimeout = 20_000
        conn.readTimeout = 30_000
        if (existing > 0) conn.setRequestProperty("Range", "bytes=$existing-")
        conn.connect()
        val code = conn.responseCode
        if (code == 416) {
            part.renameTo(dest)
            return
        }
        if (code != 200 && code != 206) throw IOException("Download failed (HTTP $code). Check your internet connection.")
        val append = code == 206
        if (!append) existing = 0
        val remaining = conn.contentLengthLong
        val total = if (remaining > 0) existing + remaining else -1L
        var done = existing
        FileOutputStream(part, append).use { out ->
            conn.inputStream.use { inp ->
                val buf = ByteArray(64 * 1024)
                while (true) {
                    if (cancel.get()) throw Cancelled()
                    val n = inp.read(buf)
                    if (n < 0) break
                    out.write(buf, 0, n)
                    done += n
                    onBytes(done)
                }
            }
        }
        if (total > 0 && part.length() != total) throw IOException("Download interrupted. Tap to resume.")
        if (!part.renameTo(dest)) throw IOException("Could not save file")
        if (dest.name.endsWith(".so")) dest.setReadOnly()
    }
}
