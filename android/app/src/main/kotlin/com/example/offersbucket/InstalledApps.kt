package com.example.offersbucket

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri

/** Queries launchable apps and mail handlers, not QUERY_ALL_PACKAGES. */
internal class InstalledApps(private val context: Context) {
    private val packageManager = context.packageManager

    @Suppress("DEPRECATION")
    fun list(): List<Map<String, Any>> {
        val launcher = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        val mail = Intent(Intent.ACTION_SENDTO, Uri.parse("mailto:"))
        val mailPackages = packageManager.queryIntentActivities(mail, 0)
            .map { it.activityInfo.packageName }.toSet()
        return (packageManager.queryIntentActivities(launcher, 0) +
            packageManager.queryIntentActivities(mail, 0))
            .filter { it.activityInfo.enabled && it.activityInfo.applicationInfo.enabled }
            .map { it.activityInfo.packageName }
            .distinct()
            .filter { it != context.packageName }
            .map {
                mapOf(
                    "packageName" to it,
                    "name" to label(it),
                    "isEmailApp" to (mailPackages.contains(it) || EMAIL_PACKAGES.contains(it)),
                )
            }
            .sortedBy { (it["name"] as String).lowercase() }
    }

    @Suppress("DEPRECATION")
    fun label(packageName: String): String = try {
        packageManager.getApplicationLabel(
            packageManager.getApplicationInfo(packageName, 0),
        ).toString()
    } catch (_: PackageManager.NameNotFoundException) {
        packageName
    }

    @Suppress("DEPRECATION")
    fun isEmailApp(packageName: String): Boolean {
        if (EMAIL_PACKAGES.contains(packageName)) return true
        return packageManager.queryIntentActivities(
            Intent(Intent.ACTION_SENDTO, Uri.parse("mailto:")).setPackage(packageName),
            0,
        ).isNotEmpty()
    }

    companion object {
        private val EMAIL_PACKAGES = setOf(
            "com.google.android.gm",
            "com.google.android.gm.lite",
            "com.microsoft.office.outlook",
            "com.yahoo.mobile.client.android.mail",
            "com.samsung.android.email.provider",
            "com.android.email",
            "com.email.android",
            "ch.protonmail.android",
            "com.fsck.k9",
            "net.thunderbird.android",
            "com.fastmail.app",
            "com.easilydo.mail",
            "com.readdle.spark",
            "org.kman.AquaMail",
            "me.bluemail.mail",
        )
    }
}
