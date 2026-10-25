import 'package:flutter_test/flutter_test.dart';
import 'package:offersbucket/models/notification_capture.dart';

void main() {
  test('extracts useful offer suggestions from captured email text', () {
    final notification = CapturedNotification.fromMap({
      'id': 'capture-1',
      'packageName': 'com.google.android.gm',
      'appName': 'Gmail',
      'title': 'Nike member offer',
      'text': 'Save 25% today. Use code RUN25 at checkout.',
      'postedAt': 1,
      'isEmail': true,
    });

    expect(notification.suggestedBrand, 'Nike member offer');
    expect(
      notification.suggestedTitle,
      'Save 25% today. Use code RUN25 at checkout.',
    );
    expect(notification.suggestedCode, 'RUN25');
    expect(notification.originalMessage, contains('Nike member offer'));
  });

  test('capture state only exposes notifications from allowed apps', () {
    final state = NotificationCaptureState.fromMap({
      'isSupported': true,
      'hasAccess': true,
      'isEnabled': true,
      'allowedPackages': ['com.google.android.gm'],
      'notifications': [
        {
          'id': 'allowed',
          'packageName': 'com.google.android.gm',
          'appName': 'Gmail',
          'title': 'Allowed',
          'text': 'Offer',
          'postedAt': 2,
        },
        {
          'id': 'blocked',
          'packageName': 'com.example.other',
          'appName': 'Other',
          'title': 'Blocked',
          'text': 'Should not appear',
          'postedAt': 3,
        },
      ],
    });

    expect(state.isActive, isTrue);
    expect(state.notifications.map((item) => item.id), ['allowed']);
  });
}
