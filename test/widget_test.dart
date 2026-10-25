import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:offersbucket/data/offer_repository.dart';
import 'package:offersbucket/main.dart';
import 'package:offersbucket/models/offer.dart';

void main() {
  testWidgets('renders OffersBucket and navigates to add offer', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MyApp(repository: OfferRepository(initialOffers: const [])),
    );
    await tester.pumpAndSettle();

    expect(find.text('OffersBucket'), findsNothing);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Text &&
            widget.textSpan?.toPlainText().startsWith('great deals.') == true,
      ),
      findsOneWidget,
    );
    expect(find.text('No coupons saved'), findsOneWidget);

    await tester.tap(find.text('Add offer'));
    await tester.pumpAndSettle();

    expect(find.text('Add an offer'), findsOneWidget);
    expect(find.text('Save offer'), findsOneWidget);
  });

  testWidgets('copies code from opened offer', (WidgetTester tester) async {
    String? copiedCode;
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
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.pumpWidget(
      MyApp(
        repository: OfferRepository(
          initialOffers: buildSampleOffers(now: DateTime(2026, 10, 22)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final offerFinder = find.text('25% off running shoes');
    await tester.ensureVisible(offerFinder);
    await tester.tap(offerFinder);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilledButton, 'Copy'), findsOneWidget);
    expect(find.text('Original message'), findsOneWidget);
    expect(
      find.text('Nike: Save 25% on selected running shoes with code RUN25.'),
      findsOneWidget,
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Copy'));
    await tester.pumpAndSettle();
    expect(copiedCode, 'RUN25');
    expect(find.text('Code copied'), findsOneWidget);
  });

  testWidgets('account dialog is centered and fields stay editable', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MyApp(repository: OfferRepository(initialOffers: const [])),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsOneWidget);
    final email = find.byType(TextFormField).first;
    await tester.enterText(email, 'user@example.com');
    expect(find.text('user@example.com'), findsOneWidget);
  });
}
