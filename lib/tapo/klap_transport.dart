/// HTTP transport for TP-Link's KLAP local protocol.
///
/// Handles the two-stage handshake (auto-detecting v1 vs v2 hash variant by
/// checking which one matches the device's response, mirroring python-kasa's
/// approach), session-cookie tracking, and encrypted request/response
/// exchange with a Tapo device on the local network.
///
/// Requests are sent with raw_http_client.dart's hand-rolled HTTP client
/// rather than dart:io's HttpClient, because some Tapo firmware's embedded
/// HTTP server ("SHIP 2.0") does case-sensitive header matching and rejects
/// the lowercase header names dart:io's HttpClient always sends.
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'klap_crypto.dart';
import 'raw_http_client.dart';

class TapoAuthException implements Exception {
  final String message;
  TapoAuthException(this.message);
  @override
  String toString() => 'TapoAuthException: $message';
}

class TapoRequestException implements Exception {
  final String message;
  TapoRequestException(this.message);
  @override
  String toString() => 'TapoRequestException: $message';
}

class KlapTransport {
  final String host;
  final int port;

  String? _sessionCookie; // e.g. "TP_SESSIONID=abcd1234"
  KlapEncryptionSession? _session;

  KlapTransport({required this.host, this.port = 80});

  Uint8List _randomBytes(int length) {
    final rand = Random.secure();
    return Uint8List.fromList(List<int>.generate(length, (_) => rand.nextInt(256)));
  }

  /// Performs the full handshake against the device using the given
  /// TP-Link account [username] (email) and [password]. Throws
  /// [TapoAuthException] if the credentials don't match what the device
  /// expects, or [TapoRequestException] on other HTTP failures.
  Future<void> handshake(String username, String password) async {
    final localSeed = _randomBytes(16);

    final response1 = await rawHttpPost(
      host: host,
      port: port,
      path: '/app/handshake1',
      body: localSeed,
    );
    if (response1.statusCode != 200) {
      throw TapoRequestException(
        'Device responded with ${response1.statusCode} to handshake1',
      );
    }

    final body = response1.body;
    if (body.length < 48) {
      throw TapoRequestException('Unexpected handshake1 response length: ${body.length}');
    }
    // Some firmware appends a trailing byte after the 48-byte payload
    // (16-byte remote_seed + 32-byte server_hash); ignore anything past that.
    final remoteSeed = body.sublist(0, 16);
    final serverHash = body.sublist(16, 48);

    String? sessionCookie;
    for (final setCookie in response1.setCookieHeaders) {
      for (final part in setCookie.split(';')) {
        final trimmed = part.trim();
        if (trimmed.startsWith('TP_SESSIONID=')) {
          sessionCookie = trimmed;
          break;
        }
      }
      if (sessionCookie != null) break;
    }
    if (sessionCookie == null) {
      throw TapoRequestException('Device did not return a TP_SESSIONID cookie');
    }
    _sessionCookie = sessionCookie;

    KlapVersion? matchedVersion;
    Uint8List? matchedAuthHash;
    for (final version in KlapVersion.values) {
      final authHash = KlapAuthHash.forVersion(version, username, password);
      final candidate = KlapAuthHash.handshake1Hash(version, localSeed, remoteSeed, authHash);
      if (_bytesEqual(candidate, serverHash)) {
        matchedVersion = version;
        matchedAuthHash = authHash;
        break;
      }
    }

    if (matchedVersion == null || matchedAuthHash == null) {
      throw TapoAuthException(
        'Device did not accept the supplied email/password. '
        'Check that both are correct (they are case-sensitive) and match '
        'the TP-Link account used to set up this device in the Tapo app.',
      );
    }

    final handshake2Payload = KlapAuthHash.handshake2Payload(
      matchedVersion,
      localSeed,
      remoteSeed,
      matchedAuthHash,
    );

    final response2 = await rawHttpPost(
      host: host,
      port: port,
      path: '/app/handshake2',
      body: handshake2Payload,
      cookieHeader: _sessionCookie,
    );
    if (response2.statusCode != 200) {
      throw TapoRequestException(
        'Device responded with ${response2.statusCode} to handshake2',
      );
    }

    _session = KlapEncryptionSession(localSeed, remoteSeed, matchedAuthHash);
  }

  bool get isHandshakeComplete => _session != null;

  /// Sends a JSON request map through the encrypted session and returns the
  /// decoded JSON response. Callers must have called [handshake] first.
  Future<Map<String, dynamic>> send(Map<String, dynamic> request) async {
    final session = _session;
    final cookie = _sessionCookie;
    if (session == null || cookie == null) {
      throw StateError('Must call handshake() before send()');
    }

    final (payload, seq) = session.encrypt(
      Uint8List.fromList(utf8.encode(jsonEncode(request))),
    );

    final response = await rawHttpPost(
      host: host,
      port: port,
      path: '/app/request?seq=$seq',
      body: payload,
      cookieHeader: cookie,
    );

    if (response.statusCode == 403) {
      _session = null;
      throw TapoRequestException('Session expired (403); re-handshake required');
    }
    if (response.statusCode != 200) {
      throw TapoRequestException(
        'Device responded with ${response.statusCode} to request seq $seq',
      );
    }

    final decrypted = session.decrypt(response.body);
    return jsonDecode(decrypted) as Map<String, dynamic>;
  }

  bool _bytesEqual(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }

  void close() {}
}
