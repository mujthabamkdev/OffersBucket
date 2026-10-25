package com.example.offersbucket

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.io.IOException

/** Native storage keeps capturing even when no Flutter engine is running. */
internal class NotificationCaptureStore(context: Context) {
    private val preferences = context.applicationContext.getSharedPreferences(
        "offersbucket.notification_capture.v1",
        Context.MODE_PRIVATE,
    )

    fun isEnabled(): Boolean = synchronized(lock) {
        preferences.getBoolean("enabled", false)
    }

    fun allowedPackages(): Set<String> = synchronized(lock) {
        preferences.getStringSet("allowed_packages", emptySet())!!.toSet()
    }

    fun accepts(packageName: String): Boolean = synchronized(lock) {
        packageName != ownPackage && isEnabled() && allowedPackages().contains(packageName)
    }

    private val ownPackage = context.packageName

    fun setEnabled(enabled: Boolean) = synchronized(lock) {
        persist(preferences.edit().putBoolean("enabled", enabled).commit())
        NotificationCaptureEvents.changed()
    }

    fun setAllowedPackages(packages: Set<String>) = synchronized(lock) {
        val allowed = packages.filter { it.isNotBlank() && it != ownPackage }.toSet()
        val retained = readArray("notifications").objects()
            .filter { allowed.contains(it.optString("packageName")) }
        persist(
            preferences.edit()
                .putStringSet("allowed_packages", allowed)
                .putString("notifications", JSONArray(retained).toString())
                .commit(),
        )
        NotificationCaptureEvents.changed()
    }

    fun notifications(): List<Map<String, Any>> = synchronized(lock) {
        val allowed = allowedPackages()
        readArray("notifications").objects()
            .filter { allowed.contains(it.optString("packageName")) }
            .map {
                mapOf(
                    "id" to it.getString("id"),
                    "packageName" to it.getString("packageName"),
                    "appName" to it.getString("appName"),
                    "title" to it.optString("title"),
                    "text" to it.optString("text"),
                    "postedAt" to it.getLong("postedAt"),
                    "isEmail" to it.optBoolean("isEmail"),
                )
            }
    }

    fun capture(notification: JSONObject): Boolean = synchronized(lock) {
        // Recheck at the persistence boundary in case the allowlist was changed.
        if (!accepts(notification.getString("packageName"))) return@synchronized false
        val id = notification.getString("id")
        val seen = readArray("seen_ids").strings()
        if (seen.contains(id)) return@synchronized false

        val captures = (readArray("notifications").objects() + notification)
            .takeLast(MAX_CAPTURES)
        persist(
            preferences.edit()
                .putString("notifications", JSONArray(captures).toString())
                .putString("seen_ids", JSONArray((seen + id).takeLast(MAX_SEEN_IDS)).toString())
                .commit(),
        )
        NotificationCaptureEvents.changed()
        true
    }

    fun deleteNotification(id: String) = synchronized(lock) {
        val retained = readArray("notifications").objects().filter { it.optString("id") != id }
        persist(preferences.edit().putString("notifications", JSONArray(retained).toString()).commit())
        NotificationCaptureEvents.changed()
    }

    fun clearNotifications() = synchronized(lock) {
        // Keep bounded fingerprints so an unchanged notification does not reappear.
        persist(preferences.edit().putString("notifications", "[]").commit())
        NotificationCaptureEvents.changed()
    }

    private fun readArray(key: String): JSONArray = try {
        JSONArray(preferences.getString(key, "[]") ?: "[]")
    } catch (_: org.json.JSONException) {
        JSONArray()
    }

    private fun JSONArray.objects(): List<JSONObject> =
        (0 until length()).mapNotNull { optJSONObject(it) }

    private fun JSONArray.strings(): List<String> =
        (0 until length()).mapNotNull { optString(it).takeIf(String::isNotEmpty) }

    private fun persist(success: Boolean) {
        if (!success) throw IOException("Could not persist notification capture settings")
    }

    companion object {
        private val lock = Any()
        const val MAX_CAPTURES = 200
        private const val MAX_SEEN_IDS = 500
    }
}
