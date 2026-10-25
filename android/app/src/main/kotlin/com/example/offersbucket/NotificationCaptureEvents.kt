package com.example.offersbucket

import android.os.Handler
import android.os.Looper

/** Signals only; notification content is never broadcast outside this process. */
internal object NotificationCaptureEvents {
    private val handler = Handler(Looper.getMainLooper())
    private val listeners = mutableSetOf<() -> Unit>()

    fun add(listener: () -> Unit) {
        listeners.add(listener)
    }

    fun remove(listener: () -> Unit) {
        listeners.remove(listener)
    }

    fun changed() {
        handler.post { listeners.toList().forEach { it() } }
    }
}
