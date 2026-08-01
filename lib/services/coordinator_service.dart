import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/coordinator.dart';

class CoordinatorService {
  static const String _storageKey = 'coordinators_v1';

  static Future<Map<String, Coordinator>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null || raw.isEmpty) return {};

    final decoded = jsonDecode(raw) as List<dynamic>;
    final map = <String, Coordinator>{};
    for (final item in decoded) {
      final coordinator = Coordinator.fromJson(item as Map<String, dynamic>);
      map[coordinator.key] = coordinator;
    }
    return map;
  }

  static Future<void> saveAll(Map<String, Coordinator> coordinators) async {
    final prefs = await SharedPreferences.getInstance();
    final list = coordinators.values.map((c) => c.toJson()).toList();
    await prefs.setString(_storageKey, jsonEncode(list));
  }

  static Future<void> upsert(Coordinator coordinator) async {
    final all = await loadAll();
    all[coordinator.key] = coordinator;
    await saveAll(all);
  }
}
