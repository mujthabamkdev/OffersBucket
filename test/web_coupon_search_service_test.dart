import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:offersbucket/services/web_coupon_search_service.dart';

class _FakeClient extends http.BaseClient {
  _FakeClient(this.payload);

  final String payload;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    return http.StreamedResponse(
      Stream.value(utf8.encode(payload)),
      200,
      headers: const {'content-type': 'application/json'},
    );
  }
}

void main() {
  test('matches multi-word searches across normalized deal text', () async {
    final service = ActuallyUsefulDealsService(
      client: _FakeClient(
        jsonEncode({
          'deals': [
            {
              'title': 'USB-C Charger',
              'merchant': 'Example Store',
              'category': {'name': 'Power & Charging'},
              'url': 'https://example.com/deal',
              'price': '24.99',
              'discount': '20% off',
              'useful_for': 'Travel and desk setups',
              'updated_at': '2026-10-24T00:00:00Z',
            },
          ],
        }),
      ),
    );

    final deals = await service.search('usb c');

    expect(deals.single.title, 'USB-C Charger');
  });
}
