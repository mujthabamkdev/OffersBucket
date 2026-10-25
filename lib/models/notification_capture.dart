class InstalledApp {
  const InstalledApp({
    required this.packageName,
    required this.name,
    this.isEmailApp = false,
  });

  final String packageName;
  final String name;
  final bool isEmailApp;

  factory InstalledApp.fromMap(Map<String, Object?> map) => InstalledApp(
    packageName: map['packageName']! as String,
    name: map['name']! as String,
    isEmailApp: map['isEmailApp'] as bool? ?? false,
  );
}

class CapturedNotification {
  const CapturedNotification({
    required this.id,
    required this.packageName,
    required this.appName,
    required this.title,
    required this.text,
    required this.postedAt,
    this.isEmail = false,
  });

  final String id;
  final String packageName;
  final String appName;
  final String title;
  final String text;
  final DateTime postedAt;
  final bool isEmail;

  String get originalMessage => [
    if (title.trim().isNotEmpty) title.trim(),
    if (text.trim().isNotEmpty && text.trim() != title.trim()) text.trim(),
  ].join('\n');

  String get suggestedBrand =>
      isEmail && title.trim().isNotEmpty ? title.trim() : appName;

  String get suggestedTitle {
    final firstLine = text.trim().split('\n').first;
    final value = isEmail && firstLine.isNotEmpty
        ? firstLine
        : title.trim().isNotEmpty
        ? title.trim()
        : firstLine;
    return value.length > 160 ? value.substring(0, 160) : value;
  }

  String get suggestedCode =>
      RegExp(
        r'\b(?:promo\s+|coupon\s+|voucher\s+)?code\s*[:=\-]?\s+([A-Z0-9][A-Z0-9_-]{1,31})\b',
        caseSensitive: false,
      ).firstMatch(originalMessage)?.group(1) ??
      '';

  factory CapturedNotification.fromMap(Map<String, Object?> map) =>
      CapturedNotification(
        id: map['id']! as String,
        packageName: map['packageName']! as String,
        appName: map['appName']! as String,
        title: map['title'] as String? ?? '',
        text: map['text'] as String? ?? '',
        postedAt: DateTime.fromMillisecondsSinceEpoch(
          (map['postedAt']! as num).toInt(),
        ),
        isEmail: map['isEmail'] as bool? ?? false,
      );
}

class NotificationCaptureState {
  const NotificationCaptureState({
    this.isSupported = false,
    this.hasAccess = false,
    this.isEnabled = false,
    this.allowedPackages = const {},
    this.notifications = const [],
  });

  final bool isSupported;
  final bool hasAccess;
  final bool isEnabled;
  final Set<String> allowedPackages;
  final List<CapturedNotification> notifications;

  bool get isActive =>
      isSupported && hasAccess && isEnabled && allowedPackages.isNotEmpty;

  factory NotificationCaptureState.fromMap(Map<String, Object?> map) {
    final allowedPackages = Set<String>.unmodifiable(
      (map['allowedPackages'] as List<Object?>? ?? const []).cast<String>(),
    );
    final notifications =
        (map['notifications'] as List<Object?>? ?? const [])
            .map(
              (item) => CapturedNotification.fromMap(
                Map<String, Object?>.from(item! as Map),
              ),
            )
            .where((item) => allowedPackages.contains(item.packageName))
            .toList()
          ..sort((first, second) => second.postedAt.compareTo(first.postedAt));

    return NotificationCaptureState(
      isSupported: map['isSupported'] as bool? ?? false,
      hasAccess: map['hasAccess'] as bool? ?? false,
      isEnabled: map['isEnabled'] as bool? ?? false,
      allowedPackages: allowedPackages,
      notifications: List.unmodifiable(notifications),
    );
  }
}
