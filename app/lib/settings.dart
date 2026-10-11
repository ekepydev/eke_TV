import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'store.dart';

class KeyAct {
  const KeyAct(this.id, this.label);
  final String id;
  final String label;
}

/// Radnje koje se mogu vezati za tipke (u plejeru).
const List<KeyAct> kKeyActs = [
  KeyAct('fullscreen', 'Preko cijelog ekrana'),
  KeyAct('volumeUp', 'Pojačaj'),
  KeyAct('volumeDown', 'Smanji'),
  KeyAct('mute', 'Utišaj / vrati zvuk'),
  KeyAct('seekForward', 'Naprijed (film) / sljedeći kanal (TV)'),
  KeyAct('seekBack', 'Nazad (film) / prethodni kanal (TV)'),
  KeyAct('nextChannel', 'Sljedeći kanal / epizoda'),
  KeyAct('prevChannel', 'Prethodni kanal / epizoda'),
  KeyAct('lastChannel', 'Zadnji gledani kanal'),
  KeyAct('playPause', 'Pauza / nastavi'),
  KeyAct('info', 'Prikaži / sakrij info'),
  KeyAct('subtitles', 'Titlovi i audio'),
  KeyAct('aspect', 'Omjer slike'),
  KeyAct('back', 'Nazad'),
];

final Map<String, LogicalKeyboardKey> kDefaultKeys = {
  'fullscreen': LogicalKeyboardKey.keyF,
  'volumeUp': LogicalKeyboardKey.arrowUp,
  'volumeDown': LogicalKeyboardKey.arrowDown,
  'mute': LogicalKeyboardKey.keyM,
  'seekForward': LogicalKeyboardKey.arrowRight,
  'seekBack': LogicalKeyboardKey.arrowLeft,
  'nextChannel': LogicalKeyboardKey.pageDown,
  'prevChannel': LogicalKeyboardKey.pageUp,
  'lastChannel': LogicalKeyboardKey.keyL,
  'playPause': LogicalKeyboardKey.space,
  'info': LogicalKeyboardKey.keyI,
  'subtitles': LogicalKeyboardKey.keyS,
  'aspect': LogicalKeyboardKey.keyZ,
  'back': LogicalKeyboardKey.escape,
};

String keyName(LogicalKeyboardKey k) {
  final names = <LogicalKeyboardKey, String>{
    LogicalKeyboardKey.arrowUp: '↑',
    LogicalKeyboardKey.arrowDown: '↓',
    LogicalKeyboardKey.arrowLeft: '←',
    LogicalKeyboardKey.arrowRight: '→',
    LogicalKeyboardKey.space: 'Razmaknica',
    LogicalKeyboardKey.enter: 'Enter',
    LogicalKeyboardKey.escape: 'Esc',
    LogicalKeyboardKey.pageUp: 'Page Up',
    LogicalKeyboardKey.pageDown: 'Page Down',
    LogicalKeyboardKey.home: 'Home',
    LogicalKeyboardKey.end: 'End',
    LogicalKeyboardKey.backspace: 'Backspace',
    LogicalKeyboardKey.tab: 'Tab',
    LogicalKeyboardKey.channelUp: 'CH+',
    LogicalKeyboardKey.channelDown: 'CH-',
    LogicalKeyboardKey.mediaPlayPause: 'Play/Pause',
  };
  final n = names[k];
  if (n != null) return n;
  if (k.keyLabel.isNotEmpty) return k.keyLabel.toUpperCase();
  return 'Tipka ${k.keyId}';
}

class AppSettings extends ChangeNotifier {
  AppSettings._();
  static final AppSettings I = AppSettings._();

  ThemeMode themeMode = ThemeMode.dark;

  /// Zadani jezik titla: bs, hr ili sr.
  String subLang = 'bs';
  bool autoSubs = true;
  String osKey = '';
  String osUser = '';
  String osPass = '';

  /// Globalni XMLTV URL (koristi se ako lista nema svoj).
  String xmltv = '';
  bool autoOpenLast = true;
  String lastSourceId = '';
  int skipSeconds = 10;
  final Map<String, int> _keys = {};

  void load() {
    final raw = Store.settingsJson();
    if (raw == null) return;
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      switch (j['theme']) {
        case 'light':
          themeMode = ThemeMode.light;
          break;
        case 'system':
          themeMode = ThemeMode.system;
          break;
        default:
          themeMode = ThemeMode.dark;
      }
      subLang = (j['subLang'] as String?) ?? 'bs';
      autoSubs = (j['autoSubs'] as bool?) ?? true;
      osKey = (j['osKey'] as String?) ?? '';
      osUser = (j['osUser'] as String?) ?? '';
      osPass = (j['osPass'] as String?) ?? '';
      xmltv = (j['xmltv'] as String?) ?? '';
      autoOpenLast = (j['autoOpenLast'] as bool?) ?? true;
      lastSourceId = (j['lastSourceId'] as String?) ?? '';
      skipSeconds = (j['skipSeconds'] as int?) ?? 10;
      _keys.clear();
      final k = j['keys'];
      if (k is Map) {
        k.forEach((a, v) {
          if (v is int) _keys['$a'] = v;
        });
      }
    } catch (_) {}
  }

  Future<void> save({bool notify = true}) async {
    final theme = themeMode == ThemeMode.light
        ? 'light'
        : (themeMode == ThemeMode.system ? 'system' : 'dark');
    await Store.saveSettingsJson(jsonEncode({
      'theme': theme,
      'subLang': subLang,
      'autoSubs': autoSubs,
      'osKey': osKey,
      'osUser': osUser,
      'osPass': osPass,
      'xmltv': xmltv,
      'autoOpenLast': autoOpenLast,
      'lastSourceId': lastSourceId,
      'skipSeconds': skipSeconds,
      'keys': _keys,
    }));
    if (notify) notifyListeners();
  }

  LogicalKeyboardKey keyFor(String action) {
    final id = _keys[action];
    if (id == null) return kDefaultKeys[action]!;
    return LogicalKeyboardKey(id);
  }

  String? actionFor(LogicalKeyboardKey k) {
    for (final a in kKeyActs) {
      if (keyFor(a.id) == k) return a.id;
    }
    return null;
  }

  /// Veže tipku za radnju. Ako je tipka već zauzeta, tipke se zamijene.
  Future<void> setKey(String action, LogicalKeyboardKey k) async {
    final other = actionFor(k);
    if (other != null && other != action) {
      _keys[other] = keyFor(action).keyId;
    }
    _keys[action] = k.keyId;
    await save();
  }

  Future<void> resetKeys() async {
    _keys.clear();
    await save();
  }
}
