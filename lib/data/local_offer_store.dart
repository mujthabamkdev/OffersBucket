import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/offer.dart';
import 'offer_repository.dart';

class LocalOfferStore implements OfferStore {
  LocalOfferStore._(this._preferences);

  static const _offersKey = 'offersbucket.offers.v1';

  final SharedPreferences _preferences;

  static Future<LocalOfferStore> create() async {
    return LocalOfferStore._(await SharedPreferences.getInstance());
  }

  @override
  List<Offer> loadOffers() {
    final raw = _preferences.getString(_offersKey);
    if (raw == null || raw.isEmpty) return const [];

    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .map(
            (item) => Offer.fromJson(
              Map<String, Object?>.from(item as Map<dynamic, dynamic>),
            ),
          )
          .toList();
    } on FormatException {
      return const [];
    } on TypeError {
      return const [];
    }
  }

  @override
  void saveOffers(List<Offer> offers) {
    final encoded = jsonEncode(offers.map((offer) => offer.toJson()).toList());
    _preferences.setString(_offersKey, encoded);
  }
}
