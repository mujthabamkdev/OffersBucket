import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/web_coupon_deal.dart';

abstract interface class WebCouponSearchService {
  Future<List<WebCouponDeal>> search(String query);
}

/// Uses Actually Useful Deals' public, read-only endpoint.
/// No account or API key is required.
class ActuallyUsefulDealsService implements WebCouponSearchService {
  ActuallyUsefulDealsService({http.Client? client})
    : _client = client ?? http.Client();

  final http.Client _client;

  @override
  Future<List<WebCouponDeal>> search(String query) async {
    final normalizedQuery = query.trim().toLowerCase();
    final response = await _client.get(
      Uri.https('www.actuallyusefuldeals.com', '/wp-json/aud/v1/deals', {
        'limit': '100',
      }),
      headers: const {'Accept': 'application/json'},
    );
    if (response.statusCode != 200) {
      throw WebCouponSearchException(
        'Deals service returned HTTP ${response.statusCode}: '
        '${_errorMessage(response.body)}',
      );
    }

    final decoded = jsonDecode(response.body);
    final rawDeals = decoded is List
        ? decoded
        : decoded is Map<String, dynamic>
        ? decoded['deals']
        : null;
    if (rawDeals is! List) return const [];

    final deals = rawDeals
        .map(
          (item) => WebCouponDeal.fromJson(
            Map<String, Object?>.from(item as Map<dynamic, dynamic>),
          ),
        )
        .where((deal) => _matches(deal, normalizedQuery))
        .toList();
    return List.unmodifiable(deals);
  }

  bool _matches(WebCouponDeal deal, String query) {
    final normalizedQuery = _normalize(query);
    if (normalizedQuery.isEmpty) return true;
    final searchable = _normalize(
      [
        deal.title,
        deal.merchant,
        deal.category,
        deal.description,
        deal.discount,
      ].join(' '),
    );
    return normalizedQuery
        .split(' ')
        .every((term) => searchable.contains(term));
  }

  String _normalize(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();

  String _errorMessage(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        final message = decoded['message'] ?? decoded['error'];
        if (message is String && message.isNotEmpty) return message;
      }
    } catch (_) {
      // Use the status-only error below.
    }
    return 'Try again later.';
  }
}

class WebCouponSearchException implements Exception {
  const WebCouponSearchException(this.message);

  final String message;

  @override
  String toString() => message;
}
