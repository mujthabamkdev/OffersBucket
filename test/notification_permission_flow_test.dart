import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:offersbucket/data/offer_repository.dart';
import 'package:offersbucket/main.dart';
import 'package:offersbucket/models/notification_capture.dart';
import 'package:offersbucket/notification_capture_page.dart';
import 'package:offersbucket/services/notification_capture_controller.dart';
import 'package:offersbucket/services/notification_capture_service.dart';

class _MissingPermissionService implements NotificationCaptureService {
  int openSettingsCalls = 0;

  @override
  bool get isSupported => true;

  @override
  Stream<void> get changes => const Stream<void>.empty();

  @override
  Future<NotificationCaptureState> getState() async =>
      const NotificationCaptureState(isSupported: true);

  @override
  Future<List<InstalledApp>> getInstalledApps() async => const [];

  @override
  Future<void> setEnabled(bool enabled) async {}

  @override
  Future<void> setAllowedApps(Set<String> packageNames) async {}

  @override
  Future<void> openAccessSettings() async => openSettingsCalls++;

  @override
  Future<void> deleteNotification(String id) async {}

  @override
  Future<void> clearNotifications() async {}
}

void main() {
  testWidgets('warns when notification access is missing', (tester) async {
    await tester.pumpWidget(
      MyApp(
        repository: OfferRepository(initialOffers: const []),
        notificationCaptureService: _MissingPermissionService(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Notification access not granted'), findsOneWidget);
    expect(find.text('Use custom coupons'), findsOneWidget);
    expect(find.text('Grant permission'), findsOneWidget);
  });

  testWidgets('grant access opens Android notification settings', (
    tester,
  ) async {
    final service = _MissingPermissionService();
    final controller = NotificationCaptureController(service);

    await tester.pumpWidget(
      MaterialApp(
        home: NotificationCapturePage(
          controller: controller,
          onReview: (_) async => false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Grant access'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open Android settings'));
    await tester.pumpAndSettle();

    expect(service.openSettingsCalls, 1);
  });
}
