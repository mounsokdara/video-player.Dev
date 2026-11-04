package com.mounsokdara.video_player.engine

import android.view.Surface
import java.nio.ByteBuffer

object SwNative {
    val available: Boolean = try {
        System.loadLibrary("swdecode")
        true
    } catch (e: Throwable) {
        false
    }

    const val NONE = Long.MIN_VALUE
    const val EOS = Long.MIN_VALUE + 1
    const val ERR = Long.MIN_VALUE + 2

    @JvmStatic external fun nCreate(csd: ByteArray, threads: Int, codecId: Int): Long
    @JvmStatic external fun nSetSurface(h: Long, surface: Surface)
    @JvmStatic external fun nSend(h: Long, buf: ByteBuffer, size: Int, ptsUs: Long): Int
    @JvmStatic external fun nSendEos(h: Long): Int
    @JvmStatic external fun nReceive(h: Long): Long
    @JvmStatic external fun nPresent(h: Long): Int
    @JvmStatic external fun nDrop(h: Long)
    @JvmStatic external fun nFlush(h: Long)
    @JvmStatic external fun nSetSkip(h: Long, mode: Int)
    @JvmStatic external fun nSetTuning(h: Long, peakNits: Int, gammaPct: Int)
    @JvmStatic external fun nRelease(h: Long)
}
