import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class TadoHomeConfig {
  final int homeId;
  final String homeName;
  final bool isTadoX;

  TadoHomeConfig({required this.homeId, required this.homeName, required this.isTadoX});

  Map<String, dynamic> toJson() => {
    'homeId': homeId,
    'homeName': homeName,
    'isTadoX': isTadoX,
  };

  factory TadoHomeConfig.fromJson(Map<String, dynamic> json) => TadoHomeConfig(
    homeId: json['homeId'] as int,
    homeName: json['homeName'] as String,
    isTadoX: json['isTadoX'] as bool,
  );
}

class TadoHomeConfigRepository {
  static const _key = 'tado_home_config';

  Future<TadoHomeConfig?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return null;
    return TadoHomeConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> save(TadoHomeConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(config.toJson()));
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
