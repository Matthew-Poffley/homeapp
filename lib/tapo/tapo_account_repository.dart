import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class TapoAccount {
  final String email;
  final String password;
  TapoAccount({required this.email, required this.password});
}

/// Stores the TP-Link account email/password used to set up devices in the
/// Tapo app, so the user doesn't have to retype it for every plug they add.
/// Most households only have one such account across all their devices.
class TapoAccountRepository {
  static const _emailKey = 'tapo_default_account_email';
  static const _passwordKey = 'tapo_default_account_password';

  final FlutterSecureStorage _secureStorage;

  TapoAccountRepository({FlutterSecureStorage? secureStorage})
    : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  Future<TapoAccount?> load() async {
    final email = await _secureStorage.read(key: _emailKey);
    final password = await _secureStorage.read(key: _passwordKey);
    if (email == null || password == null) return null;
    return TapoAccount(email: email, password: password);
  }

  Future<void> save(String email, String password) async {
    await _secureStorage.write(key: _emailKey, value: email);
    await _secureStorage.write(key: _passwordKey, value: password);
  }

  Future<void> clear() async {
    await _secureStorage.delete(key: _emailKey);
    await _secureStorage.delete(key: _passwordKey);
  }
}
