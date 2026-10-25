import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/notification_capture.dart';
import 'notification_capture_service.dart';

class NotificationCaptureController extends ChangeNotifier {
  NotificationCaptureController(this._service)
    : state = NotificationCaptureState(isSupported: _service.isSupported);

  final NotificationCaptureService _service;
  NotificationCaptureState state;
  List<InstalledApp> installedApps = const [];
  bool isLoading = false;
  bool isSaving = false;
  String? error;

  StreamSubscription<void>? _subscription;
  Future<void>? _refreshFuture;
  bool _refreshRequested = false;
  bool _reloadAppsRequested = false;
  bool _disposed = false;

  Future<void> initialize() async {
    if (!_service.isSupported) return;
    _subscription = _service.changes.listen(
      (_) => unawaited(refresh(reloadApps: false)),
      onError: (Object _) {
        error = 'Live updates are unavailable. Refresh to load new captures.';
        _notify();
      },
    );
    await refresh();
  }

  Future<void> refresh({bool reloadApps = true}) {
    if (_disposed || !_service.isSupported) return Future.value();
    _refreshRequested = true;
    _reloadAppsRequested |= reloadApps;
    return _refreshFuture ??= _refreshLoop().whenComplete(() {
      _refreshFuture = null;
    });
  }

  Future<void> _refreshLoop() async {
    isLoading = true;
    _notify();
    try {
      while (_refreshRequested && !_disposed) {
        _refreshRequested = false;
        final reloadApps = _reloadAppsRequested;
        _reloadAppsRequested = false;
        final results = await Future.wait<Object>([
          _service.getState(),
          if (reloadApps) _service.getInstalledApps(),
        ]);
        if (_disposed) return;
        state = results[0] as NotificationCaptureState;
        if (reloadApps) {
          installedApps = List.unmodifiable(results[1] as List<InstalledApp>);
        }
        error = null;
      }
    } on MissingPluginException {
      state = const NotificationCaptureState();
      error = 'Notification capture is unavailable in this build.';
    } catch (_) {
      error = 'Could not load notification capture. Try refreshing.';
    } finally {
      isLoading = false;
      _notify();
    }
  }

  Future<bool> setAppAllowed(InstalledApp app, bool allowed) {
    final packages = {...state.allowedPackages};
    if (allowed) {
      packages.add(app.packageName);
    } else {
      packages.remove(app.packageName);
    }
    return _mutate(() => _service.setAllowedApps(packages));
  }

  Future<bool> setEnabled(bool enabled) =>
      _mutate(() => _service.setEnabled(enabled));

  Future<bool> openAccessSettings() => _mutate(_service.openAccessSettings);

  Future<bool> deleteNotification(String id) =>
      _mutate(() => _service.deleteNotification(id));

  Future<bool> clearNotifications() => _mutate(_service.clearNotifications);

  Future<bool> _mutate(Future<void> Function() action) async {
    if (isSaving || _disposed || !state.isSupported) return false;
    isSaving = true;
    error = null;
    _notify();
    try {
      await action();
      await refresh(reloadApps: false);
      return error == null;
    } on PlatformException catch (exception) {
      error = exception.code == 'notification_access_required'
          ? 'Grant Android notification access before enabling capture.'
          : 'Could not update notification capture. Try again.';
      return false;
    } catch (_) {
      error = 'Could not update notification capture. Try again.';
      return false;
    } finally {
      isSaving = false;
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_subscription?.cancel());
    super.dispose();
  }
}
