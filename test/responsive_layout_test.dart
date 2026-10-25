import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offersbucket/data/offer_repository.dart';
import 'package:offersbucket/main.dart';
import 'package:offersbucket/models/notification_capture.dart';
import 'package:offersbucket/models/offer.dart';
import 'package:offersbucket/models/web_coupon_deal.dart';
import 'package:offersbucket/notification_capture_page.dart';
import 'package:offersbucket/services/notification_capture_controller.dart';
import 'package:offersbucket/services/notification_capture_service.dart';
import 'package:offersbucket/services/web_coupon_search_service.dart';
import 'package:offersbucket/theme/app_theme.dart';
import 'package:offersbucket/widgets/app_layout.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _longCode = 'RUN25_MEMBERS_ONLY_EXTRA_LONG_COUPON_CODE_2026';
const _originalMessage =
    'Member offer: save on selected items.\n'
    'Use your coupon at checkout. Terms and exclusions apply.';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final loader = FontLoader(AppTheme.fontFamily);
    for (final weight in [
      'Light',
      'Regular',
      'Medium',
      'SemiBold',
      'Bold',
      'ExtraBold',
    ]) {
      loader.addFont(rootBundle.load('assets/fonts/Manrope-$weight.ttf'));
    }
    await loader.load();
    final icons = FontLoader('MaterialIcons');
    icons.addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });

  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final width in [320.0, 390.0, 800.0, 1440.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('all tabs fit at ${width}px with ${scale}x text', (
        tester,
      ) async {
        _setViewport(tester, width, scale);
        final offers = _offers();
        final repository = OfferRepository(
          initialOffers: [
            ...offers,
            for (final offer in offers.take(2))
              offer.copyWith(id: 'archived-${offer.id}', isArchived: true),
          ],
        );
        await tester.pumpWidget(
          MyApp(
            repository: repository,
            webCouponSearchService: _DealsService(),
            notificationCaptureService: _CaptureService(supported: false),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          Theme.of(
            tester.element(find.byType(HomePage)),
          ).chipTheme.labelStyle?.fontFamily,
          AppTheme.fontFamily,
        );
        _expectTwoColumnGrid(tester, 3);
        expect(tester.takeException(), isNull);

        final choiceChips = find.byType(ChoiceChip);
        expect(choiceChips, findsWidgets);
        final chipTop = tester.getTopLeft(choiceChips.first).dy;
        final chipCount = choiceChips.evaluate().length;
        for (var i = 1; i < chipCount; i++) {
          expect(
            tester.getTopLeft(choiceChips.at(i)).dy,
            closeTo(chipTop, 1),
            reason: 'Category filters must stay on one scrollable line.',
          );
        }

        final gridCardSize = tester.getSize(find.byType(OfferCard).first);
        for (final offer in offers.where(
          (offer) => offer.description.isNotEmpty,
        )) {
          expect(find.text(offer.description), findsNothing);
        }
        await _tapVisible(
          tester,
          find.descendant(
            of: find.byType(SegmentedButton<bool>),
            matching: find.byIcon(Icons.view_list_outlined),
          ),
        );
        final listCards = find.byType(OfferCard);
        expect(listCards, findsNWidgets(3));
        final listCardSize = tester.getSize(listCards.first);
        expect(listCardSize.width, greaterThan(gridCardSize.width));
        expect(listCardSize.height, greaterThan(gridCardSize.height));
        if (width >= 800) {
          expect(listCardSize.width, greaterThan(AppLayout.maxCardWidth));
        }
        for (var index = 0; index < 3; index++) {
          expect(
            tester.widget<OfferCard>(listCards.at(index)).minimal,
            isFalse,
          );
          expect(tester.getSize(listCards.at(index)), listCardSize);
          if (index > 0) {
            expect(
              tester.getRect(listCards.at(index)).top,
              greaterThan(tester.getRect(listCards.at(index - 1)).bottom),
            );
          }
        }
        for (final offer in offers.where(
          (offer) => offer.description.isNotEmpty,
        )) {
          expect(find.text(offer.description), findsOneWidget);
        }
        await _tapVisible(
          tester,
          find.descendant(
            of: find.byType(SegmentedButton<bool>),
            matching: find.byIcon(Icons.grid_view_outlined),
          ),
        );
        _expectTwoColumnGrid(tester, 3);
        expect(tester.takeException(), isNull);

        await _openTab(tester, 'Explore');
        expect(
          tester.getTopLeft(find.text('Explore web deals')).dy,
          closeTo(24, 1),
        );
        await tester.enterText(find.byType(TextField), 'shoes');
        await tester.tap(find.widgetWithIcon(IconButton, Icons.search));
        await tester.pumpAndSettle();
        final dealSizes = [
          for (final deal in _deals)
            tester.getSize(find.widgetWithText(Card, deal.title)),
        ];
        expect(dealSizes[0], dealSizes[1]);
        expect(dealSizes[0].width, lessThanOrEqualTo(AppLayout.maxCardWidth));
        expect(tester.takeException(), isNull);

        await _openTab(tester, 'Add offer');
        await _fillField(tester, 'Brand', 'Test brand');
        await _fillField(tester, 'Offer title', 'A saved member offer');
        final category = find.byType(DropdownButtonFormField<String>);
        await _tapVisible(tester, category);
        await _tapVisible(tester, find.text('Entertainment').last);
        final categoryLabel = tester.renderObject<RenderParagraph>(
          find.descendant(of: category, matching: find.text('Entertainment')),
        );
        expect(categoryLabel.didExceedMaxLines, isFalse);
        expect(
          categoryLabel.computeMaxIntrinsicHeight(categoryLabel.size.width),
          lessThanOrEqualTo(categoryLabel.size.height + .5),
          reason: 'Selected category must remain fully readable.',
        );
        await _fillField(tester, 'Description', 'First line\nSecond line');
        await _fillField(tester, 'Original message', _originalMessage);
        await _fillField(tester, 'Promo code', _longCode);
        expect(tester.takeException(), isNull);
        await _tapVisible(tester, find.text('Save offer'));
        final saved = repository.search('A saved member offer').single;
        expect(saved.code, _longCode);
        expect(saved.originalMessage, _originalMessage);
        expect(saved.category, 'Entertainment');
        _expectTwoColumnGrid(tester, 4);
        expect(tester.takeException(), isNull);

        await _openTab(tester, 'Archive');
        final archiveHeading = find.descendant(
          of: find.byType(ArchivePage),
          matching: find.text('Archive'),
        );
        expect(tester.getTopLeft(archiveHeading).dy, closeTo(24, 1));
        _expectUniformCards(tester, 2);
        expect(tester.takeException(), isNull);

        await _openTab(tester, 'Settings');
        await _tapVisible(tester, find.text('Open'));
        tester.view.viewInsets = const FakeViewPadding(bottom: 260);
        await tester.pumpAndSettle();
        await _fillField(tester, 'Email', 'member@example.com');
        await _fillField(tester, 'Password', 'readable-password');
        expect(find.text('member@example.com'), findsOneWidget);
        expect(
          tester.getRect(find.byType(Dialog)).center.dx,
          closeTo(width / 2, 1),
        );
        await _tapVisible(tester, find.text('Create account'));
        expect(find.text('Create your account'), findsOneWidget);
        expect(tester.takeException(), isNull);
        final closeAccount = find.widgetWithIcon(IconButton, Icons.close);
        await _tapVisible(tester, closeAccount);
        tester.view.resetViewInsets();
        await tester.pumpAndSettle();
        expect(find.byType(Dialog), findsNothing);

        await _tapVisible(tester, find.text('Grant again'));
        final unsupported = find.textContaining(
          'Automatic notification capture is available on Android only.',
        );
        expect(unsupported, findsOneWidget);
        expect(tester.getTopLeft(unsupported).dy, lessThan(130));
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final compact in [false, true]) {
    for (final minimal in [false, true]) {
      testWidgets(
        'card actions work with compact=$compact / minimal=$minimal',
        (tester) async {
          _setViewport(tester, 320, 2);
          String? copiedCode;
          var openedDetails = false;
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            (call) async {
              if (call.method == 'Clipboard.setData') {
                copiedCode = (call.arguments as Map)['text'] as String;
              }
              return null;
            },
          );
          addTearDown(
            () => tester.binding.defaultBinaryMessenger
                .setMockMethodCallHandler(SystemChannels.platform, null),
          );
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.light,
              home: Scaffold(
                body: AppPageScroll(
                  child: AppCardGrid(
                    columns: minimal ? 2 : null,
                    children: [
                      for (final offer in _offers())
                        OfferCard(
                          offer: offer,
                          onTap: () => openedDetails = true,
                          compact: compact,
                          minimal: minimal,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          _expectUniformCards(tester, 3);
          await _tapVisible(tester, find.text(_longCode));
          expect(copiedCode, _longCode);
          expect(openedDetails, isFalse);
          await _tapVisible(tester, find.text(_offers().first.title));
          expect(openedDetails, isTrue);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  for (final width in [320.0, 1440.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('capture list and inbox fit at ${width}px / ${scale}x', (
        tester,
      ) async {
        _setViewport(tester, width, scale);
        final service = _CaptureService();
        final controller = NotificationCaptureController(service);
        addTearDown(controller.dispose);
        await controller.initialize();
        var saveReview = false;
        final reviewed = <String>[];
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            home: NotificationCapturePage(
              controller: controller,
              onReview: (notification) async {
                reviewed.add(notification.id);
                return saveReview;
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final search = find.byType(TextField);
        await _scrollCaptureTo(tester, search);
        await tester.enterText(search, 'gmail');
        await tester.pumpAndSettle();
        final allowedApp = find.byKey(
          const ValueKey('allow-com.google.android.gm'),
        );
        await _scrollCaptureTo(tester, allowedApp);
        expect(tester.widget<SwitchListTile>(allowedApp).value, isTrue);
        expect(find.text('Another app with a long display name'), findsNothing);
        expect(tester.takeException(), isNull);

        await _scrollCaptureTo(
          tester,
          find.text(width == 320 || scale > 1 ? 'Inbox' : 'Messages'),
          delta: -200,
        );
        await tester.tap(
          find.text(width == 320 || scale > 1 ? 'Inbox' : 'Messages'),
        );
        await tester.pumpAndSettle();
        final reviewButton = find.descendant(
          of: find.byKey(const ValueKey('capture-1')),
          matching: find.text('Review & save offer'),
        );
        await _scrollCaptureTo(tester, reviewButton);
        await tester.tap(reviewButton);
        await tester.pumpAndSettle();
        expect(reviewed, ['capture-1']);
        expect(service.deleted, isEmpty);
        saveReview = true;
        await tester.tap(reviewButton);
        await tester.pumpAndSettle();
        expect(service.deleted, ['capture-1']);
        expect(find.text('Offer saved'), findsOneWidget);
        expect(tester.takeException(), isNull);

        await _scrollCaptureTo(
          tester,
          find.text('Clear captures'),
          delta: -200,
        );
        await tester.tap(find.text('Clear captures'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(service.clearCalls, 0);
        await tester.tap(find.text('Clear captures'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Delete captures'));
        await tester.pumpAndSettle();
        expect(service.clearCalls, 1);
        expect(
          find.textContaining('No captured messages yet.'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      });
    }
  }
}

void _setViewport(WidgetTester tester, double width, double scale) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, width < 600 ? 844 : 1000);
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetViewInsets);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

Future<void> _openTab(WidgetTester tester, String label) async {
  await tester.tap(
    find.descendant(of: find.byType(NavigationBar), matching: find.text(label)),
  );
  await tester.pumpAndSettle();
}

Future<void> _scrollCaptureTo(
  WidgetTester tester,
  Finder target, {
  double delta = 200,
}) async {
  await tester.scrollUntilVisible(
    target,
    delta,
    scrollable: find
        .descendant(
          of: find.byType(CustomScrollView),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.pumpAndSettle();
}

Future<void> _tapVisible(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> _fillField(WidgetTester tester, String label, String value) async {
  final field = find.byWidgetPredicate(
    (widget) => widget is TextField && widget.decoration?.labelText == label,
  );
  await tester.ensureVisible(field);
  await tester.enterText(field, value);
  await tester.pumpAndSettle();
}

void _expectUniformCards(WidgetTester tester, int count) {
  final cards = find.byType(OfferCard);
  expect(cards, findsNWidgets(count));
  final size = tester.getSize(cards.first);
  expect(size.width, lessThanOrEqualTo(AppLayout.maxCardWidth));
  for (var i = 1; i < count; i++) {
    expect(tester.getSize(cards.at(i)), size);
  }
}

void _expectTwoColumnGrid(WidgetTester tester, int count) {
  _expectUniformCards(tester, count);
  final cards = find.byType(OfferCard);
  for (var index = 0; index < count; index++) {
    expect(tester.widget<OfferCard>(cards.at(index)).minimal, isTrue);
  }
  final first = tester.getRect(cards.first);
  for (var index = 0; index < count; index += 2) {
    final left = tester.getRect(cards.at(index));
    expect(left.left, closeTo(first.left, 1));
    if (index > 0) {
      expect(left.top, greaterThan(tester.getRect(cards.at(index - 2)).bottom));
    }
    if (index + 1 < count) {
      final right = tester.getRect(cards.at(index + 1));
      expect(right.top, closeTo(left.top, 1));
      expect(right.left, greaterThan(left.right));
    }
  }
}

List<Offer> _offers() {
  final samples = buildSampleOffers();
  return [
    samples[0].copyWith(
      brand: 'A brand with a much longer display name',
      title: 'Save on running shoes and accessories from the new season',
      code: _longCode,
      originalMessage: _originalMessage,
    ),
    samples[1],
    samples[2].copyWith(title: 'Deal', description: '', code: ''),
  ];
}

const _deals = [
  WebCouponDeal(
    title: 'Running shoes and accessories with a much longer deal title',
    merchant: 'A merchant with a long display name',
    category: 'Fashion',
    url: 'https://example.com/deal',
    price: '₹12,345.00',
    discount: '25%',
    description: 'Selected items only. Terms apply.',
    updatedAt: null,
  ),
  WebCouponDeal(
    title: 'Short deal',
    merchant: 'Store',
    category: 'Shopping',
    url: 'https://example.com/other',
    price: '',
    discount: '',
    description: '',
    updatedAt: null,
  ),
];

class _DealsService implements WebCouponSearchService {
  @override
  Future<List<WebCouponDeal>> search(String query) async => _deals;
}

class _CaptureService implements NotificationCaptureService {
  _CaptureService({this.supported = true});

  final bool supported;
  final deleted = <String>[];
  int clearCalls = 0;
  var notifications = [
    CapturedNotification(
      id: 'capture-1',
      packageName: 'com.google.android.gm',
      appName: 'Gmail with a long account display name',
      title: 'Member offer with a longer notification title',
      text: _originalMessage,
      postedAt: DateTime(2026, 10, 24),
      isEmail: true,
    ),
    CapturedNotification(
      id: 'capture-2',
      packageName: 'com.google.android.gm',
      appName: 'Gmail',
      title: 'Another offer',
      text: 'Use code NEXT25 at checkout.',
      postedAt: DateTime(2026, 10, 23),
      isEmail: true,
    ),
  ];

  @override
  bool get isSupported => supported;

  @override
  Stream<void> get changes => const Stream.empty();

  @override
  Future<NotificationCaptureState> getState() async => NotificationCaptureState(
    isSupported: supported,
    hasAccess: true,
    isEnabled: true,
    allowedPackages: const {'com.google.android.gm'},
    notifications: notifications,
  );

  @override
  Future<List<InstalledApp>> getInstalledApps() async => const [
    InstalledApp(
      packageName: 'com.google.android.gm',
      name: 'Gmail',
      isEmailApp: true,
    ),
    InstalledApp(
      packageName: 'com.example.a.very.long.package.name',
      name: 'Another app with a long display name',
    ),
  ];

  @override
  Future<void> setEnabled(bool enabled) async {}

  @override
  Future<void> setAllowedApps(Set<String> packageNames) async {}

  @override
  Future<void> openAccessSettings() async {}

  @override
  Future<void> deleteNotification(String id) async {
    deleted.add(id);
    notifications = notifications.where((item) => item.id != id).toList();
  }

  @override
  Future<void> clearNotifications() async {
    clearCalls++;
    notifications = [];
  }
}
