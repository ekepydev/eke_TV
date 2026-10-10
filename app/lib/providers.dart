import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'models.dart';

/// User-Agent kakav šalje MAG set-top box.
const kStbUa =
    'Mozilla/5.0 (QtEmbedded; U; Linux; C) AppleWebKit/533.3 (KHTML, like Gecko) MAG200 stbapp ver: 2 rev: 250 Safari/533.3';

/// Neki provajderi blokiraju nepoznate User-Agente; VLC prolazi gotovo svuda.
const kPlayerUa = 'VLC/3.0.18 LibVLC/3.0.18';

const _timeout = Duration(seconds: 30);

String normUrl(String u) {
  final t = u.trim();
  return RegExp(r'^https?://', caseSensitive: false).hasMatch(t) ? t : 'http://$t';
}

String errMsg(Object e) {
  if (e is TimeoutException) return 'Isteklo vrijeme veze sa serverom';
  if (e is SocketException) return 'Nema veze sa serverom (provjeri adresu i internet)';
  if (e is FormatException) return 'Neispravan odgovor servera';
  return e.toString().replaceFirst('Exception: ', '');
}

Future<String> _getText(String url, {Map<String, String>? headers}) async {
  final r = await http.get(Uri.parse(url), headers: headers).timeout(_timeout);
  if (r.statusCode != 200) throw Exception('HTTP ${r.statusCode}');
  return utf8.decode(r.bodyBytes, allowMalformed: true);
}

// ---------- M3U ----------
List<Channel> parseM3u(String text) {
  final out = <Channel>[];
  String? name;
  String logo = '';
  String group = 'Ostalo';

  String attr(String line, String key) {
    final m = RegExp('$key="([^"]*)"', caseSensitive: false).firstMatch(line);
    return m?.group(1) ?? '';
  }

  for (final raw in const LineSplitter().convert(text)) {
    final l = raw.trim();
    if (l.isEmpty) continue;
    if (l.startsWith('#EXTINF')) {
      final q = l.lastIndexOf('"');
      final c = l.indexOf(',', q + 1);
      final n = c >= 0 ? l.substring(c + 1).trim() : '';
      final tvgName = attr(l, 'tvg-name');
      name = n.isNotEmpty ? n : (tvgName.isNotEmpty ? tvgName : 'Kanal');
      logo = attr(l, 'tvg-logo');
      final g = attr(l, 'group-title');
      group = g.isEmpty ? 'Ostalo' : g;
    } else if (!l.startsWith('#') && name != null) {
      out.add(Channel(
        id: '${out.length}',
        name: name,
        logo: logo,
        group: group,
        url: l,
        num: out.length + 1,
      ));
      name = null;
    }
  }
  return out;
}

// ---------- Xtream ----------
Future<List<Channel>> loadXtream(Source s) async {
  final base = normUrl(s.server).replaceAll(RegExp(r'/+$'), '');
  final u = Uri.encodeComponent(s.user);
  final p = Uri.encodeComponent(s.pass);
  final api = '$base/player_api.php?username=$u&password=$p';
  final h = {'User-Agent': kPlayerUa};

  Future<dynamic> js(String action) async =>
      jsonDecode(await _getText('$api$action', headers: h));

  final res = await Future.wait<dynamic>([
    js('&action=get_live_categories'),
    js('&action=get_live_streams'),
  ]);
  final cats = res[0];
  final streams = res[1];
  if (streams is! List) {
    throw Exception('Pogrešni podaci za prijavu ili server ne podržava Xtream API');
  }
  final cm = <String, String>{};
  if (cats is List) {
    for (final c in cats) {
      if (c is Map) cm['${c['category_id']}'] = '${c['category_name']}';
    }
  }
  final out = <Channel>[];
  var i = 0;
  for (final x in streams) {
    if (x is! Map) continue;
    i++;
    out.add(Channel(
      id: '${x['stream_id']}',
      name: '${x['name']}',
      logo: '${x['stream_icon'] ?? ''}',
      group: cm['${x['category_id']}'] ?? 'Ostalo',
      num: int.tryParse('${x['num']}') ?? i,
      url: '$base/live/$u/$p/${x['stream_id']}.ts',
    ));
  }
  return out;
}

// ---------- Stalker (MAG emulacija) ----------
class StalkerClient {
  StalkerClient(this.s);
  final Source s;
  String _api = '';
  String _token = '';

  Map<String, String> _headers() => {
        'User-Agent': kStbUa,
        'X-User-Agent': 'Model: MAG250; Link: WiFi',
        'Cookie': 'mac=${s.mac}; stb_lang=en; timezone=Europe/Sarajevo',
        'Accept': '*/*',
        if (_token.isNotEmpty) 'Authorization': 'Bearer $_token',
      };

