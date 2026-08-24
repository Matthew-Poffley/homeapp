/// OAuth2 Device Authorization Grant (RFC 8628) client for Tado's API, per
/// Tado's own support documentation
/// (https://support.tado.com/en/articles/8565472). The user opens
/// [DeviceAuthorization.verificationUriComplete] in a browser and logs in
/// there themselves — this app never sees their Tado password.
library;

import 'dart:convert';
import 'dart:io';

class TadoAuthException implements Exception {
  final String message;
  TadoAuthException(this.message);
  @override
  String toString() => 'TadoAuthException: $message';
}

class DeviceAuthorization {
  final String deviceCode;
  final String userCode;
  final String verificationUri;
  final String verificationUriComplete;
  final int expiresInSeconds;
  final int pollIntervalSeconds;

  DeviceAuthorization({
    required this.deviceCode,
    required this.userCode,
    required this.verificationUri,
    required this.verificationUriComplete,
    required this.expiresInSeconds,
    required this.pollIntervalSeconds,
  });
}

class TadoTokens {
  final String accessToken;
  final String refreshToken;
  final DateTime expiresAt;

  TadoTokens({required this.accessToken, required this.refreshToken, required this.expiresAt});

  bool get isExpired => DateTime.now().isAfter(expiresAt.subtract(const Duration(seconds: 5)));

  Map<String, dynamic> toJson() => {
    'accessToken': accessToken,
    'refreshToken': refreshToken,
    'expiresAt': expiresAt.toIso8601String(),
  };

  factory TadoTokens.fromJson(Map<String, dynamic> json) => TadoTokens(
    accessToken: json['accessToken'] as String,
    refreshToken: json['refreshToken'] as String,
    expiresAt: DateTime.parse(json['expiresAt'] as String),
  );
}

class TadoAuthClient {
  static const _clientId = '1bb50063-6b0c-4d11-bd99-387f4a91cc46';
  static const _deviceAuthorizeUrl = 'https://login.tado.com/oauth2/device_authorize';
  static const _tokenUrl = 'https://login.tado.com/oauth2/token';

  final HttpClient _client = HttpClient();

  Future<Map<String, dynamic>> _post(String url, Map<String, String> params) async {
    final uri = Uri.parse(url).replace(queryParameters: params);
    final request = await _client.postUrl(uri);
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    final decoded = jsonDecode(body) as Map<String, dynamic>;
    if (response.statusCode != 200) {
      final error = decoded['error'] as String? ?? 'unknown_error';
      throw TadoAuthException('$error: ${decoded['error_description'] ?? body}');
    }
    return decoded;
  }

  Future<DeviceAuthorization> startDeviceAuthorization() async {
    final json = await _post(_deviceAuthorizeUrl, {
      'client_id': _clientId,
      'scope': 'offline_access',
    });
    return DeviceAuthorization(
      deviceCode: json['device_code'] as String,
      userCode: json['user_code'] as String,
      verificationUri: json['verification_uri'] as String,
      verificationUriComplete: json['verification_uri_complete'] as String,
      expiresInSeconds: json['expires_in'] as int,
      pollIntervalSeconds: json['interval'] as int,
    );
  }

  /// Returns null if still pending (caller should wait `interval` seconds
  /// and poll again); throws [TadoAuthException] if denied/expired.
  Future<TadoTokens?> pollForToken(DeviceAuthorization auth) async {
    try {
      final json = await _post(_tokenUrl, {
        'client_id': _clientId,
        'device_code': auth.deviceCode,
        'grant_type': 'urn:ietf:params:oauth:grant-type:device_code',
      });
      return TadoTokens(
        accessToken: json['access_token'] as String,
        refreshToken: json['refresh_token'] as String,
        expiresAt: DateTime.now().add(Duration(seconds: json['expires_in'] as int)),
      );
    } on TadoAuthException catch (e) {
      if (e.message.startsWith('authorization_pending')) return null;
      rethrow;
    }
  }

  Future<TadoTokens> refresh(String refreshToken) async {
    final json = await _post(_tokenUrl, {
      'client_id': _clientId,
      'grant_type': 'refresh_token',
      'refresh_token': refreshToken,
    });
    return TadoTokens(
      accessToken: json['access_token'] as String,
      refreshToken: json['refresh_token'] as String,
      expiresAt: DateTime.now().add(Duration(seconds: json['expires_in'] as int)),
    );
  }

  void close() => _client.close(force: true);
}
