import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

/// Lokalna pohrana: liste (izvori) i favoriti ostaju na uređaju.
class Store {
  static late SharedPreferences _p;

  static Future<void> init() async {
    _p = await SharedPreferences.getInstance();
  }

  static List<Source> sources() {
    final raw = _p.getString('sources');
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List)
          .map((e) => Source.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveSources(List<Source> s) =>
      _p.setString('sources', jsonEncode(s.map((e) => e.toJson()).toList()));

  static Set<String> favs() => (_p.getStringList('favs') ?? <String>[]).toSet();

  static Future<void> saveFavs(Set<String> f) =>
      _p.setStringList('favs', f.toList());
}
