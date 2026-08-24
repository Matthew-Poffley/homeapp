import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'tado_auth_client.dart';

class TadoTokenRepository {
  static const _key = 'tado_tokens';

  final FlutterSecureStorage _secureStorage;

  TadoTokenRepository({FlutterSecureStorage? secureStorage})
    : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  Future<TadoTokens?> load() async {
    final raw = await _secureStorage.read(key: _key);
    if (raw == null) return null;
    return TadoTokens.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> save(TadoTokens tokens) async {
    await _secureStorage.write(key: _key, value: jsonEncode(tokens.toJson()));
  }

  Future<void> clear() async {
    await _secureStorage.delete(key: _key);
  }
}
