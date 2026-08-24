import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import 'plug_action.dart';

class ActionRepository {
  static const _listKey = 'tapo_actions';

  Future<List<PlugAction>> loadActions() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_listKey);
    if (raw == null) return [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list
        .map((e) => PlugAction.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<void> addAction({
    required String name,
    required List<String> plugIds,
    required int pauseHours,
  }) async {
    final actions = await loadActions();
    await _saveActions([
      ...actions,
      PlugAction(id: _generateId(), name: name, plugIds: plugIds, pauseHours: pauseHours),
    ]);
  }

  Future<void> updateAction(PlugAction action) async {
    final actions = await loadActions();
    await _saveActions([for (final a in actions) if (a.id == action.id) action else a]);
  }

  Future<void> removeAction(String id) async {
    final actions = await loadActions();
    await _saveActions(actions.where((a) => a.id != id).toList(growable: false));
  }

  Future<void> _saveActions(List<PlugAction> actions) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_listKey, jsonEncode(actions.map((a) => a.toJson()).toList()));
  }

  String _generateId() {
    final rand = Random.secure();
    return List<int>.generate(16, (_) => rand.nextInt(256))
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }
}
