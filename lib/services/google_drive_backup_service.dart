import 'dart:convert';

import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

import '../models/offer.dart';

const _driveAppDataScope = 'https://www.googleapis.com/auth/drive.appdata';

class GoogleDriveBackupService {
  GoogleDriveBackupService({
    required this.iosClientId,
    required this.webClientId,
    http.Client? httpClient,
  }) : _httpClient = httpClient ?? http.Client();

  final String? iosClientId;
  final String? webClientId;
  final http.Client _httpClient;
  bool _initialized = false;

  bool get isConfigured =>
      (iosClientId?.isNotEmpty ?? false) || (webClientId?.isNotEmpty ?? false);

  Future<List<Offer>> loadLatestBackup() async {
    final headers = await _authorizedHeaders();
    final files = await _listFiles(headers);
    if (files.isEmpty) {
      throw const GoogleDriveBackupNotFoundException(
        'No OffersBucket backup found in Google Drive.',
      );
    }

    final file = Map<String, dynamic>.from(files.first as Map);
    final fileId = file['id'];
    if (fileId is! String || fileId.isEmpty) {
      throw const GoogleDriveRequestException(
        'Google Drive returned an invalid file.',
      );
    }

    final contentResponse = await _httpClient.get(
      Uri.https('www.googleapis.com', '/drive/v3/files/$fileId', {
        'alt': 'media',
      }),
      headers: headers,
    );
    if (contentResponse.statusCode == 401 ||
        contentResponse.statusCode == 403) {
      throw const GoogleDriveAuthorizationException(
        'Google Drive authorization expired or was denied.',
      );
    }
    if (contentResponse.statusCode != 200) {
      throw GoogleDriveRequestException(
        _requestError(
          'Could not download Google Drive backup',
          contentResponse,
        ),
      );
    }

    try {
      return decodeOffers(contentResponse.body);
    } on FormatException {
      throw const GoogleDriveRequestException(
        'Google Drive backup is not valid OffersBucket JSON.',
      );
    } on TypeError {
      throw const GoogleDriveRequestException(
        'Google Drive backup is not valid OffersBucket JSON.',
      );
    }
  }

