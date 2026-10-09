package com.mounsokdara.video_player

import android.content.Intent
import android.provider.Settings
import com.mounsokdara.video_player.accessibility.livecaption.LiveCaptionActivity
import com.mounsokdara.video_player.accessibility.livecaption.LiveCaptionEngine
import com.mounsokdara.video_player.accessibility.livecaption.aimodeltranscribe.AiModelTranscribeActivity
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class AppNative(
    private val activity: FlutterActivity,
    val systemBars: SystemBarController,
    val audioFocus: AudioFocusController,
    val equalizer: EqualizerController
) {
    fun handleLocal(method: String, call: io.flutter.plugin.common.MethodCall, result: MethodChannel.Result): Boolean {
        when (method) {
            NativeConstants.Method.APPLY_SYSTEM_BARS -> {
                val light = call.argument<Boolean>("lightIcons") ?: true
                val contrast = call.argument<Boolean>("contrast") ?: true
                val hide = call.argument<Boolean>("hide") ?: false
                systemBars.apply(light, contrast, hide)
                result.success(true)
                return true
            }
            NativeConstants.Method.SET_ORIENTATION -> {
                OrientationController.apply(activity, call.argument<String>("mode") ?: NativeConstants.Orient.AUTO)
                result.success(true)
                return true
            }
            NativeConstants.Method.REQUEST_AUDIO_FOCUS -> {
                audioFocus.request()
                result.success(true)
                return true
            }
            NativeConstants.Method.ABANDON_AUDIO_FOCUS -> {
                audioFocus.abandon()
                result.success(true)
                return true
            }
            NativeConstants.Method.APPLY_EQUALIZER -> {
                equalizer.apply(
                    call.argument<Boolean>("enabled") ?: false,
                    call.argument<List<Int>>("bands") ?: emptyList(),
                    call.argument<Boolean>("bassOn") ?: false,
                    call.argument<Int>("bass") ?: 0,
                    call.argument<Boolean>("surroundOn") ?: false,
                    call.argument<Int>("surround") ?: 0
                )
                result.success(true)
                return true
            }
            NativeConstants.Method.OPEN_ACTIVITY -> {
                // Screens that run as their own activity: opened with the system slide transition.
                val target = when (call.argument<String>("route")) {
                    "/settings" -> SettingsActivity::class.java
                    "/general" -> GeneralSettingsActivity::class.java
                    "/video" -> VideoSettingsActivity::class.java
                    "/accessibility" -> AccessibilitySettingsActivity::class.java
                    "/theme" -> ThemeSettingsActivity::class.java
                    "/about" -> AboutActivity::class.java
                    "/equalizer" -> EqualizerActivity::class.java
                    "/licenses" -> LicensesActivity::class.java
                    "/changelog" -> ChangelogActivity::class.java
                    "/console" -> ConsoleActivity::class.java
                    "/quick-actions" -> QuickActionsActivity::class.java
                    "/title-bar" -> TitleBarButtonsActivity::class.java
                    "/floating-buttons" -> FloatingButtonsActivity::class.java
                    "/live-caption" -> LiveCaptionActivity::class.java
                    "/live-caption/ai-model" -> AiModelTranscribeActivity::class.java
                    else -> null
                }
                if (target != null) activity.startActivity(Intent(activity, target))
                result.success(target != null)
                return true
            }
            "openCaptionSettings" -> {
                try {
                    activity.startActivity(Intent(Settings.ACTION_CAPTIONING_SETTINGS))
                } catch (_: Exception) {
                    try {
                        activity.startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
                    } catch (_: Exception) {
                    }
                }
                result.success(true)
                return true
            }
            "liveCaptionStart" -> {
                val path = call.argument<String>("path") ?: ""
                val pos = (call.argument<Number>("positionMs") ?: 0).toLong()
                if (path.isNotEmpty()) LiveCaptionEngine.start(activity.applicationContext, path, pos)
                result.success(path.isNotEmpty())
                return true
            }
            "liveCaptionPlayhead" -> {
                LiveCaptionEngine.playhead((call.argument<Number>("positionMs") ?: 0).toLong())
                result.success(true)
                return true
            }
            "liveCaptionStop" -> {
                LiveCaptionEngine.stop(call.argument<Boolean>("release") ?: false)
                result.success(true)
                return true
            }
            "liveCaptionStatus" -> {
                result.success(LiveCaptionEngine.status(activity.applicationContext))
                return true
            }
            NativeConstants.Method.DEBUG_LOG -> {
                DeveloperLog.append(activity, call.argument<String>("line") ?: "")
                result.success(true)
                return true
            }
            NativeConstants.Method.CLEAR_LOGS -> {
                DeveloperLog.append(activity, "__clear__")
                NativeCrashLog.clear(activity)
                result.success(true)
                return true
            }
            NativeConstants.Method.READ_DEBUG_LOG -> {
                result.success(DeveloperLog.read(activity))
                return true
            }
            NativeConstants.Method.PEEK_CRASH -> {
                result.success(NativeCrashLog.peek(activity))
                return true
            }
            else -> return false
        }
    }
}