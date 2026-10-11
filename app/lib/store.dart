import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

/// Lokalna pohrana: liste (izvori), favoriti, historija i postavke ostaju na uređaju.
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

  static List<String> recent() => List<String>.of(_p.getStringList('recent') ?? <String>[]);

  static Future<void> pushRecent(String key) async {
    final l = recent()..remove(key);
    l.insert(0, key);
    if (l.length > 30) l.removeRange(30, l.length);
    await _p.setStringList('recent', l);
  }

  /// Zapamćena pozicija (ms) za filmove i epizode.
  static int pos(String key) => _p.getInt('pos.$key') ?? 0;

  static Future<void> setPos(String key, int ms) => _p.setInt('pos.$key', ms);

  static String? settingsJson() => _p.getString('settings');

  static Future<void> saveSettingsJson(String s) => _p.setString('settings', s);
}
