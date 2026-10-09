package com.mounsokdara.video_player.accessibility.livecaption

import android.content.Context
import android.net.Uri
import org.json.JSONObject
import java.io.File
import java.security.MessageDigest

/**
 * Per-video caption cache in `cacheDir/livecaption/<key>.jsonl`. Every extracted phrase is appended
 * the moment it is ready, together with the time ranges already processed, so nothing is lost if
 * the app is closed and a replay only extracts what is still missing. The key covers the file,
 * its size and date, the AI model and the language.
 */
class CaptionCache private constructor(private val file: File) {
    class Cue(val start: Long, val end: Long, val text: String)

    val cues = ArrayList<Cue>()
    private val ranges = ArrayList<LongArray>()

    fun coveredMs(durationMs: Long): Long {
        var sum = 0L
        for (r in ranges) sum += if (durationMs > 0) (minOf(r[1], durationMs) - r[0]).coerceAtLeast(0) else r[1] - r[0]
        return sum
    }

    @Synchronized
    fun addCue(start: Long, end: Long, text: String) {
        cues.add(Cue(start, end, text))
        append(JSONObject().put("s", start).put("e", end).put("t", text).toString())
    }

    @Synchronized
    fun addRange(a: Long, b: Long) {
        if (b <= a) return
        ranges.add(longArrayOf(a, b))
        merge()
        append(JSONObject().put("d", org.json.JSONArray().put(a).put(b)).toString())
    }

    /**
     * First not-yet-extracted part at or after [from]; when nothing is left after it, the first gap
     * before it. Null when the whole video is covered (gaps under 2.5 s are ignored).
     */
    @Synchronized
    fun nextGap(from: Long, durationMs: Long): LongArray? {
        val total = if (durationMs > 0) durationMs else Long.MAX_VALUE / 4
        val gaps = ArrayList<LongArray>()
        var prev = 0L
        for (r in ranges) {
            if (r[0] - prev > 2500) gaps.add(longArrayOf(prev, r[0]))
            prev = maxOf(prev, r[1])
        }
        if (total - prev > 2500) gaps.add(longArrayOf(prev, total))
        for (g in gaps) if (g[1] > from) return longArrayOf(maxOf(g[0], from), g[1])
        return gaps.firstOrNull()
    }

    private fun merge() {
        ranges.sortBy { it[0] }
        val out = ArrayList<LongArray>()
        for (r in ranges) {
            val last = out.lastOrNull()
            if (last != null && r[0] <= last[1] + 300) last[1] = maxOf(last[1], r[1]) else out.add(longArrayOf(r[0], r[1]))
        }
        ranges.clear()
        ranges.addAll(out)
    }

    private fun append(line: String) {
        try {
            file.parentFile?.mkdirs()
            file.appendText(line + "\n")
        } catch (_: Throwable) {
        }
    }

    private fun load(header: String) {
        if (!file.exists()) {
            append(header)
            return
        }
        try {
            file.forEachLine { line ->
                try {
                    val o = JSONObject(line)
                    when {
                        o.has("s") -> cues.add(Cue(o.getLong("s"), o.getLong("e"), o.getString("t")))
                        o.has("d") -> ranges.add(longArrayOf(o.getJSONArray("d").getLong(0), o.getJSONArray("d").getLong(1)))
                    }
                } catch (_: Throwable) {
                    // A half-written last line is ignored.
                }
            }
        } catch (_: Throwable) {
        }
        merge()
    }

    companion object {
        private fun dir(c: Context) = File(c.cacheDir, "livecaption")

        fun open(c: Context, path: String, model: String, lang: String): CaptionCache {
            val p = if (path.startsWith("file:")) Uri.parse(path).path ?: path else path
            val f = if (path.startsWith("content:")) null else File(p)
            val size = f?.length() ?: 0L
            val mtime = f?.lastModified() ?: 0L
            val key = MessageDigest.getInstance("SHA-1")
                .digest("$path|$size|$mtime|$model|$lang".toByteArray())
                .joinToString("") { "%02x".format(it) }
            val cache = CaptionCache(File(dir(c), "$key.jsonl"))
            cache.load(JSONObject().put("v", 1).put("path", path).put("model", model).put("lang", lang).toString())
            return cache
        }

        /** (number of cached videos, bytes used). */
        fun stats(c: Context): Pair<Int, Long> {
            val files = dir(c).listFiles()?.filter { it.isFile } ?: return 0 to 0L
            return files.size to files.sumOf { it.length() }
        }

        fun clear(c: Context) {
            dir(c).listFiles()?.forEach { it.delete() }
        }
    }
}
