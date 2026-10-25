import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../models/offer.dart';

class ExpiryReminderService {
  static const _channelId = 'offersbucket_expiry_reminders';
  static const _channelName = 'Expiry reminders';
  static const _channelDescription = 'Reminders for coupons expiring soon.';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized || kIsWeb) return;
    tz.initializeTimeZones();
    try {
      final localTimezone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(localTimezone.identifier));
    } catch (_) {
      // Keep package default timezone if native timezone lookup is unavailable.
    }

    final settings = InitializationSettings(
      android: const AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: const DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
      macOS: const DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    );
    try {
      await _plugin.initialize(settings: settings);
      _initialized = true;
      await _createAndroidChannel();
    } catch (_) {
      // Reminder support stays unavailable instead of blocking app startup.
    }
  }

  Future<bool> requestPermission() async {
    if (!_initialized) return false;
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        return await _plugin
                .resolvePlatformSpecificImplementation<
                  AndroidFlutterLocalNotificationsPlugin
                >()
                ?.requestNotificationsPermission() ??
            false;
      }
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        return await _plugin
                .resolvePlatformSpecificImplementation<
                  IOSFlutterLocalNotificationsPlugin
                >()
                ?.requestPermissions(alert: true, badge: true, sound: true) ??
            false;
      }
      if (defaultTargetPlatform == TargetPlatform.macOS) {
        return await _plugin
                .resolvePlatformSpecificImplementation<
                  MacOSFlutterLocalNotificationsPlugin
                >()
                ?.requestPermissions(alert: true, badge: true, sound: true) ??
            false;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> sync(
    Iterable<Offer> offers, {
    required bool enabled,
    bool requestPermission = false,
  }) async {
    if (!_initialized) return;
    try {
      if (!enabled) {
        await _plugin.cancelAllPendingNotifications();
        return;
      }
      if (requestPermission && !await this.requestPermission()) {
        await _plugin.cancelAllPendingNotifications();
        return;
      }

      await _plugin.cancelAllPendingNotifications();
      final now = tz.TZDateTime.now(tz.local);
      for (final offer in offers) {
        if (offer.isArchived || !offer.validUntil.isAfter(DateTime.now())) {
          continue;
        }
        var reminderAt = tz.TZDateTime.from(
          offer.validUntil.subtract(const Duration(days: 1)),
          tz.local,
        );
        if (!reminderAt.isAfter(now)) {
          reminderAt = now.add(const Duration(minutes: 1));
        }
        await _plugin.zonedSchedule(
          id: _notificationId(offer.id),
          title: 'Coupon expires soon',
          body: '${offer.brand}: ${offer.title}',
          scheduledDate: reminderAt,
          notificationDetails: const NotificationDetails(
            android: AndroidNotificationDetails(
              _channelId,
              _channelName,
              channelDescription: _channelDescription,
              importance: Importance.defaultImportance,
              priority: Priority.defaultPriority,
            ),
            iOS: DarwinNotificationDetails(),
            macOS: DarwinNotificationDetails(),
          ),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          payload: offer.id,
        );
      }
    } catch (_) {
      // A device notification policy must not prevent coupon saving.
    }
  }

  Future<void> _createAndroidChannel() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await android?.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: _channelDescription,
        importance: Importance.defaultImportance,
      ),
    );
  }

  int _notificationId(String offerId) =>
      (offerId.codeUnits.fold<int>(17, (hash, code) => hash * 31 + code) &
          0x7fffffff) |
      1;
}
