import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/notification_capture.dart';

abstract interface class NotificationCaptureService {
  bool get isSupported;

  Stream<void> get changes;

  Future<NotificationCaptureState> getState();

  Future<List<InstalledApp>> getInstalledApps();

  Future<void> setEnabled(bool enabled);

  Future<void> setAllowedApps(Set<String> packageNames);

  Future<void> openAccessSettings();

  Future<void> deleteNotification(String id);

  Future<void> clearNotifications();
}

class PlatformNotificationCaptureService implements NotificationCaptureService {
  static const _methods = MethodChannel('offersbucket/notification_capture');
  static const _events = EventChannel(
    'offersbucket/notification_capture/events',
  );

  @override
  bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  Stream<void> get changes => isSupported
      ? _events.receiveBroadcastStream().map<void>((_) {})
      : const Stream.empty();

  @override
  Future<NotificationCaptureState> getState() async {
    if (!isSupported) return const NotificationCaptureState();
    final map = await _methods.invokeMapMethod<String, Object?>('getState');
    if (map == null) throw const FormatException('Missing capture state');
    return NotificationCaptureState.fromMap(map);
  }

  @override
  Future<List<InstalledApp>> getInstalledApps() async {
    if (!isSupported) return const [];
    final apps = await _methods.invokeListMethod<Object?>('getInstalledApps');
    return List.unmodifiable(
      (apps ?? const []).map(
        (item) => InstalledApp.fromMap(Map<String, Object?>.from(item! as Map)),
      ),
    );
  }

  @override
  Future<void> setEnabled(bool enabled) =>
      _invoke('setEnabled', {'enabled': enabled});

  @override
  Future<void> setAllowedApps(Set<String> packageNames) => _invoke(
    'setAllowedApps',
    {'packageNames': packageNames.toList()..sort()},
  );

  @override
  Future<void> openAccessSettings() => _invoke('openAccessSettings');

  @override
  Future<void> deleteNotification(String id) =>
      _invoke('deleteNotification', {'id': id});

  @override
  Future<void> clearNotifications() => _invoke('clearNotifications');

  Future<void> _invoke(String method, [Map<String, Object?>? arguments]) async {
    if (!isSupported) return;
    await _methods.invokeMethod<void>(method, arguments);
  }
}
