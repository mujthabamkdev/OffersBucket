package com.example.offersbucket

import android.app.NotificationManager
import android.content.ActivityNotFoundException
import android.content.ComponentName
import android.content.Intent
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var methods: MethodChannel? = null
    private var events: EventChannel? = null
    private var eventSink: EventChannel.EventSink? = null
    private val onCaptureChanged: () -> Unit = { eventSink?.success(null) }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        methods = MethodChannel(messenger, "offersbucket/notification_capture").also {
            it.setMethodCallHandler(::handleCaptureCall)
        }
        events = EventChannel(messenger, "offersbucket/notification_capture/events").also {
            it.setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, sink: EventChannel.EventSink) {
                    eventSink = sink
                    NotificationCaptureEvents.add(onCaptureChanged)
                }

                override fun onCancel(arguments: Any?) {
                    NotificationCaptureEvents.remove(onCaptureChanged)
                    eventSink = null
                }
            })
        }
    }

    override fun onResume() {
        super.onResume()
        NotificationCaptureEvents.changed()
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        NotificationCaptureEvents.remove(onCaptureChanged)
        eventSink = null
        methods?.setMethodCallHandler(null)
        events?.setStreamHandler(null)
        methods = null
        events = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    private fun handleCaptureCall(call: MethodCall, result: MethodChannel.Result) {
        val store = NotificationCaptureStore(this)
        try {
            when (call.method) {
                "getState" -> result.success(
                    mapOf(
                        "isSupported" to true,
                        "hasAccess" to hasNotificationAccess(),
                        "isEnabled" to store.isEnabled(),
                        "allowedPackages" to store.allowedPackages().sorted(),
                        "notifications" to store.notifications(),
                    ),
                )
                "getInstalledApps" -> {
                    val apps = InstalledApps(this).list()
                    val installed = apps.map { it["packageName"] as String }.toSet()
                    val allowed = store.allowedPackages()
                    if (!installed.containsAll(allowed)) {
                        store.setAllowedPackages(allowed.intersect(installed))
                    }
                    result.success(apps)
                }
                "setEnabled" -> {
                    val enabled = call.argument<Boolean>("enabled")
                    if (enabled == null) {
                        result.error("invalid_arguments", "An enabled flag is required", null)
                        return
                    }
                    if (enabled && !hasNotificationAccess()) {
                        result.error(
                            "notification_access_required",
                            "Grant notification access in Android settings first",
                            null,
                        )
                        return
                    }
                    store.setEnabled(enabled)
                    result.success(null)
                }
                "setAllowedApps" -> {
                    val packages = call.argument<List<String>>("packageNames")
                    if (packages == null) {
                        result.error("invalid_arguments", "Package names are required", null)
                        return
                    }
                    val installed = InstalledApps(this).list()
                        .map { it["packageName"] as String }.toSet()
                    if (!installed.containsAll(packages)) {
                        result.error("invalid_arguments", "Only installed apps can be allowed", null)
                        return
                    }
                    store.setAllowedPackages(packages.toSet())
                    result.success(null)
                }
                "openAccessSettings" -> {
                    openNotificationAccessSettings()
                    result.success(null)
                }
                "deleteNotification" -> {
                    val id = call.argument<String>("id")
                    if (id == null) {
                        result.error("invalid_arguments", "A capture ID is required", null)
                        return
                    }
                    store.deleteNotification(id)
                    result.success(null)
                }
                "clearNotifications" -> {
                    store.clearNotifications()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        } catch (_: Exception) {
            result.error("capture_unavailable", "Could not access notification capture", null)
        }
    }

    private fun hasNotificationAccess(): Boolean {
        val component = ComponentName(this, OfferNotificationListenerService::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            return getSystemService(NotificationManager::class.java)
                .isNotificationListenerAccessGranted(component)
        }
        return Settings.Secure.getString(contentResolver, "enabled_notification_listeners")
            ?.split(':')?.any { ComponentName.unflattenFromString(it) == component } == true
    }

    private fun openNotificationAccessSettings() {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                startActivity(
                    Intent(Settings.ACTION_NOTIFICATION_LISTENER_DETAIL_SETTINGS).putExtra(
                        Settings.EXTRA_NOTIFICATION_LISTENER_COMPONENT_NAME,
                        ComponentName(this, OfferNotificationListenerService::class.java)
                            .flattenToString(),
                    ),
                )
            } else {
                startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
            }
        } catch (_: ActivityNotFoundException) {
            startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
        }
    }
}