  Future<void> saveBackup(Iterable<Offer> offers) async {
    final headers = await _authorizedHeaders();
    final files = await _listFiles(headers);
    final content = encodeOffers(offers);

    if (files.isNotEmpty) {
      final file = Map<String, dynamic>.from(files.first as Map);
      final fileId = file['id'];
      if (fileId is! String || fileId.isEmpty) {
        throw const GoogleDriveRequestException(
          'Google Drive returned an invalid backup file.',
        );
      }
      final response = await _httpClient.patch(
        Uri.https('www.googleapis.com', '/upload/drive/v3/files/$fileId', {
          'uploadType': 'media',
        }),
        headers: {...headers, 'Content-Type': 'application/json'},
        body: content,
      );
      if (response.statusCode != 200) {
        throw GoogleDriveRequestException(
          _requestError('Could not update Google Drive backup', response),
        );
      }
      return;
    }

    const boundary = 'offersbucket-drive-boundary';
    final metadata = jsonEncode({
      'name': 'offersbucket-backup.json',
      'parents': ['appDataFolder'],
      'mimeType': 'application/json',
    });
    final body = [
      '--$boundary\r\n',
      'Content-Type: application/json; charset=UTF-8\r\n\r\n',
      metadata,
      '\r\n--$boundary\r\n',
      'Content-Type: application/json\r\n\r\n',
      content,
      '\r\n--$boundary--\r\n',
    ].join();
    final request =
        http.Request(
            'POST',
            Uri.https('www.googleapis.com', '/upload/drive/v3/files', {
              'uploadType': 'multipart',
            }),
          )
          ..headers.addAll({
            ...headers,
            'Content-Type': 'multipart/related; boundary=$boundary',
          })
          ..body = body;
    final response = await http.Response.fromStream(
      await _httpClient.send(request),
    );
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw GoogleDriveRequestException(
        _requestError('Could not create Google Drive backup', response),
      );
    }
  }

  static List<Offer> decodeOffers(String content) {
    final decoded = jsonDecode(content);
    final rawOffers = decoded is List
        ? decoded
        : decoded is Map<String, dynamic>
        ? decoded['offers']
        : null;
    if (rawOffers is! List) {
      throw const FormatException('Missing offers list');
    }

    return rawOffers
        .map(
          (item) => Offer.fromJson(
            Map<String, Object?>.from(item as Map<dynamic, dynamic>),
          ),
        )
        .toList();
  }

  static String encodeOffers(Iterable<Offer> offers) =>
      jsonEncode(offers.map((offer) => offer.toJson()).toList());

  Future<Map<String, String>> _authorizedHeaders() async {
    if (!isConfigured) {
      throw const GoogleDriveConfigurationException(
        'Google Drive is not configured for this build.',
      );
    }

    try {
      await _initialize();
      final account = await GoogleSignIn.instance.authenticate();
      final headers = await account.authorizationClient.authorizationHeaders(
        const [_driveAppDataScope],
        promptIfNecessary: true,
      );
      if (headers == null) {
        throw const GoogleDriveAuthorizationException(
          'Google Drive authorization was not granted.',
        );
      }
      return headers;
    } on GoogleDriveAuthorizationException {
      rethrow;
    } on GoogleSignInException catch (error) {
      throw GoogleDriveAuthorizationException(
        'Google sign-in failed (${error.code}): '
        '${error.description ?? 'Try again.'}',
      );
    } catch (error) {
      throw GoogleDriveAuthorizationException('Google sign-in failed: $error');
    }
  }

  Future<List<dynamic>> _listFiles(Map<String, String> headers) async {
    final response = await _httpClient.get(
      Uri.https('www.googleapis.com', '/drive/v3/files', {
        'q': "'appDataFolder' in parents and trashed = false",
        'spaces': 'appDataFolder',
        'orderBy': 'modifiedTime desc',
        'pageSize': '20',
        'fields': 'files(id,name,mimeType,modifiedTime)',
      }),
      headers: headers,
    );
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw GoogleDriveAuthorizationException(
        _requestError('Google Drive authorization failed', response),
      );
    }
    if (response.statusCode != 200) {
      throw GoogleDriveRequestException(
        _requestError('Could not list Google Drive backups', response),
      );
    }

    final files = (jsonDecode(response.body) as Map<String, dynamic>)['files'];
    return files is List ? files : const [];
  }

  Future<void> _initialize() async {
    if (_initialized) return;
    await GoogleSignIn.instance.initialize(
      clientId: iosClientId,
      serverClientId: webClientId,
    );
    _initialized = true;
  }

  String _requestError(String action, http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      final error = decoded is Map<String, dynamic> ? decoded['error'] : null;
      final message = error is Map<String, dynamic> ? error['message'] : null;
      if (message is String && message.isNotEmpty) {
        return '$action (${response.statusCode}): $message';
      }
    } catch (_) {
      // Fall through to the status-only message.
    }
    return '$action (${response.statusCode}).';
  }
}

class GoogleDriveConfigurationException implements Exception {
  const GoogleDriveConfigurationException(this.message);

  final String message;

  @override
  String toString() => message;
}

class GoogleDriveAuthorizationException implements Exception {
  const GoogleDriveAuthorizationException(this.message);

  final String message;

  @override
  String toString() => message;
}

class GoogleDriveBackupNotFoundException implements Exception {
  const GoogleDriveBackupNotFoundException(this.message);

  final String message;

  @override
  String toString() => message;
}

class GoogleDriveRequestException implements Exception {
  const GoogleDriveRequestException(this.message);

  final String message;

  @override
  String toString() => message;
}
