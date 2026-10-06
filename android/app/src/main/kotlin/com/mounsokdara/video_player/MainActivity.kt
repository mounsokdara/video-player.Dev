package com.mounsokdara.video_player

import android.app.Activity
import android.app.PictureInPictureParams
import android.content.ClipData
import android.content.ClipDescription
import android.content.ContentUris
import android.content.ContentValues
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Color
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMetadataRetriever
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.os.storage.StorageManager
import android.provider.MediaStore
import android.provider.OpenableColumns
import android.provider.Settings
import android.util.Log
import android.util.Rational
import android.view.PixelCopy
import android.view.SurfaceView
import android.view.TextureView
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.webkit.MimeTypeMap
import android.widget.Toast
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.concurrent.CopyOnWriteArrayList

open class MainActivity : FlutterActivity() {
    private val channelName = NativeConstants.CHANNEL
    private val eventName = NativeConstants.EVENTS
    private var wantPip = false
    private var isPlaying = false
    private var keepScreenOn = false
    private var pendingOpen: String? = null
    private var eventSink: EventChannel.EventSink? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private val io = java.util.concurrent.Executors.newSingleThreadExecutor()
    private var previewRetriever: MediaMetadataRetriever? = null
    private var previewBoundPath: String? = null
    private lateinit var systemBars: SystemBarController
    private lateinit var audioFocus: AudioFocusController
    private lateinit var equalizer: EqualizerController
    private lateinit var appNative: AppNative
    private var libraryWatcher: LibraryWatcher? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        systemBars = SystemBarController(this)
        equalizer = EqualizerController(
            this,
            { flutterEngine },
            mainHandler,
            { NativeCrashLog.breadcrumb(this, it) },
            { NativeCrashLog.write(this, it) }
        )
        audioFocus = AudioFocusController(
            this,
            mainHandler,
            { action -> emit(mapOf("type" to "media", "action" to action)) },
            { NativeCrashLog.breadcrumb(this, it) },
            isPlaying
        ) { isPlaying = it }
        appNative = AppNative(this, systemBars, audioFocus, equalizer)
        super.onCreate(savedInstanceState)
        systemBars.enableEdgeToEdge()
        NativeCrashLog.installHook(this) { emit(it) }
        handleIncoming(intent)
    }

    override fun onDestroy() {
        try {
            File(filesDir, NativeConstants.FILE_DIRTY).delete()
            File(filesDir, NativeConstants.FILE_ACTION).writeText("idle")
        } catch (_: Exception) {
        }
        equalizer.release()
        libraryWatcher?.stop()
        libraryWatcher = null
        bindPreview(null)
        audioFocus.release()
        super.onDestroy()
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) systemBars.reapply()
    }

    override fun onResume() {
        super.onResume()
        if (::systemBars.isInitialized) systemBars.reapply()
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        if (::systemBars.isInitialized) systemBars.reapply()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIncoming(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, eventName)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                    if (events != null) addMediaSink(events)
                    val pending = pendingOpen
                    pendingOpen = null
                    if (pending != null) emit(mapOf("type" to "open", "path" to pending))
                    startLibraryWatcher()
                }

                override fun onCancel(arguments: Any?) {
                    eventSink?.let { removeMediaSink(it) }
                    eventSink = null
                }
            })
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                try {
                    if (appNative.handleLocal(call.method, call, result)) return@setMethodCallHandler
                    when (call.method) {
                        "sdkInt" -> result.success(Build.VERSION.SDK_INT)
                        "openPage" -> {
                            val cls = when (call.argument<String>("page")) {
                                "about" -> AboutActivity::class.java
                                "licenses" -> LicensesActivity::class.java
                                "console" -> ConsoleActivity::class.java
                                else -> null
                            }
                            if (cls == null) {
                                result.error("ARG", "page", null)
                            } else {
                                startActivity(Intent(this, cls))
                                result.success(true)
                            }
                        }
                        "hasAllFilesAccess" -> {
                            result.success(
                                if (Build.VERSION.SDK_INT >= 30)
                                    Environment.isExternalStorageManager()
                                else true
                            )
                        }
                        "requestAllFilesAccess" -> {
                            if (Build.VERSION.SDK_INT >= 30) {
                                val intent = Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION)
                                intent.data = Uri.parse("package:$packageName")
                                startActivity(intent)
                            }
                            result.success(true)
                        }
                        "canManageMedia" -> {
                            result.success(
                                if (Build.VERSION.SDK_INT >= 31) MediaStore.canManageMedia(this) else true
                            )
                        }
                        "requestManageMedia" -> {
                            if (Build.VERSION.SDK_INT >= 31 && !MediaStore.canManageMedia(this)) {
                                startActivity(
                                    Intent(Settings.ACTION_REQUEST_MANAGE_MEDIA).apply {
                                        data = Uri.parse("package:$packageName")
                                    }
                                )
                            }
                            result.success(true)
                        }
                        "listStorageVolumes" -> {
                            val volumes = listVolumes()
                            startLibraryWatcher(volumes)
                            result.success(volumes)
                        }
                        "listVideoFiles" -> {
                            val root = call.argument<String>("path")
                                ?: return@setMethodCallHandler result.error("ARG", "path", null)
                            val hidden = call.argument<Boolean>("includeHidden") ?: false
                            val hiddenOnly = call.argument<Boolean>("hiddenOnly") ?: false
                            val skipNomedia = call.argument<Boolean>("skipNomedia") ?: true
                            val depth = if (hiddenOnly) 8 else 4
                            val budget = if (hiddenOnly) NativeConstants.HIDDEN_SCAN_BUDGET else NativeConstants.SCAN_BUDGET
                            io.execute {
                                try {
                                    val data = LibraryScanner.scan(File(root), depth, hidden, budget, hiddenOnly, skipNomedia)
                                    mainHandler.post { result.success(data) }
                                } catch (t: Throwable) {
                                    mainHandler.post { result.error("SCAN", t.message, null) }
                                }
                            }
                        }
                        "deletePath" -> {
                            val path = call.argument<String>("path")
                                ?: return@setMethodCallHandler result.error("ARG", "path", null)
                            result.success(deleteMediaFile(path))
                        }
                        "deletePaths" -> {
                            val paths = call.argument<List<String>>("paths") ?: emptyList()
                            var ok = true
                            for (path in paths) {
                                if (!deleteMediaFile(path)) ok = false
                            }
                            result.success(ok)
                        }
                        "renamePath" -> {
                            val path = call.argument<String>("path")
                                ?: return@setMethodCallHandler result.error("ARG", "path", null)
                            val name = call.argument<String>("name")
                                ?: return@setMethodCallHandler result.error("ARG", "name", null)
                            val src = File(path)
                            val dest = File(src.parentFile, name)
                            result.success(if (src.renameTo(dest)) dest.absolutePath else null)
                        }
                        "setKeepScreenOn" -> {
                            keepScreenOn = call.argument<Boolean>("on") ?: false
                            runOnUiThread {
                                if (keepScreenOn) window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                                else window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                            }
                            result.success(true)
                        }
                        "setPlaying" -> {
                            isPlaying = call.argument<Boolean>("on") ?: false
                            audioFocus.setPlaying(isPlaying)
                            if (isPlaying) claimPlayback(eventSink)
                            result.success(true)
                        }
                        "enterPip" -> {
                            if (!isPlaying) {
                                Toast.makeText(this, "Play a video first", Toast.LENGTH_SHORT).show()
                                result.success(false)
                            } else {
                                wantPip = true
                                runOnUiThread { enterPipNow() }
                                result.success(true)
                            }
                        }
                        "setPipEnabled" -> {
                            wantPip = call.argument<Boolean>("on") ?: false
                            result.success(wantPip)
                        }
                        "isPip" -> result.success(Build.VERSION.SDK_INT >= 26 && isInPictureInPictureMode)
                        "preparePreview" -> {
                            val path = call.argument<String>("path")
                            io.execute { bindPreview(path) }
                            result.success(true)
                        }
                        "setStereoVolume" -> {
                            val left = (call.argument<Double>("left") ?: 1.0).toFloat()
                            val right = (call.argument<Double>("right") ?: 1.0).toFloat()
                            equalizer.setStereoVolume(left, right)
                            result.success(true)
                        }
                        "toast" -> {
                            Toast.makeText(this, call.argument<String>("msg") ?: "", Toast.LENGTH_SHORT).show()
                            result.success(true)
                        }
                        "startBackground" -> {
                            val playing = call.argument<Boolean>("playing") ?: true
                            if (playing) claimPlayback(eventSink)
                            else ownerSink = eventSink ?: ownerSink
                            startPlaybackService(
                                if (PlaybackService.live()) PlaybackService.ACTION_UPDATE else PlaybackService.ACTION_START,
                                call.argument<String>("title") ?: "Video Player",
                                call.argument<String>("artist") ?: "Video Player",
                                playing,
                                call.argument<Int>("positionMs") ?: 0,
                                call.argument<Int>("durationMs") ?: 0
                            )
                            result.success(true)
                        }
                        "updateBackground" -> {
                            if (!PlaybackService.live()) {
                                result.success(false)
                                return@setMethodCallHandler
                            }
                            val playing = call.argument<Boolean>("playing") ?: true
                            if (ownerSink == null) {
                                if (playing) claimPlayback(eventSink) else ownerSink = eventSink
                            }
                            startPlaybackService(
                                PlaybackService.ACTION_UPDATE,
                                call.argument<String>("title") ?: "Video Player",
                                call.argument<String>("artist") ?: "Video Player",
                                playing,
                                call.argument<Int>("positionMs") ?: 0,
                                call.argument<Int>("durationMs") ?: 0
                            )
                            result.success(true)
                        }
                        "stopBackground" -> {
                            stopPlaybackService()
                            result.success(true)
                        }
                        "previewFrame" -> {
                            val path = call.argument<String>("path")
                                ?: return@setMethodCallHandler result.error("ARG", "path", null)
                            val positionMs = call.argument<Int>("positionMs") ?: 0
                            val longEdge = call.argument<Int>("longEdge") ?: 180
                            io.execute {
                                val bytes = previewJpeg(path, positionMs.toLong(), longEdge)
                                mainHandler.post { result.success(bytes) }
                            }
                        }
                        "thumbnailBytes" -> {
                            val path = call.argument<String>("path")
                                ?: return@setMethodCallHandler result.error("ARG", "path", null)
                            val size = call.argument<Int>("size") ?: 240
                            io.execute {
                                val bytes = LibraryScanner.thumbnailJpeg(path, size)
                                mainHandler.post { result.success(bytes) }
                            }
                        }
                        "screenshotWindow" -> {
                            val title = call.argument<String>("title") ?: "frame"
                            val path = call.argument<String>("path")
                            val positionMs = call.argument<Int>("positionMs") ?: 0
                            captureVideoShot(title, path, positionMs) { saved ->
                                mainHandler.post { result.success(saved) }
                            }
                        }
                        "listIndexedVideos" -> {
                            io.execute {
                                val list = listIndexedVideos()
                                mainHandler.post { result.success(list) }
                            }
                        }
                        "copyPath" -> {
                            val src = call.argument<String>("src")
                                ?: return@setMethodCallHandler result.error("ARG", "src", null)
                            val dest = call.argument<String>("dest")
                                ?: return@setMethodCallHandler result.error("ARG", "dest", null)
                            result.success(copyFileTo(src, dest))
                        }
                        "movePath" -> {
                            val src = call.argument<String>("src")
                                ?: return@setMethodCallHandler result.error("ARG", "src", null)
                            val dest = call.argument<String>("dest")
                                ?: return@setMethodCallHandler result.error("ARG", "dest", null)
                            result.success(moveFileTo(src, dest))
                        }
                        "fileSize" -> {
                            val path = call.argument<String>("path") ?: ""
                            val f = File(path)
                            result.success(if (f.exists()) f.length() else 0L)
                        }
                        "mediaInfo" -> {
                            val path = call.argument<String>("path")
                                ?: return@setMethodCallHandler result.error("ARG", "path", null)
                            result.success(readMediaInfo(path))
                        }
                        "pendingOpen" -> {
                            val path = pendingOpen
                            pendingOpen = null
                            result.success(path)
                        }
                        "lastCrash" -> result.success(NativeCrashLog.readLast(this))
                        "breadcrumb" -> {
                            NativeCrashLog.breadcrumb(this, call.argument<String>("action") ?: "")
                            result.success(true)
                        }
                        "pickerAllowMultiple" -> {
                            result.success(intent?.getBooleanExtra(Intent.EXTRA_ALLOW_MULTIPLE, false) == true)
                        }
                        "completePick" -> {
                            val path = call.argument<String>("path")
                            val paths = call.argument<List<String>>("paths")
                            result.success(finishPick(path, paths))
                        }
                        "cancelPick" -> {
                            cancelPick()
                            result.success(true)
                        }
                        else -> result.notImplemented()
                    }
                } catch (e: Throwable) {
                    NativeCrashLog.write(this, "channel ${call.method}: ${e.message}\n${Log.getStackTraceString(e)}")
                    result.error("ERR", e.message, null)
                }
            }
    }

    private fun bindPreview(path: String?) {
        if (path.isNullOrEmpty()) {
            try { previewRetriever?.release() } catch (_: Exception) {}
            previewRetriever = null
            previewBoundPath = null
            return
        }
        if (path == previewBoundPath && previewRetriever != null) return
        previewScaledOk = true
        try { previewRetriever?.release() } catch (_: Exception) {}
        previewRetriever = null
        previewBoundPath = null
        val r = MediaMetadataRetriever()
        try {
            val file = File(path)
            if (file.exists()) r.setDataSource(path) else r.setDataSource(this, Uri.parse(path))
            previewRetriever = r
            previewBoundPath = path
        } catch (_: Exception) {
            try { r.release() } catch (_: Exception) {}
        }
    }

    @Suppress("DEPRECATION")
    private fun deleteMediaFile(path: String): Boolean {
        val file = File(path)
        if (tryFileDelete(file)) return true
        val uri = mediaUriForPath(path) ?: return tryFileDelete(file) || !file.exists()
        return try {
            val rows = contentResolver.delete(uri, null, null)
            if (rows > 0) {
                tryFileDelete(file)
                true
            } else {
                tryFileDelete(file) || !file.exists()
            }
        } catch (_: SecurityException) {
            // Never launch RecoverableSecurityException's confirmation sheet.
            tryFileDelete(file) || !file.exists()
        } catch (_: Exception) {
            tryFileDelete(file) || !file.exists()
        }
    }

    private fun tryFileDelete(file: File): Boolean {
        return try {
            if (!file.exists()) return true
            if (file.delete()) {
                try {
                    MediaScannerConnection.scanFile(this, arrayOf(file.absolutePath), arrayOf("video/*"), null)
                } catch (_: Exception) {
                }
                true
            } else {
                false
            }
        } catch (_: Exception) {
            false
        }
    }

    @Suppress("DEPRECATION")
    private fun mediaUriForPath(path: String): Uri? {
        val name = File(path).name
        val collections = ArrayList<Uri>()
        collections.add(MediaStore.Video.Media.EXTERNAL_CONTENT_URI)
        collections.add(MediaStore.Files.getContentUri("external"))
        if (Build.VERSION.SDK_INT >= 29) {
            try {
                collections.add(MediaStore.Video.Media.getContentUri(MediaStore.VOLUME_EXTERNAL))
            } catch (_: Exception) {
            }
        }
        val projection = arrayOf(MediaStore.Video.Media._ID)
        for (collection in collections.distinct()) {
            try {
                contentResolver.query(
                    collection,
                    projection,
                    "${MediaStore.MediaColumns.DATA}=?",
                    arrayOf(path),
                    null
                )?.use { c ->
                    if (c.moveToFirst()) {
                        val id = c.getLong(0)
                        return ContentUris.withAppendedId(collection, id)
                    }
                }
            } catch (_: Exception) {
            }
        }
        for (collection in collections.distinct()) {
            try {
                contentResolver.query(
                    collection,
                    projection,
                    "${MediaStore.MediaColumns.DISPLAY_NAME}=?",
                    arrayOf(name),
                    null
                )?.use { c ->
                    if (c.count == 1 && c.moveToFirst()) {
                        val id = c.getLong(0)
                        return ContentUris.withAppendedId(collection, id)
                    }
                }
            } catch (_: Exception) {
            }
        }
        return null
    }

    private fun captureFrame(path: String, positionMs: Long, title: String): String? {
        val retriever = MediaMetadataRetriever()
        return try {
            val file = File(path)
            if (file.exists()) retriever.setDataSource(path) else retriever.setDataSource(this, Uri.parse(path))
            val bitmap = retriever.getFrameAtTime(positionMs * 1000, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
                ?: retriever.frameAtTime
                ?: return null
            val stamp = SimpleDateFormat("yyyyMMdd_HHmmss", Locale.US).format(Date())
            val safe = title.replace(Regex("[^A-Za-z0-9._-]"), "_").take(40)
            val name = "VID_${stamp}_$safe.jpg"
            val saved = saveToDcim(bitmap, name)
            bitmap.recycle()
            saved
        } catch (_: Exception) {
            null
        } finally {
            try {
                retriever.release()
            } catch (_: Exception) {
            }
        }
    }

    private fun saveToDcim(bitmap: Bitmap, name: String): String? {
        if (Build.VERSION.SDK_INT >= 29) {
            val values = ContentValues().apply {
                put(MediaStore.Images.Media.DISPLAY_NAME, name)
                put(MediaStore.Images.Media.MIME_TYPE, "image/jpeg")
                put(MediaStore.Images.Media.RELATIVE_PATH, Environment.DIRECTORY_DCIM + "/Screenshots")
                put(MediaStore.Images.Media.IS_PENDING, 1)
            }
            val uri = contentResolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values) ?: return writeLegacy(bitmap, name)
            return try {
                contentResolver.openOutputStream(uri)?.use { out ->
                    if (!bitmap.compress(Bitmap.CompressFormat.JPEG, 95, out)) return writeLegacy(bitmap, name)
                } ?: return writeLegacy(bitmap, name)
                values.clear()
                values.put(MediaStore.Images.Media.IS_PENDING, 0)
                contentResolver.update(uri, values, null, null)
                uri.toString()
            } catch (_: Exception) {
                writeLegacy(bitmap, name)
            }
        }
        return writeLegacy(bitmap, name)
    }

    private fun writeLegacy(bitmap: Bitmap, name: String): String? {
        return try {
            val dir = File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DCIM), "Screenshots")
            if (!dir.exists()) dir.mkdirs()
            val file = File(dir, name)
            FileOutputStream(file).use { out ->
                bitmap.compress(Bitmap.CompressFormat.JPEG, 95, out)
            }
            MediaScannerConnection.scanFile(this, arrayOf(file.absolutePath), arrayOf("image/jpeg"), null)
            file.absolutePath
        } catch (_: Exception) {
            null
        }
    }

    private fun readMediaInfo(path: String): Map<String, Any?> {
        val retriever = MediaMetadataRetriever()
        val map = HashMap<String, Any?>()
        try {
            val file = File(path)
            if (file.exists()) retriever.setDataSource(path) else retriever.setDataSource(this, Uri.parse(path))
            fun meta(key: Int) = retriever.extractMetadata(key)
            var width = meta(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)?.toIntOrNull() ?: 0
            var height = meta(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)?.toIntOrNull() ?: 0
            val duration = meta(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0L
            val bitrate = meta(MediaMetadataRetriever.METADATA_KEY_BITRATE)?.toIntOrNull() ?: 0
            val mime = meta(MediaMetadataRetriever.METADATA_KEY_MIMETYPE)
            var fps = 0.0
            if (Build.VERSION.SDK_INT >= 23) {
                fps = meta(MediaMetadataRetriever.METADATA_KEY_CAPTURE_FRAMERATE)?.toDoubleOrNull() ?: 0.0
            }
            var frames = 0
            if (Build.VERSION.SDK_INT >= 28) {
                frames = meta(MediaMetadataRetriever.METADATA_KEY_VIDEO_FRAME_COUNT)?.toIntOrNull() ?: 0
            }
            if (fps <= 0 && frames > 0 && duration > 0) fps = frames * 1000.0 / duration
            map["width"] = width
            map["height"] = height
            map["durationMs"] = duration
            map["bitrate"] = bitrate
            map["mime"] = mime
            map["fps"] = fps
            map["frameCount"] = frames
            mergeExtractor(path, map)
        } catch (_: Exception) {
        } finally {
            try {
                retriever.release()
            } catch (_: Exception) {
            }
        }
        return map
    }

    private fun mergeExtractor(path: String, map: HashMap<String, Any?>) {
        val extractor = MediaExtractor()
        try {
            if (path.startsWith("content:")) extractor.setDataSource(this, Uri.parse(path), null)
            else extractor.setDataSource(path)
            for (i in 0 until extractor.trackCount) {
                val format = extractor.getTrackFormat(i)
                val mime = format.getString(MediaFormat.KEY_MIME) ?: continue
                if (!mime.startsWith("video/")) continue
                fun gi(key: String) = if (format.containsKey(key)) format.getInteger(key) else null
                val w = gi(MediaFormat.KEY_WIDTH)
                val h = gi(MediaFormat.KEY_HEIGHT)
                if ((map["width"] as? Int ?: 0) <= 0 && w != null) map["width"] = w
                if ((map["height"] as? Int ?: 0) <= 0 && h != null) map["height"] = h
                val cropL = gi("crop-left") ?: 0
                val cropT = gi("crop-top") ?: 0
                val cropR = gi("crop-right")
                val cropB = gi("crop-bottom")
                var codedW = w ?: (map["width"] as? Int ?: 0)
                var codedH = h ?: (map["height"] as? Int ?: 0)
                if (cropR != null && cropR >= cropL) codedW = maxOf(codedW, cropR + 1)
                if (cropB != null && cropB >= cropT) codedH = maxOf(codedH, cropB + 1)
                map["codedW"] = codedW
                map["codedH"] = codedH
                if (Build.VERSION.SDK_INT >= 29) {
                    val sarW = gi("sar-width")
                    val sarH = gi("sar-height")
                    if (sarW != null && sarH != null && sarW > 0 && sarH > 0) {
                        map["sarNum"] = sarW
                        map["sarDen"] = sarH
                    }
                }
                map["codec"] = mime
                break
            }
        } catch (_: Exception) {
        } finally {
            try {
                extractor.release()
            } catch (_: Exception) {
            }
        }
    }

    private fun handleIncoming(intent: Intent?) {
        if (intent == null) return
        val uri: Uri? = when (intent.action) {
            Intent.ACTION_VIEW, Intent.ACTION_EDIT -> intent.data
            Intent.ACTION_SEND -> if (Build.VERSION.SDK_INT >= 33) {
                intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
            } else {
                @Suppress("DEPRECATION")
                intent.getParcelableExtra(Intent.EXTRA_STREAM)
            }
            else -> intent.data
        }
        if (uri == null) return
        val path = resolveUri(uri)
        if (path != null) {
            pendingOpen = path
            val listening = eventSink != null
            emit(mapOf("type" to "open", "path" to path))
            if (listening) pendingOpen = null
        }
    }

    private fun resolveUri(uri: Uri): String? {
        if (uri.scheme == "file") return uri.path
        if (uri.scheme == "content") {
            queryDisplayName(uri)?.let { name ->
                val cached = File(cacheDir, name)
                try {
                    contentResolver.openInputStream(uri)?.use { input ->
                        cached.outputStream().use { input.copyTo(it) }
                    }
                    return cached.absolutePath
                } catch (_: Exception) {
                }
            }
            if (uri.path != null && File(uri.path!!).exists()) return uri.path
        }
        return uri.path
    }

    private fun queryDisplayName(uri: Uri): String? {
        contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { c ->
            if (c.moveToFirst()) {
                val idx = c.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (idx >= 0) return c.getString(idx)
            }
        }
        return uri.lastPathSegment
    }

    private fun startPlaybackService(
        action: String,
        title: String,
        artist: String,
        playing: Boolean,
        positionMs: Int,
        durationMs: Int
    ) {
        val intent = Intent(this, PlaybackService::class.java).apply {
            this.action = action
            putExtra("title", title)
            putExtra("artist", artist)
            putExtra("playing", playing)
            putExtra("positionMs", positionMs)
            putExtra("durationMs", durationMs)
        }
        try {
            if (PlaybackService.live()) {
                startService(intent)
            } else if (Build.VERSION.SDK_INT >= 26) {
                PlaybackService.starting = true
                try {
                    startForegroundService(intent)
                } catch (t: Throwable) {
                    PlaybackService.starting = false
                    startService(intent)
                }
            } else {
                startService(intent)
            }
        } catch (t: Throwable) {
            PlaybackService.starting = false
            try {
                startService(intent)
            } catch (t2: Throwable) {
                NativeCrashLog.write(this, "playback service: ${t2.message}\n${Log.getStackTraceString(t2)}")
            }
        }
    }

    private fun stopPlaybackService() {
        val stop = Intent(this, PlaybackService::class.java).setAction(PlaybackService.ACTION_STOP)
        try {
            if (PlaybackService.live()) {
                startService(stop)
            } else {
                stopService(Intent(this, PlaybackService::class.java))
            }
        } catch (_: Throwable) {
            try {
                stopService(Intent(this, PlaybackService::class.java))
            } catch (_: Throwable) {
            }
        }
    }

    private fun emit(payload: Map<String, Any?>) {
        mainHandler.post {
            try {
                eventSink?.success(payload)
            } catch (_: Throwable) {
            }
        }
    }

    private fun enterPipNow() {
        if (!isPlaying) return
        if (Build.VERSION.SDK_INT >= 26 && !isInPictureInPictureMode) {
            val params = PictureInPictureParams.Builder()
                .setAspectRatio(Rational(16, 9))
                .build()
            enterPictureInPictureMode(params)
        }
    }

    open override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        if (wantPip && isPlaying && Build.VERSION.SDK_INT >= 26) {
            enterPipNow()
        }
    }

    private fun listVolumes(): List<Map<String, Any?>> {
        val out = ArrayList<Map<String, Any?>>()
        val sm = getSystemService(STORAGE_SERVICE) as StorageManager
        for (volume in sm.storageVolumes) {
            val path = volumePath(volume)
            val map = HashMap<String, Any?>()
            map["path"] = path
            map["description"] = volume.getDescription(this)
            map["isPrimary"] = volume.isPrimary
            map["isRemovable"] = volume.isRemovable
            map["state"] = volume.state
            map["isSd"] = volume.isRemovable && path?.contains("usb", true) != true
            map["isUsb"] = path?.contains("usb", true) == true ||
                volume.getDescription(this).contains("usb", true) ||
                volume.getDescription(this).contains("otg", true)
            out.add(map)
        }
        val ext = Environment.getExternalStorageDirectory()?.absolutePath
        if (out.none { it["path"] == ext } && ext != null) {
            out.add(
                mapOf(
                    "path" to ext,
                    "description" to "Internal storage",
                    "isPrimary" to true,
                    "isRemovable" to false,
                    "state" to "mounted",
                    "isSd" to false,
                    "isUsb" to false
                )
            )
        }
        return out
    }

    private fun volumePath(volume: android.os.storage.StorageVolume): String? {
        if (Build.VERSION.SDK_INT >= 30) {
            return volume.directory?.absolutePath
        }
        if (volume.isPrimary) {
            return Environment.getExternalStorageDirectory()?.absolutePath
        }
        val uuid = volume.uuid ?: return null
        val candidate = File("/storage/$uuid")
        return if (candidate.exists()) candidate.absolutePath else null
    }

    private fun startLibraryWatcher(volumeMaps: List<Map<String, Any?>>? = null) {
        val maps = volumeMaps ?: try {
            listVolumes()
        } catch (_: Exception) {
            emptyList()
        }
        val roots = maps.mapNotNull { (it["path"] as? String)?.takeIf { p -> p.isNotEmpty() }?.let { p -> File(p) } }
        val watcher = libraryWatcher ?: LibraryWatcher(this) {
            emitMedia("refresh")
        }.also { libraryWatcher = it }
        io.execute {
            try {
                watcher.start(roots)
            } catch (_: Exception) {
            }
        }
    }

    @Suppress("DEPRECATION")
    private fun listIndexedVideos(): List<Map<String, Any?>> {
        val out = ArrayList<Map<String, Any?>>()
        val projection = arrayOf(
            MediaStore.Video.Media._ID,
            MediaStore.Video.Media.DATA,
            MediaStore.Video.Media.DISPLAY_NAME,
            MediaStore.Video.Media.SIZE,
            MediaStore.Video.Media.DATE_MODIFIED,
            MediaStore.Video.Media.DURATION,
            MediaStore.Video.Media.WIDTH,
            MediaStore.Video.Media.HEIGHT,
            MediaStore.Video.Media.MIME_TYPE
        )
        val uri = if (Build.VERSION.SDK_INT >= 29) {
            MediaStore.Video.Media.getContentUri(MediaStore.VOLUME_EXTERNAL)
        } else {
            MediaStore.Video.Media.EXTERNAL_CONTENT_URI
        }
        try {
            contentResolver.query(
                uri,
                projection,
                null,
                null,
                "${MediaStore.Video.Media.DATE_MODIFIED} DESC"
            )?.use { c ->
                val iId = c.getColumnIndex(MediaStore.Video.Media._ID)
                val iData = c.getColumnIndex(MediaStore.Video.Media.DATA)
                val iName = c.getColumnIndex(MediaStore.Video.Media.DISPLAY_NAME)
                val iSize = c.getColumnIndex(MediaStore.Video.Media.SIZE)
                val iMod = c.getColumnIndex(MediaStore.Video.Media.DATE_MODIFIED)
                val iDur = c.getColumnIndex(MediaStore.Video.Media.DURATION)
                val iW = c.getColumnIndex(MediaStore.Video.Media.WIDTH)
                val iH = c.getColumnIndex(MediaStore.Video.Media.HEIGHT)
                val iMime = c.getColumnIndex(MediaStore.Video.Media.MIME_TYPE)
                while (c.moveToNext() && out.size < NativeConstants.INDEXED_CAP) {
                    val path = if (iData >= 0) c.getString(iData) else null
                    if (path.isNullOrBlank()) continue
                    val file = File(path)
                    if (file.exists() && file.isFile && !isVideoFile(file)) continue
                    var size = if (iSize >= 0) c.getLong(iSize) else 0L
                    if (size <= 0 && file.exists()) size = file.length()
                    val name = if (iName >= 0) c.getString(iName) ?: file.name else file.name
                    val modified = if (iMod >= 0) c.getLong(iMod) * 1000 else file.lastModified()
                    out.add(
                        mapOf(
                            "id" to if (iId >= 0) c.getLong(iId).toString() else path,
                            "path" to path,
                            "name" to name,
                            "size" to size,
                            "modified" to modified,
                            "durationMs" to if (iDur >= 0) c.getLong(iDur) else 0L,
                            "width" to if (iW >= 0) c.getInt(iW) else 0,
                            "height" to if (iH >= 0) c.getInt(iH) else 0,
                            "mime" to if (iMime >= 0) c.getString(iMime) else null,
                            "folder" to (file.parent ?: "")
                        )
                    )
                }
            }
        } catch (_: Exception) {
        }
        return out
    }

    private fun copyFileTo(src: String, dest: String): Boolean {
        return try {
            val s = File(src)
            val d = File(dest)
            if (!s.exists()) return false
            d.parentFile?.mkdirs()
            s.inputStream().use { input -> d.outputStream().use { input.copyTo(it) } }
            MediaScannerConnection.scanFile(this, arrayOf(d.absolutePath), arrayOf("video/*"), null)
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun moveFileTo(src: String, dest: String): String? {
        return try {
            val s = File(src)
            val d = File(dest)
            if (!s.exists()) return null
            d.parentFile?.mkdirs()
            if (s.renameTo(d)) {
                MediaScannerConnection.scanFile(this, arrayOf(d.absolutePath, s.absolutePath), arrayOf("video/*", "video/*"), null)
                return d.absolutePath
            }
            if (copyFileTo(src, dest)) {
                tryFileDelete(s)
                d.absolutePath
            } else {
                null
            }
        } catch (_: Exception) {
            null
        }
    }

    private fun previewJpeg(path: String, positionMs: Long, longEdge: Int): ByteArray? {
        if (previewBoundPath != path || previewRetriever == null) bindPreview(path)
        val retriever = previewRetriever
        if (retriever != null) {
            try {
                return frameToJpeg(retriever, positionMs, longEdge)
            } catch (_: Exception) {
                bindPreview(path)
                previewRetriever?.let {
                    return try {
                        frameToJpeg(it, positionMs, longEdge)
                    } catch (_: Exception) {
                        null
                    }
                }
            }
        }
        return null
    }

    // false once getScaledFrameAtTime proved to return a distorted aspect for this video.
    private var previewScaledOk = true

    private fun frameToJpeg(retriever: MediaMetadataRetriever, positionMs: Long, longEdge: Int): ByteArray? {
        val us = positionMs * 1000
        val option = MediaMetadataRetriever.OPTION_PREVIOUS_SYNC
        val edge = longEdge.coerceIn(120, 720)
        var vw = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)?.toIntOrNull() ?: 0
        var vh = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)?.toIntOrNull() ?: 0
        val rot = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)?.toIntOrNull() ?: 0
        if (rot == 90 || rot == 270) { val t = vw; vw = vh; vh = t }
        val ar = if (vw > 0 && vh > 0) vw.toFloat() / vh else 16f / 9f
        // Keep the video's own aspect ratio: no stretching, no cropping.
        val dw = if (ar >= 1f) edge else (edge * ar).toInt().coerceAtLeast(1)
        val dh = if (ar >= 1f) (edge / ar).toInt().coerceAtLeast(1) else edge

        var bmp: Bitmap? = null
        if (Build.VERSION.SDK_INT >= 27 && previewScaledOk) {
            bmp = retriever.getScaledFrameAtTime(us, option, dw, dh)
                ?: retriever.getScaledFrameAtTime(us, MediaMetadataRetriever.OPTION_CLOSEST, dw, dh)
            if (bmp != null) {
                val got = bmp.width.toFloat() / bmp.height
                val want = dw.toFloat() / dh
                if (Math.abs(got / want - 1f) > 0.06f) {
                    previewScaledOk = false
                    bmp.recycle()
                    bmp = null
                }
            }
        }
        if (bmp == null) {
            val full = retriever.getFrameAtTime(us, option) ?: retriever.frameAtTime
            if (full != null) {
                val sc = edge.toFloat() / maxOf(full.width, full.height)
                bmp = if (sc < 1f) {
                    val scaled = Bitmap.createScaledBitmap(
                        full,
                        (full.width * sc).toInt().coerceAtLeast(1),
                        (full.height * sc).toInt().coerceAtLeast(1),
                        true
                    )
                    if (scaled !== full) full.recycle()
                    scaled
                } else {
                    full
                }
            }
        }
        if (bmp == null) return null
        val out = java.io.ByteArrayOutputStream()
        bmp.compress(Bitmap.CompressFormat.JPEG, 85, out)
        bmp.recycle()
        return out.toByteArray()
    }

    private fun collectViews(view: View, surfaces: MutableList<SurfaceView>, textures: MutableList<TextureView>) {
        when (view) {
            is SurfaceView -> surfaces.add(view)
            is TextureView -> textures.add(view)
        }
        if (view is ViewGroup) {
            for (i in 0 until view.childCount) {
                collectViews(view.getChildAt(i), surfaces, textures)
            }
        }
    }

    private fun isMostlyBlack(bmp: Bitmap): Boolean {
        val w = bmp.width
        val h = bmp.height
        if (w < 4 || h < 4) return true
        val stepX = (w / 8).coerceAtLeast(1)
        val stepY = (h / 8).coerceAtLeast(1)
        var dark = 0
        var n = 0
        var y = 0
        while (y < h) {
            var x = 0
            while (x < w) {
                val c = bmp.getPixel(x, y)
                if (Color.red(c) + Color.green(c) + Color.blue(c) < 48) dark++
                n++
                x += stepX
            }
            y += stepY
        }
        return n == 0 || dark * 10 >= n * 8
    }

    private fun captureVideoShot(title: String, path: String?, positionMs: Int, done: (String?) -> Unit) {
        fun fallback() {
            if (path.isNullOrEmpty()) {
                done(null)
                return
            }
            io.execute { done(captureFrame(path, positionMs.toLong(), title)) }
        }

        fun saveBmp(bmp: Bitmap) {
            io.execute {
                val out = java.io.ByteArrayOutputStream()
                bmp.compress(Bitmap.CompressFormat.JPEG, 92, out)
                bmp.recycle()
                done(saveJpegBytes(out.toByteArray(), title))
            }
        }

        val root = window?.decorView
        if (root == null) {
            fallback()
            return
        }
        val surfaces = mutableListOf<SurfaceView>()
        val textures = mutableListOf<TextureView>()
        collectViews(root, surfaces, textures)

        val tex = textures.maxByOrNull { it.width * it.height }
        if (tex != null && tex.isAvailable && tex.width > 8 && tex.height > 8) {
            try {
                val bmp = tex.getBitmap()
                if (bmp != null && !isMostlyBlack(bmp)) {
                    saveBmp(bmp)
                    return
                }
                bmp?.recycle()
            } catch (_: Exception) {
            }
        }

        val surface = surfaces.maxByOrNull { it.width * it.height }
        if (Build.VERSION.SDK_INT >= 24 && surface != null && surface.width > 8 && surface.height > 8) {
            val bmp = Bitmap.createBitmap(surface.width, surface.height, Bitmap.Config.ARGB_8888)
            try {
                PixelCopy.request(surface, bmp, { code ->
                    if (code == PixelCopy.SUCCESS && !isMostlyBlack(bmp)) {
                        saveBmp(bmp)
                    } else {
                        try {
                            bmp.recycle()
                        } catch (_: Exception) {
                        }
                        fallback()
                    }
                }, mainHandler)
                return
            } catch (_: Exception) {
                try {
                    bmp.recycle()
                } catch (_: Exception) {
                }
            }
        }

        fallback()
    }

    private fun saveJpegBytes(bytes: ByteArray, title: String): String? {
        val stamp = SimpleDateFormat("yyyyMMdd_HHmmss", Locale.US).format(Date())
        val safe = title.replace(Regex("[^A-Za-z0-9._-]"), "_").take(40)
        val name = "VID_${stamp}_$safe.jpg"
        if (Build.VERSION.SDK_INT >= 29) {
            val values = ContentValues().apply {
                put(MediaStore.Images.Media.DISPLAY_NAME, name)
                put(MediaStore.Images.Media.MIME_TYPE, "image/jpeg")
                put(MediaStore.Images.Media.RELATIVE_PATH, Environment.DIRECTORY_DCIM + "/Screenshots")
                put(MediaStore.Images.Media.IS_PENDING, 1)
            }
            val uri = contentResolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values)
                ?: return writeLegacyBytes(bytes, name)
            return try {
                contentResolver.openOutputStream(uri)?.use { it.write(bytes) }
                    ?: return writeLegacyBytes(bytes, name)
                values.clear()
                values.put(MediaStore.Images.Media.IS_PENDING, 0)
                contentResolver.update(uri, values, null, null)
                uri.toString()
            } catch (_: Exception) {
                writeLegacyBytes(bytes, name)
            }
        }
        return writeLegacyBytes(bytes, name)
    }

    private fun writeLegacyBytes(bytes: ByteArray, name: String): String? {
        return try {
            val dir = File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DCIM), "Screenshots")
            if (!dir.exists()) dir.mkdirs()
            val file = File(dir, name)
            FileOutputStream(file).use { it.write(bytes) }
            MediaScannerConnection.scanFile(this, arrayOf(file.absolutePath), arrayOf("image/jpeg"), null)
            file.absolutePath
        } catch (_: Exception) {
            null
        }
    }

    private fun isPickerIntent(): Boolean {
        val action = intent?.action ?: return false
        return action == Intent.ACTION_GET_CONTENT || action == Intent.ACTION_PICK
    }

    private fun cancelPick() {
        if (!isPickerIntent()) return
        setResult(Activity.RESULT_CANCELED)
        finish()
    }

    private fun finishPick(path: String?, paths: List<String>?): Boolean {
        if (!isPickerIntent()) return false
        val files = ArrayList<File>()
        if (!paths.isNullOrEmpty()) {
            for (p in paths) {
                if (p.isNotBlank()) files.add(File(p))
            }
        } else if (!path.isNullOrBlank()) {
            files.add(File(path))
        }
        val existing = files.filter { it.exists() && it.isFile }
        if (existing.isEmpty()) return false
        val uris = existing.mapNotNull { shareUri(it) }
        if (uris.isEmpty()) return false
        val mime = mimeOfFile(existing.first())
        val reply = Intent()
        if (uris.size == 1) {
            reply.setDataAndType(uris[0], mime)
        } else {
            reply.type = "video/*"
            val clip = ClipData(ClipDescription("videos", arrayOf("video/*")), ClipData.Item(uris[0]))
            for (i in 1 until uris.size) clip.addItem(ClipData.Item(uris[i]))
            reply.clipData = clip
        }
        reply.addFlags(
            Intent.FLAG_GRANT_READ_URI_PERMISSION or
                Intent.FLAG_GRANT_PREFIX_URI_PERMISSION
        )
        val pkg = callingPackage
        if (pkg != null) {
            for (uri in uris) {
                try {
                    grantUriPermission(pkg, uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
                } catch (_: Exception) {
                }
            }
        }
        setResult(Activity.RESULT_OK, reply)
        finish()
        return true
    }

    private fun shareUri(file: File): Uri? {
        return try {
            FileProvider.getUriForFile(this, "$packageName.fileprovider", file)
        } catch (_: Exception) {
            mediaUriForPath(file.absolutePath) ?: try {
                Uri.fromFile(file)
            } catch (_: Exception) {
                null
            }
        }
    }

    private fun mimeOfFile(file: File): String {
        val ext = file.extension.lowercase()
        return MimeTypeMap.getSingleton().getMimeTypeFromExtension(ext) ?: "video/*"
    }

    companion object {
        var eventsSink: EventChannel.EventSink? = null
        private val mediaSinks = CopyOnWriteArrayList<EventChannel.EventSink>()
        private val emitHandler = Handler(Looper.getMainLooper())
        @Volatile
        var ownerSink: EventChannel.EventSink? = null

        fun addMediaSink(sink: EventChannel.EventSink) {
            if (!mediaSinks.contains(sink)) mediaSinks.add(sink)
            eventsSink = sink
        }

        fun removeMediaSink(sink: EventChannel.EventSink) {
            mediaSinks.remove(sink)
            if (eventsSink === sink) eventsSink = mediaSinks.lastOrNull()
            if (ownerSink === sink) ownerSink = mediaSinks.lastOrNull()
        }

        fun claimPlayback(sink: EventChannel.EventSink?) {
            ownerSink = sink
            if (sink != null) pauseOthers(sink)
        }

        fun pauseOthers(except: EventChannel.EventSink?) {
            val payload = hashMapOf<String, Any?>("type" to "media", "action" to "pause")
            val send = Runnable {
                for (s in mediaSinks) {
                    if (s === except) continue
                    try {
                        s.success(payload)
                    } catch (_: Throwable) {
                    }
                }
            }
            if (Looper.myLooper() == Looper.getMainLooper()) send.run() else emitHandler.post(send)
        }

        fun emitMedia(action: String, extra: Map<String, Any?> = emptyMap()) {
            val payload = HashMap<String, Any?>(extra.size + 2)
            payload["type"] = "media"
            payload["action"] = action
            payload.putAll(extra)
            val send = Runnable {
                val targets: List<EventChannel.EventSink> = when {
                    action == "refresh" || action == "pause" -> mediaSinks.toList()
                    ownerSink != null -> listOf(ownerSink!!)
                    else -> mediaSinks.toList()
                }
                for (s in targets) {
                    try {
                        s.success(payload)
                    } catch (_: Throwable) {
                    }
                }
            }
            if (Looper.myLooper() == Looper.getMainLooper()) send.run() else emitHandler.post(send)
        }

        fun isVideoFile(f: File): Boolean {
            if (!f.isFile || f.length() <= 0L) return false
            val name = f.name.lowercase()
            if (name.endsWith(".d.ts")) return false
            val ext = f.extension.lowercase()
            if (ext == "ts") return isMpegTs(f)
            if (ext in NativeConstants.SKIP_EXT) return false
            if (isPlainText(f)) return false
            if (ext in NativeConstants.VIDEO_EXT) return true
            if (isNonVideoMagic(f)) return false
            if (hasVideoMagic(f)) return true
            if (f.length() < 8192L) return false
            return hasVideoTrack(f)
        }

        private fun isMpegTs(f: File): Boolean {
            if (f.length() < 188) return false
            return try {
                f.inputStream().use { it.read() == 0x47 }
            } catch (_: Exception) {
                false
            }
        }

        private fun isPlainText(f: File): Boolean {
            return try {
                f.inputStream().use { ins ->
                    val b = ByteArray(512)
                    val n = ins.read(b)
                    if (n <= 0) return false
                    bytesArePlainText(b, n)
                }
            } catch (_: Exception) {
                false
            }
        }

        private fun bytesArePlainText(b: ByteArray, n: Int): Boolean {
            if (n <= 0) return false
            val b0 = b[0].toInt() and 0xFF
            val b1 = if (n > 1) b[1].toInt() and 0xFF else 0
            if (n >= 2 && ((b0 == 0xFF && b1 == 0xFE) || (b0 == 0xFE && b1 == 0xFF))) return true
            var i = 0
            if (n >= 3 && b0 == 0xEF && b1 == 0xBB && (b[2].toInt() and 0xFF) == 0xBF) {
                i = 3
                if (i >= n) return true
            }
            var nul = 0
            var ctrl = 0
            var text = 0
            var high = 0
            var j = i
            while (j < n) {
                val u = b[j].toInt() and 0xFF
                when {
                    u == 0 -> nul++
                    u == 0x09 || u == 0x0A || u == 0x0D -> text++
                    u in 0x20..0x7E -> text++
                    u < 0x20 || u == 0x7F -> ctrl++
                    else -> high++
                }
                j++
            }
            val len = n - i
            if (len <= 0) return true
            if (nul > 0) return nul * 5 >= len * 2 && text * 5 >= len * 2
            if (ctrl * 20 > len) return false
            if (text * 100 >= len * 85) return true
            return ctrl == 0 && high > 0 && text + high == len && utf8LooksValid(b, i, n)
        }

        private fun utf8LooksValid(b: ByteArray, start: Int, n: Int): Boolean {
            var i = start
            while (i < n) {
                val c = b[i].toInt() and 0xFF
                val need = when {
                    c < 0x80 -> 0
                    c in 0xC2..0xDF -> 1
                    c in 0xE0..0xEF -> 2
                    c in 0xF0..0xF4 -> 3
                    else -> return false
                }
                if (i + need >= n) return true
                var k = 1
                while (k <= need) {
                    if (b[i + k].toInt() and 0xC0 != 0x80) return false
                    k++
                }
                i += 1 + need
            }
            return true
        }

        private fun isNonVideoMagic(f: File): Boolean {
            return try {
                f.inputStream().use { ins ->
                    val b = ByteArray(12)
                    val n = ins.read(b)
                    if (n < 3) return true
                    if (b[0] == 0xFF.toByte() && b[1] == 0xD8.toByte() && b[2] == 0xFF.toByte()) return true
                    if (n >= 8 && b[0] == 0x89.toByte() && b[1] == 0x50.toByte() && b[2] == 0x4E.toByte() && b[3] == 0x47.toByte()) return true
                    if (b[0] == 0x47.toByte() && b[1] == 0x49.toByte() && b[2] == 0x46.toByte()) return true
                    if (n >= 4 && b[0] == 0x25.toByte() && b[1] == 0x50.toByte() && b[2] == 0x44.toByte() && b[3] == 0x46.toByte()) return true
                    if (n >= 4 && b[0] == 0x50.toByte() && b[1] == 0x4B.toByte() && b[2] == 0x03.toByte() && b[3] == 0x04.toByte()) return true
                    if (n >= 4 && b[0] == 0x7F.toByte() && b[1] == 0x45.toByte() && b[2] == 0x4C.toByte() && b[3] == 0x46.toByte()) return true
                    if (n >= 12 && b[0] == 0x52.toByte() && b[1] == 0x49.toByte() && b[2] == 0x46.toByte() && b[3] == 0x46.toByte()) {
                        val kind = String(b, 8, 4, Charsets.US_ASCII)
                        if (kind == "WAVE" || kind == "WEBP") return true
                    }
                    if (n >= 3 && b[0] == 0x49.toByte() && b[1] == 0x44.toByte() && b[2] == 0x33.toByte()) return true
                    if (n >= 4 && b[0] == 0x66.toByte() && b[1] == 0x4C.toByte() && b[2] == 0x61.toByte() && b[3] == 0x43.toByte()) return true
                    if (n >= 4 && b[0] == 0x4F.toByte() && b[1] == 0x67.toByte() && b[2] == 0x67.toByte() && b[3] == 0x53.toByte()) return true
                    false
                }
            } catch (_: Exception) {
                false
            }
        }

        private fun hasVideoMagic(f: File): Boolean {
            return try {
                f.inputStream().use { ins ->
                    val b = ByteArray(16)
                    val n = ins.read(b)
                    if (n < 4) return false
                    if (n >= 8 && b[4] == 0x66.toByte() && b[5] == 0x74.toByte() && b[6] == 0x79.toByte() && b[7] == 0x70.toByte()) return true
                    if (b[0] == 0x1A.toByte() && b[1] == 0x45.toByte() && b[2] == 0xDF.toByte() && b[3] == 0xA3.toByte()) return true
                    if (n >= 12 && b[0] == 0x52.toByte() && b[1] == 0x49.toByte() && b[2] == 0x46.toByte() && b[3] == 0x46.toByte()) {
                        val kind = String(b, 8, 4, Charsets.US_ASCII)
                        if (kind == "AVI " || kind == "AVIX") return true
                    }
                    if (b[0] == 0x46.toByte() && b[1] == 0x4C.toByte() && b[2] == 0x56.toByte()) return true
                    if (b[0] == 0.toByte() && b[1] == 0.toByte() && b[2] == 1.toByte() &&
                        (b[3] == 0xBA.toByte() || b[3] == 0xB3.toByte())) return true
                    if (n >= 8 && b[0] == 0x30.toByte() && b[1] == 0x26.toByte() && b[2] == 0xB2.toByte() && b[3] == 0x75.toByte()) return true
                    if (b[0] == 0x47.toByte() && f.length() >= 188L) return isMpegTs(f)
                    false
                }
            } catch (_: Exception) {
                false
            }
        }

        private fun hasVideoTrack(f: File): Boolean {
            val extractor = MediaExtractor()
            return try {
                extractor.setDataSource(f.absolutePath)
                for (i in 0 until extractor.trackCount) {
                    val mime = extractor.getTrackFormat(i).getString(MediaFormat.KEY_MIME) ?: continue
                    if (mime.startsWith("video/")) return true
                }
                false
            } catch (_: Exception) {
                false
            } finally {
                try {
                    extractor.release()
                } catch (_: Exception) {
                }
            }
        }
    }
}
