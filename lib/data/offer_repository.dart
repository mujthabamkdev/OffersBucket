import '../models/offer.dart';

enum OfferSort { expiry, newest, brand }

/// Persistence seam for replacing the in-memory implementation later.
abstract interface class OfferStore {
  List<Offer> loadOffers();

  void saveOffers(List<Offer> offers);
}

class InMemoryOfferStore implements OfferStore {
  InMemoryOfferStore([Iterable<Offer>? initialOffers])
    : _offers = List<Offer>.from(initialOffers ?? const <Offer>[]);

  List<Offer> _offers;

  @override
  List<Offer> loadOffers() => List<Offer>.unmodifiable(_offers);

  @override
  void saveOffers(List<Offer> offers) {
    _offers = List<Offer>.from(offers);
  }
}

class OfferRepository {
  OfferRepository({
    OfferStore? store,
    Iterable<Offer>? initialOffers,
    DateTime Function()? clock,
  }) : _store = store ?? InMemoryOfferStore(initialOffers ?? sampleOffers),
       _clock = clock ?? DateTime.now {
    final storedOffers = _store.loadOffers();
    _offers = List<Offer>.from(
      storedOffers.isEmpty && initialOffers != null
          ? initialOffers
          : storedOffers,
    );
    if (storedOffers.isEmpty && initialOffers != null && _offers.isNotEmpty) {
      _save();
    }
  }

  final OfferStore _store;
  final DateTime Function() _clock;
  late List<Offer> _offers;

  List<Offer> get activeOffers => offers();

  List<Offer> get archivedOffers => offers(archived: true);

  bool isCaptureSaved(String captureId) =>
      _offers.any((offer) => offer.captureId == captureId);

  List<Offer> offers({
    OfferSort sort = OfferSort.expiry,
    bool archived = false,
  }) {
    final matchingOffers = _offers.where(
      (offer) => offer.isArchived == archived,
    );
    return List<Offer>.unmodifiable(_sort(matchingOffers, sort));
  }

  List<Offer> search(
    String query, {
    OfferSort sort = OfferSort.expiry,
    bool includeArchived = false,
  }) {
    final normalizedQuery = query.trim().toLowerCase();
    final matchingOffers = _offers.where((offer) {
      if (!includeArchived && offer.isArchived) {
        return false;
      }

      if (normalizedQuery.isEmpty) {
        return true;
      }

      return _contains(offer.brand, normalizedQuery) ||
          _contains(offer.title, normalizedQuery) ||
          _contains(offer.category, normalizedQuery);
    });

    return List<Offer>.unmodifiable(_sort(matchingOffers, sort));
  }

  List<Offer> searchByBrand(
    String brand, {
    OfferSort sort = OfferSort.expiry,
    bool includeArchived = false,
  }) {
    return search(brand, sort: sort, includeArchived: includeArchived)
        .where((offer) => _contains(offer.brand, brand.trim().toLowerCase()))
        .toList();
  }

  List<Offer> searchByTitle(
    String title, {
    OfferSort sort = OfferSort.expiry,
    bool includeArchived = false,
  }) {
    return search(title, sort: sort, includeArchived: includeArchived)
        .where((offer) => _contains(offer.title, title.trim().toLowerCase()))
        .toList();
  }

  List<Offer> searchByCategory(
    String category, {
    OfferSort sort = OfferSort.expiry,
    bool includeArchived = false,
  }) {
    return search(category, sort: sort, includeArchived: includeArchived)
        .where(
          (offer) => _contains(offer.category, category.trim().toLowerCase()),
        )
        .toList();
  }

  Offer addCustomOffer({
    required String brand,
    required String title,
    required String description,
    String originalMessage = '',
    String? captureId,
    required String code,
    required String category,
    required DateTime validUntil,
    required int colorValue,
    required String iconKey,
    String source = 'Custom',
    DateTime? savedAt,
    bool isFavorite = false,
  }) {
    _requireText(brand, 'brand');
    _requireText(title, 'title');
    _requireText(category, 'category');

    if (captureId != null) {
      _requireText(captureId, 'captureId');
      for (final offer in _offers) {
        if (offer.captureId == captureId) return offer;
      }
    }

    final offer = Offer(
      id: _newId(),
      brand: brand.trim(),
      title: title.trim(),
      description: description.trim(),
      originalMessage: originalMessage.trim(),
      captureId: captureId,
      code: code.trim(),
      category: category.trim(),
      source: source.trim(),
      validUntil: validUntil,
      savedAt: savedAt ?? _clock(),
      isFavorite: isFavorite,
      colorValue: colorValue,
      iconKey: iconKey,
    );

    _offers = [..._offers, offer];
    _save();
    return offer;
  }

  bool toggleFavorite(String id) {
    final index = _offers.indexWhere((offer) => offer.id == id);
    if (index == -1) {
      return false;
    }

    final offer = _offers[index];
    _offers[index] = offer.copyWith(isFavorite: !offer.isFavorite);
    _save();
    return _offers[index].isFavorite;
  }

  int importOffers(Iterable<Offer> importedOffers) {
    final byId = <String, Offer>{for (final offer in _offers) offer.id: offer};
    var importedCount = 0;
    for (final offer in importedOffers) {
      byId[offer.id] = offer;
      importedCount++;
    }
    if (importedCount == 0) return 0;

    _offers = byId.values.toList();
    _save();
    return importedCount;
  }

  int archiveExpired({DateTime? asOf}) {
    final cutoff = asOf ?? _clock();
    var archivedCount = 0;

    _offers = _offers.map((offer) {
      if (!offer.isArchived && !offer.validUntil.isAfter(cutoff)) {
        archivedCount++;
        return offer.copyWith(isArchived: true);
      }
      return offer;
    }).toList();

    if (archivedCount > 0) {
      _save();
    }
    return archivedCount;
  }

  bool _contains(String value, String query) {
    return query.isEmpty || value.toLowerCase().contains(query);
  }

  List<Offer> _sort(Iterable<Offer> offers, OfferSort sort) {
    final sortedOffers = List<Offer>.from(offers);
    sortedOffers.sort((first, second) {
      final comparison = switch (sort) {
        OfferSort.expiry => first.validUntil.compareTo(second.validUntil),
        OfferSort.newest => second.savedAt.compareTo(first.savedAt),
        OfferSort.brand => first.brand.toLowerCase().compareTo(
          second.brand.toLowerCase(),
        ),
      };

      return comparison != 0 ? comparison : first.id.compareTo(second.id);
    });
    return sortedOffers;
  }

  String _newId() {
    final timestamp = _clock().microsecondsSinceEpoch;
    var id = 'custom-$timestamp';
    var suffix = 1;
    while (_offers.any((offer) => offer.id == id)) {
      id = 'custom-$timestamp-$suffix';
      suffix++;
    }
    return id;
  }

  void _requireText(String value, String field) {
    if (value.trim().isEmpty) {
      throw ArgumentError.value(value, field, 'must not be empty');
    }
  }

  void _save() => _store.saveOffers(List<Offer>.unmodifiable(_offers));
}
