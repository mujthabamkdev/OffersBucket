import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:offersbucket/services/google_drive_backup_service.dart';

void main() {
  test('decodes an OffersBucket backup wrapped in an offers object', () {
    final offers = GoogleDriveBackupService.decodeOffers(
      jsonEncode({
        'offers': [
          {
            'id': 'drive-1',
            'brand': 'Drive Brand',
            'title': 'Drive offer',
            'description': 'Imported from app-only Drive storage.',
            'code': 'DRIVE10',
            'category': 'Other',
            'source': 'OffersBucket',
            'validUntil': '2026-12-01T00:00:00.000Z',
            'savedAt': '2026-10-24T00:00:00.000Z',
            'colorValue': 4278190080,
            'iconKey': 'local_offer',
          },
        ],
      }),
    );

    expect(offers.single.id, 'drive-1');
    expect(offers.single.code, 'DRIVE10');
  });

  test('rejects a backup without an offers list', () {
    expect(
      () => GoogleDriveBackupService.decodeOffers('{}'),
      throwsFormatException,
    );
  });
}