  List<String> _candidates() {
    final p = normUrl(s.portal).replaceAll(RegExp(r'/+$'), '');
    if (RegExp(r'\.php$', caseSensitive: false).hasMatch(p)) return [p];
    final base = p.replaceFirst(
        RegExp(r'/(stalker_portal/c|stalker_portal|c)$', caseSensitive: false), '');
    return <String>{
      '$base/portal.php',
      '$base/server/load.php',
      '$base/stalker_portal/server/load.php',
    }.toList();
  }

  Future<dynamic> _call(String api, String qs) async {
    final r = await http
        .get(Uri.parse('$api?$qs&JsHttpRequest=1-xml'), headers: _headers())
        .timeout(_timeout);
    if (r.statusCode != 200) throw Exception('HTTP ${r.statusCode}');
    final t = utf8.decode(r.bodyBytes, allowMalformed: true);
    dynamic j;
    try {
      j = jsonDecode(t);
    } catch (_) {
      throw Exception('Portal nije vratio JSON (pogrešan URL ili MAC nije aktivan)');
    }
    return j is Map ? j['js'] : null;
  }

  Future<void> auth() async {
    Object? last;
    for (final api in _candidates()) {
      try {
        _token = '';
        final hs = await _call(api, 'type=stb&action=handshake&token=&prehash=0');
        final tok = hs is Map ? hs['token'] : null;
        if (tok == null || '$tok'.isEmpty) throw Exception('Handshake nije uspio');
        _token = '$tok';
        _api = api;
        try {
          await _call(api,
              'type=stb&action=get_profile&hd=1&stb_type=MAG250&client_type=STB&auth_second_step=0&not_valid_token=0');
        } catch (_) {}
        return;
      } catch (e) {
        last = e;
      }
    }
    _api = '';
    _token = '';
    throw last ?? Exception('Portal nije dostupan');
  }

  Future<List<Channel>> loadChannels() async {
    await auth();
    final genres = <String, String>{};
    try {
      final g = await _call(_api, 'type=itv&action=get_genres');
      if (g is List) {
        for (final x in g) {
          if (x is Map) genres['${x['id']}'] = '${x['title']}';
        }
      }
    } catch (_) {}
    final res = await _call(_api, 'type=itv&action=get_all_channels');
    final data = res is Map ? res['data'] : null;
    if (data is! List || data.isEmpty) {
      throw Exception('Portal nije vratio kanale (provjeri MAC adresu)');
    }
    final origin = Uri.parse(_api).origin;
    final out = <Channel>[];
    var i = 0;
    for (final c in data) {
      if (c is! Map) continue;
      i++;
      final logo = '${c['logo'] ?? ''}';
      out.add(Channel(
        id: '${c['id']}',
        name: '${c['name']}',
        cmd: '${c['cmd']}',
        num: int.tryParse('${c['number']}') ?? i,
        group: genres['${c['tv_genre_id']}'] ?? 'Ostalo',
        logo: logo.isEmpty
            ? ''
            : (logo.startsWith('http') ? logo : '$origin/stalker_portal/misc/logos/320/$logo'),
      ));
    }
    return out;
  }

  Future<String> link(Channel c, {bool retry = true}) async {
    try {
      if (_api.isEmpty) await auth();
      final r = await _call(_api,
          'type=itv&action=create_link&cmd=${Uri.encodeComponent(c.cmd ?? '')}&series=&forced_streaming=0&disable_ip_check=0&download=0');
      final raw = r is Map ? '${r['cmd'] ?? ''}' : '';
      if (raw.isEmpty) throw Exception('Portal nije vratio link');
      return raw.replaceFirst(RegExp(r'^\w+\s+'), '').trim();
    } catch (e) {
      if (!retry) rethrow;
      _api = '';
      _token = '';
      return link(c, retry: false);
    }
  }
}

// ---------- zajednički ulaz ----------
class Repo {
  static final Map<String, StalkerClient> _st = {};

  static StalkerClient _client(Source s) =>
      _st.putIfAbsent(s.id, () => StalkerClient(s));

  static Future<List<Channel>> loadChannels(Source s) async {
    switch (s.type) {
      case 'm3u':
        return parseM3u(
            await _getText(normUrl(s.url), headers: {'User-Agent': kPlayerUa}));
      case 'xtream':
        return loadXtream(s);
      case 'stalker':
        return _client(s).loadChannels();
      default:
        throw Exception('Nepoznat tip izvora');
    }
  }

  static Future<Resolved> resolve(Source s, Channel c) async {
    if (c.url == null) {
      final u = await _client(s).link(c);
      return Resolved(u, {'User-Agent': kStbUa, 'X-User-Agent': 'Model: MAG250; Link: WiFi'});
    }
    return Resolved(c.url!, {'User-Agent': kPlayerUa});
  }
}
