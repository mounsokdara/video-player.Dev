package com.mounsokdara.video_player

import android.content.Intent
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
            NativeConstants.Method.OPEN_SETTINGS -> {
                activity.startActivity(Intent(activity, SettingsActivity::class.java))
                result.success(true)
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
            else -> return false
        }
    }
}