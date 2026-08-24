import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'saved_plug.dart';

/// Persists the list of plugs the user has added (SharedPreferences) and
/// their passwords (secure storage), keeping the two in sync.
class PlugRepository {
  static const _listKey = 'tapo_plugs';
  final FlutterSecureStorage _secureStorage;

  PlugRepository({FlutterSecureStorage? secureStorage})
    : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  String _passwordKey(String id) => 'tapo_plug_password_$id';

  Future<List<SavedPlug>> loadPlugs() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_listKey);
    if (raw == null) return [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list
        .map((e) => SavedPlug.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<String?> loadPassword(String id) => _secureStorage.read(key: _passwordKey(id));

  Future<void> addPlug({
    required String name,
    required String host,
    required PlugProtocol protocol,
    String email = '',
    String? password,
    String? childId,
  }) async {
    final plug = SavedPlug(
      id: _generateId(),
      name: name,
      host: host,
      email: email,
      protocol: protocol,
      childId: childId,
    );
    final plugs = await loadPlugs();
    await _savePlugs([...plugs, plug]);
    if (password != null) {
      await _secureStorage.write(key: _passwordKey(plug.id), value: password);
    }
  }

  Future<void> removePlug(String id) async {
    final plugs = await loadPlugs();
    await _savePlugs(plugs.where((p) => p.id != id).toList(growable: false));
    await _secureStorage.delete(key: _passwordKey(id));
  }

  Future<void> _savePlugs(List<SavedPlug> plugs) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_listKey, jsonEncode(plugs.map((p) => p.toJson()).toList()));
  }

  String _generateId() {
    final rand = Random.secure();
    return List<int>.generate(16, (_) => rand.nextInt(256))
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }
}
