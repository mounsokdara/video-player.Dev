package com.mounsokdara.video_player

object NativeConstants {
    const val CHANNEL = "app.videoplayer/android"
    const val EVENTS = "app.videoplayer/events"
    const val EQ_RETRY_MS = 450L
    const val HIDE_RETRY_MS = 120L
    const val EQ_BANDS = 10
    const val BASS_MAX = 1000
    const val SCAN_BUDGET = 2500
    const val HIDDEN_SCAN_BUDGET = 4000
    const val INDEXED_CAP = 5000
    const val FILE_CRASH = "last_crash.txt"
    const val FILE_DIRTY = "session_dirty.txt"
    const val FILE_ACTION = "last_action.txt"
    const val FILE_EQ_DIRTY = "eq_dirty.txt"
    const val FILE_DEBUG = "debug_log.txt"

    val TEN_BAND_HZ = intArrayOf(31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000)

    val VIDEO_EXT = setOf(
        "mp4", "mkv", "webm", "avi", "mov", "m4v", "3gp", "3gpp", "3g2", "3gp2",
        "flv", "wmv", "asf", "mpeg", "mpg", "mpe", "m1v", "m2v", "mpv", "mp2v",
        "m2ts", "mts", "m2t", "ts", "tts", "vob", "f4v", "ogv", "ogm", "ogx",
        "rm", "rmvb", "divx", "xvid", "tod", "vro", "nsv", "nuv", "rec", "wtv",
        "amv", "dv", "mxf", "gxf", "h264", "h265", "hevc", "264", "265", "qt",
        "mp4v", "mpeg1", "mpeg2", "mpeg4"
    )
    val SKIP_EXT = setOf(
        "tsx", "js", "jsx", "mjs", "cjs", "json", "txt", "md", "css",
        "html", "htm", "xml", "svg", "map", "yml", "yaml", "py", "java",
        "kt", "dart", "c", "h", "cpp", "go", "rs", "sh", "log", "csv",
        "toml", "ini", "cfg",
        "jpg", "jpeg", "png", "gif", "webp", "bmp", "heic", "heif", "ico", "tif", "tiff",
        "mp3", "wav", "flac", "ogg", "m4a", "aac", "wma", "opus", "oga", "aiff",
        "pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "apk", "zip", "rar", "7z"
    )

    object Orient {
        const val LANDSCAPE = "landscape"
        const val PORTRAIT = "portrait"
        const val LANDSCAPE_NORMAL = "landscape_normal"
        const val LANDSCAPE_REVERSE = "landscape_reverse"
        const val PORTRAIT_NORMAL = "portrait_normal"
        const val PORTRAIT_REVERSE = "portrait_reverse"
        const val LOCKED = "locked"
        const val USER = "user"
        const val SENSOR = "sensor"
        const val AUTO = "auto"
        const val NONE = "none"
        const val UNSPECIFIED = "unspecified"
    }

    object Method {
        const val APPLY_SYSTEM_BARS = "applySystemBars"
        const val SET_ORIENTATION = "setOrientation"
        const val REQUEST_AUDIO_FOCUS = "requestAudioFocus"
        const val ABANDON_AUDIO_FOCUS = "abandonAudioFocus"
        const val APPLY_EQUALIZER = "applyEqualizer"
        const val OPEN_CRASH_REPORT = "openCrashReport"
        const val OPEN_SETTINGS = "openSettings"
        const val DEBUG_LOG = "debugLog"
        const val CLEAR_LOGS = "clearLogs"
    }
}

/** Read by LicensesActivity only. The About page itself is Dart: keep VERSION in sync with lib/about/about_info.dart. */
object AboutInfo {
    const val NAME = "Video Player"
    const val AUTHOR = "Moun Sokdara"
    const val VERSION = "1.0.2.3"
}
