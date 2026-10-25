package com.example.offersbucket

import android.app.Notification
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log
import org.json.JSONObject
import java.security.MessageDigest

class OfferNotificationListenerService : NotificationListenerService() {
    override fun onListenerConnected() {
        // Do not backfill notifications posted before the user's opt-in.
        NotificationCaptureEvents.changed()
    }

    override fun onListenerDisconnected() {
        NotificationCaptureEvents.changed()
    }

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        val store = NotificationCaptureStore(this)
        // Deny by default, before reading any notification extras or message text.
        if (!store.accepts(sbn.packageName)) return
        val notification = sbn.notification
        if (sbn.isOngoing || notification.flags and Notification.FLAG_GROUP_SUMMARY != 0) return

        try {
            val extras = notification.extras
            val title = (extras.getCharSequence(Notification.EXTRA_TITLE)
                ?: extras.getCharSequence(Notification.EXTRA_TITLE_BIG))
                ?.toString()?.trim().orEmpty().take(MAX_TITLE_LENGTH)
            val bigText = extras.getCharSequence(Notification.EXTRA_BIG_TEXT)
                ?.toString()?.trim().orEmpty()
            val lines = extras.getCharSequenceArray(Notification.EXTRA_TEXT_LINES)
                ?.map { it.toString().trim() }?.filter(String::isNotEmpty)?.distinct()
                ?.joinToString("\n").orEmpty()
            val text = (bigText.ifEmpty { lines }.ifEmpty {
                extras.getCharSequence(Notification.EXTRA_TEXT)?.toString()?.trim().orEmpty()
            }).take(MAX_TEXT_LENGTH)
            if (title.isEmpty() && text.isEmpty()) return

            val apps = InstalledApps(this)
            // Include the Android notification key so equal text in different messages survives.
            val fingerprint = JSONObject()
                .put("packageName", sbn.packageName)
                .put("key", sbn.key)
                .put("title", title)
                .put("text", text)
                .toString()
            val id = MessageDigest.getInstance("SHA-256")
                .digest(fingerprint.toByteArray(Charsets.UTF_8))
                .joinToString("") { "%02x".format(it.toInt() and 0xff) }
            store.capture(
                JSONObject()
                    .put("id", id)
                    .put("packageName", sbn.packageName)
                    .put("appName", apps.label(sbn.packageName))
                    .put("title", title)
                    .put("text", text)
                    .put("postedAt", sbn.postTime)
                    .put("isEmail", apps.isEmailApp(sbn.packageName)),
            )
        } catch (_: Exception) {
            // Never log notification contents, sender, or package names.
            Log.w("OffersBucket", "Could not capture notification")
        }
    }

    companion object {
        private const val MAX_TITLE_LENGTH = 512
        private const val MAX_TEXT_LENGTH = 8192
    }
}
