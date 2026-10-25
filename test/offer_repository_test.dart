import 'package:flutter_test/flutter_test.dart';
import 'package:offersbucket/data/offer_repository.dart';
import 'package:offersbucket/models/offer.dart';

void main() {
  final now = DateTime(2026, 10, 22, 12);

  Offer offer({
    required String id,
    required String brand,
    required String title,
    required String category,
    required DateTime validUntil,
    required DateTime savedAt,
  }) {
    return Offer(
      id: id,
      brand: brand,
      title: title,
      description: 'Description',
      code: 'CODE',
      category: category,
      source: 'Test',
      validUntil: validUntil,
      savedAt: savedAt,
      colorValue: 0xFF000000,
      iconKey: 'local_offer',
    );
  }

  test('searches active offers across brand, title, and category', () {
    final repository = OfferRepository(
      initialOffers: [
        offer(
          id: '1',
          brand: 'Acme',
          title: 'Coffee beans',
          category: 'Food',
          validUntil: now.add(const Duration(days: 1)),
          savedAt: now,
        ),
        offer(
          id: '2',
          brand: 'Bravo',
          title: 'Travel bag',
          category: 'Fashion',
          validUntil: now.add(const Duration(days: 2)),
          savedAt: now,
        ),
      ],
    );

    expect(repository.searchByBrand('acmE').single.id, '1');
    expect(repository.searchByTitle('coffee').single.id, '1');
    expect(repository.searchByCategory('fashion').single.id, '2');
  });

  test('sorts by expiry, newest, and brand', () {
    final repository = OfferRepository(
      initialOffers: [
        offer(
          id: 'z',
          brand: 'Zulu',
          title: 'Later',
          category: 'Other',
          validUntil: now.add(const Duration(days: 4)),
          savedAt: now.subtract(const Duration(days: 1)),
        ),
        offer(
          id: 'a',
          brand: 'Acme',
          title: 'Soon',
          category: 'Other',
          validUntil: now.add(const Duration(days: 1)),
          savedAt: now,
        ),
      ],
    );

    expect(repository.offers().map((item) => item.id), ['a', 'z']);
    expect(repository.offers(sort: OfferSort.newest).map((item) => item.id), [
      'a',
      'z',
    ]);
    expect(repository.offers(sort: OfferSort.brand).map((item) => item.id), [
      'a',
      'z',
    ]);
  });

  test(
    'adds custom offers, toggles favorites, and archives expired offers',
    () {
      final repository = OfferRepository(
        initialOffers: const [],
        clock: () => now,
      );
      final customOffer = repository.addCustomOffer(
        brand: 'Custom Co',
        title: 'Member deal',
        description: 'Custom description',
        code: 'MEMBER',
        category: 'Shopping',
        validUntil: now,
        colorValue: 0xFFFFFFFF,
        iconKey: 'shopping_bag',
      );

      expect(repository.toggleFavorite(customOffer.id), isTrue);
      expect(repository.activeOffers.single.isFavorite, isTrue);
      expect(repository.archiveExpired(), 1);
      expect(repository.activeOffers, isEmpty);
      expect(repository.archivedOffers.single.id, customOffer.id);
    },
  );

  test('imports offers and replaces matching ids', () {
    final repository = OfferRepository(initialOffers: const []);
    final imported = offer(
      id: 'drive-1',
      brand: 'Drive Brand',
      title: 'Imported deal',
      category: 'Shopping',
      validUntil: now.add(const Duration(days: 4)),
      savedAt: now,
    );

    expect(repository.importOffers([imported]), 1);
    expect(repository.activeOffers.single.brand, 'Drive Brand');
    expect(repository.importOffers([imported.copyWith(title: 'Updated')]), 1);
    expect(repository.activeOffers.single.title, 'Updated');
  });

  test('keeps original message through JSON round trip', () {
    final original = offer(
      id: 'notice-1',
      brand: 'Brand',
      title: 'Deal',
      category: 'Shopping',
      validUntil: now.add(const Duration(days: 1)),
      savedAt: now,
    ).copyWith(originalMessage: 'Full notification text');
    final restored = Offer.fromJson(original.toJson());
    expect(restored.originalMessage, 'Full notification text');
  });
}
