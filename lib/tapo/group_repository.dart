import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import 'plug_group.dart';

class GroupRepository {
  static const _listKey = 'tapo_groups';

  Future<List<PlugGroup>> loadGroups() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_listKey);
    if (raw == null) return [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list
        .map((e) => PlugGroup.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<void> addGroup({required String name, required List<String> plugIds}) async {
    final groups = await loadGroups();
    await _saveGroups([...groups, PlugGroup(id: _generateId(), name: name, plugIds: plugIds)]);
  }

  Future<void> updateGroup(PlugGroup group) async {
    final groups = await loadGroups();
    await _saveGroups([for (final g in groups) if (g.id == group.id) group else g]);
  }

  Future<void> removeGroup(String id) async {
    final groups = await loadGroups();
    await _saveGroups(groups.where((g) => g.id != id).toList(growable: false));
  }

  Future<void> _saveGroups(List<PlugGroup> groups) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_listKey, jsonEncode(groups.map((g) => g.toJson()).toList()));
  }

  String _generateId() {
    final rand = Random.secure();
    return List<int>.generate(16, (_) => rand.nextInt(256))
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }
}
