import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'epg.dart';
import 'models.dart';
import 'settings.dart';

/// User-Agent kakav šalje MAG set-top box.
const kStbUa =
    'Mozilla/5.0 (QtEmbedded; U; Linux; C) AppleWebKit/533.3 (KHTML, like Gecko) MAG200 stbapp ver: 2 rev: 250 Safari/533.3';

/// Neki provajderi blokiraju nepoznate User-Agente; VLC prolazi gotovo svuda.
const kPlayerUa = 'VLC/3.0.18 LibVLC/3.0.18';

const _timeout = Duration(seconds: 30);
const _bigTimeout = Duration(seconds: 120);

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

String _s(dynamic v) => v == null ? '' : '$v';

dynamic _decodeJson(String s) => jsonDecode(s);

Future<String> _getText(
  String url, {
  Map<String, String>? headers,
  Duration timeout = _timeout,
}) async {
  final r = await http.get(Uri.parse(url), headers: headers).timeout(timeout);
  if (r.statusCode != 200) throw Exception('HTTP ${r.statusCode}');
  return utf8.decode(r.bodyBytes, allowMalformed: true);
}

Future<dynamic> _getJson(String url, {Map<String, String>? headers}) async {
  final text = await _getText(url, headers: headers, timeout: _bigTimeout);
  return compute(_decodeJson, text);
}

String _rating(dynamic v) {
  final n = double.tryParse(_s(v));
  if (n == null || n <= 0) return '';
  return n.toStringAsFixed(1);
}

String _year(String name, String explicit) {
  if (RegExp(r'^(19|20)\d{2}$').hasMatch(explicit)) return explicit;
  final m = RegExp(r'\b((?:19|20)\d{2})\b').firstMatch(name);
  return m?.group(1) ?? '';
}

String _b64(String s) {
  if (s.isEmpty) return '';
  try {
    return utf8.decode(base64.decode(base64.normalize(s)), allowMalformed: true);
  } catch (_) {
    return s;
  }
}

// ---------- M3U ----------
List<Channel> parseM3u(String text) {
  final out = <Channel>[];
  String? name;
  String logo = '';
  String group = 'Ostalo';
  String epgId = '';

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
      epgId = attr(l, 'tvg-id');
    } else if (!l.startsWith('#') && name != null) {
      out.add(Channel(
        id: '${out.length}',
        name: name,
        logo: logo,
        group: group,
        url: l,
        num: out.length + 1,
        epgId: epgId,
      ));
      name = null;
    }
  }
  return out;
}

bool looksLikeM3u(String text) =>
    text.contains('#EXTM3U') || text.contains('#EXTINF');

// ---------- Xtream ----------
class _Xt {
  _Xt(Source s)
      : base = normUrl(s.server).replaceAll(RegExp(r'/+$'), ''),
        u = Uri.encodeComponent(s.user),
        p = Uri.encodeComponent(s.pass);

  final String base;
  final String u;
  final String p;

  String get api => '$base/player_api.php?username=$u&password=$p';

  Future<dynamic> call(String action, [String extra = '']) =>
      _getJson('$api&action=$action$extra', headers: {'User-Agent': kPlayerUa});

  String live(String id) => '$base/live/$u/$p/$id.ts';
  String movie(String id, String ext) => '$base/movie/$u/$p/$id.$ext';
  String episode(String id, String ext) => '$base/series/$u/$p/$id.$ext';
}

List<CatEntry> _cats(dynamic j) {
  final out = <CatEntry>[];
  if (j is List) {
    for (final c in j) {
      if (c is Map) out.add(CatEntry(_s(c['category_id']), _s(c['category_name'])));
    }
  }
  return out;
}

Future<List<Channel>> loadXtream(Source s) async {
  final x = _Xt(s);
  final res = await Future.wait<dynamic>([
    x.call('get_live_categories'),
    x.call('get_live_streams'),
  ]);
  final streams = res[1];
  if (streams is! List) {
    throw Exception('Pogrešni podaci za prijavu ili server ne podržava Xtream API');
  }
  final cm = <String, String>{for (final c in _cats(res[0])) c.id: c.name};
  final out = <Channel>[];
  var i = 0;
  for (final m in streams) {
    if (m is! Map) continue;
    i++;
    out.add(Channel(
      id: _s(m['stream_id']),
      name: _s(m['name']),
      logo: _s(m['stream_icon']),
      group: cm[_s(m['category_id'])] ?? 'Ostalo',
      num: int.tryParse(_s(m['num'])) ?? i,
      url: x.live(_s(m['stream_id'])),
      epgId: _s(m['epg_channel_id']),
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
          if (x is Map) genres[_s(x['id'])] = _s(x['title']);
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
      final logo = _s(c['logo']);
      out.add(Channel(
        id: _s(c['id']),
        name: _s(c['name']),
        cmd: _s(c['cmd']),
        num: int.tryParse(_s(c['number'])) ?? i,
        group: genres[_s(c['tv_genre_id'])] ?? 'Ostalo',
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
      final raw = r is Map ? _s(r['cmd']) : '';
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

class _EpgHit {
  _EpgHit(this.list) : at = DateTime.now();
  final List<Programme> list;
  final DateTime at;
}

// ---------- zajednički ulaz ----------
class Repo {
  static final Map<String, StalkerClient> _st = {};
  static final Map<String, List<Channel>> _live = {};
  static final Map<String, CatalogData<VodItem>> _vod = {};
  static final Map<String, CatalogData<SeriesItem>> _series = {};
  static final Map<String, _EpgHit> _epg = {};

  /// XMLTV adrese pročitane iz zaglavlja M3U liste (url-tvg / x-tvg-url).
  static final Map<String, String> m3uEpg = {};

  static StalkerClient _client(Source s) => _st.putIfAbsent(s.id, () => StalkerClient(s));

  static List<Channel> _m3u(Source s, String text) {
    if (!looksLikeM3u(text)) throw Exception('Ovo nije ispravna M3U lista');
    final head = text.substring(0, text.length < 600 ? text.length : 600);
    final m = RegExp(r'(?:x-tvg-url|url-tvg)="([^"]*)"', caseSensitive: false).firstMatch(head);
    final u = m?.group(1)?.split(',').first.trim() ?? '';
    if (u.isNotEmpty) m3uEpg[s.id] = u;
    return parseM3u(text);
  }

  static Future<List<Channel>> loadChannels(Source s, {bool force = false}) async {
    if (!force && _live.containsKey(s.id)) return _live[s.id]!;
    List<Channel> list;
    switch (s.type) {
      case 'm3u':
        list = _m3u(
          s,
          await _getText(normUrl(s.url),
              headers: {'User-Agent': kPlayerUa}, timeout: _bigTimeout),
        );
        break;
      case 'file':
        list = _m3u(s, utf8.decode(await File(s.file).readAsBytes(), allowMalformed: true));
        break;
      case 'xtream':
        list = await loadXtream(s);
        break;
      case 'stalker':
        list = await _client(s).loadChannels();
        break;
      default:
        throw Exception('Nepoznat tip izvora');
    }
    if (list.isEmpty) throw Exception('Lista je prazna');
    _live[s.id] = list;
    return list;
  }

  static Future<Resolved> resolve(Source s, Channel c) async {
    if (c.url == null) {
      final u = await _client(s).link(c);
      return Resolved(u, {'User-Agent': kStbUa, 'X-User-Agent': 'Model: MAG250; Link: WiFi'});
    }
    return Resolved(c.url!, {'User-Agent': kPlayerUa});
  }

  // ----- EPG -----
  static Future<List<Programme>> epg(Source s, Channel c) async {
    final key = '${s.id}:${c.id}';
    final hit = _epg[key];
    if (hit != null && DateTime.now().difference(hit.at) < const Duration(minutes: 10)) {
      return hit.list;
    }
    var list = <Programme>[];
    try {
      if (s.type == 'xtream') {
        list = await _xtreamEpg(s, c.id);
      } else if (c.epgId.isNotEmpty) {
        final url = s.xmltv.isNotEmpty
            ? s.xmltv
            : (m3uEpg[s.id] ?? AppSettings.I.xmltv);
        if (url.isNotEmpty) {
          final map = await Epg.load(url);
          list = map[c.epgId.toLowerCase()] ?? <Programme>[];
        }
      }
    } catch (_) {}
    _epg[key] = _EpgHit(list);
    return list;
  }

  static Future<List<Programme>> _xtreamEpg(Source s, String streamId) async {
    final j = await _Xt(s).call('get_short_epg', '&stream_id=$streamId&limit=8');
    final l = j is Map ? j['epg_listings'] : null;
    final out = <Programme>[];
    if (l is List) {
      for (final e in l) {
        if (e is! Map) continue;
        final st = int.tryParse(_s(e['start_timestamp']));
        final en = int.tryParse(_s(e['stop_timestamp']));
        if (st == null || en == null) continue;
        out.add(Programme(
          _b64(_s(e['title'])),
          _b64(_s(e['description'])),
          DateTime.fromMillisecondsSinceEpoch(st * 1000),
          DateTime.fromMillisecondsSinceEpoch(en * 1000),
        ));
      }
    }
    out.sort((a, b) => a.start.compareTo(b.start));
    return out;
  }

  // ----- Filmovi (Xtream VOD) -----
  static Future<CatalogData<VodItem>> loadMovies(Source s, {bool force = false}) async {
    if (!force && _vod.containsKey(s.id)) return _vod[s.id]!;
    final x = _Xt(s);
    final res = await Future.wait<dynamic>([
      x.call('get_vod_categories'),
      x.call('get_vod_streams'),
    ]);
    final raw = res[1];
    if (raw is! List) {
      throw Exception('Ova lista nema filmove ili su podaci za prijavu pogrešni');
    }
    final items = <VodItem>[];
    for (final m in raw) {
      if (m is! Map) continue;
      final name = _s(m['name']);
      final ext = _s(m['container_extension']);
      items.add(VodItem(
        id: _s(m['stream_id']),
        name: name,
        cover: _s(m['stream_icon']),
        rating: _rating(m['rating']),
        year: _year(name, _s(m['year'])),
        added: int.tryParse(_s(m['added'])) ?? 0,
        categoryId: _s(m['category_id']),
        ext: ext.isEmpty ? 'mp4' : ext,
      ));
    }
    final d = CatalogData<VodItem>(_cats(res[0]), items);
    _vod[s.id] = d;
    return d;
  }

  static Future<VodInfo> vodInfo(Source s, String id) async {
    final j = await _Xt(s).call('get_vod_info', '&vod_id=$id');
    final info = j is Map ? j['info'] : null;
    if (info is! Map) return const VodInfo();
    var back = '';
    final bp = info['backdrop_path'];
    if (bp is List && bp.isNotEmpty) back = _s(bp.first);
    final rd = _s(info['releasedate']).isNotEmpty ? _s(info['releasedate']) : _s(info['release_date']);
    return VodInfo(
      plot: _s(info['plot']).isNotEmpty ? _s(info['plot']) : _s(info['description']),
      genre: _s(info['genre']),
      duration: _s(info['duration']),
      cast: _s(info['cast']).isNotEmpty ? _s(info['cast']) : _s(info['actors']),
      director: _s(info['director']),
      backdrop: back,
      year: rd.length >= 4 ? rd.substring(0, 4) : '',
      rating: _rating(info['rating']),
    );
  }

  static Resolved movieUrl(Source s, VodItem m) =>
      Resolved(_Xt(s).movie(m.id, m.ext), {'User-Agent': kPlayerUa});

  // ----- Serije -----
  static Future<CatalogData<SeriesItem>> loadSeries(Source s, {bool force = false}) async {
    if (!force && _series.containsKey(s.id)) return _series[s.id]!;
    final x = _Xt(s);
    final res = await Future.wait<dynamic>([
      x.call('get_series_categories'),
      x.call('get_series'),
    ]);
    final raw = res[1];
    if (raw is! List) {
      throw Exception('Ova lista nema serije ili su podaci za prijavu pogrešni');
    }
    final items = <SeriesItem>[];
    for (final m in raw) {
      if (m is! Map) continue;
      final name = _s(m['name']);
      final rd = _s(m['releaseDate']).isNotEmpty ? _s(m['releaseDate']) : _s(m['release_date']);
      items.add(SeriesItem(
        id: _s(m['series_id']),
        name: name,
        cover: _s(m['cover']),
        plot: _s(m['plot']),
        rating: _rating(m['rating']),
        year: _year(name, rd.length >= 4 ? rd.substring(0, 4) : _s(m['year'])),
        added: int.tryParse(_s(m['last_modified'])) ?? 0,
        categoryId: _s(m['category_id']),
      ));
    }
    final d = CatalogData<SeriesItem>(_cats(res[0]), items);
    _series[s.id] = d;
    return d;
  }

  static Future<SeriesDetail> seriesDetail(Source s, String id) async {
    final j = await _Xt(s).call('get_series_info', '&series_id=$id');
    if (j is! Map) throw Exception('Nema podataka o seriji');
    final Map info = j['info'] is Map ? j['info'] as Map : const {};
    final seasons = <int, List<Episode>>{};

    void add(int season, dynamic e) {
      if (e is! Map) return;
      final Map inf = e['info'] is Map ? e['info'] as Map : const {};
      final ext = _s(e['container_extension']);
      seasons.putIfAbsent(season, () => <Episode>[]).add(Episode(
            id: _s(e['id']),
            title: _s(e['title']),
            season: season,
            number: int.tryParse(_s(e['episode_num'])) ?? 0,
            ext: ext.isEmpty ? 'mp4' : ext,
            plot: _s(inf['plot']),
            cover: _s(inf['movie_image']),
            duration: _s(inf['duration']),
          ));
    }

    final eps = j['episodes'];
    if (eps is Map) {
      eps.forEach((k, v) {
        final sn = int.tryParse('$k') ?? 0;
        if (v is List) {
          for (final e in v) {
            add(sn, e);
          }
        }
      });
    } else if (eps is List) {
      for (var i = 0; i < eps.length; i++) {
        final v = eps[i];
        if (v is List) {
          for (final e in v) {
            add(i + 1, e);
          }
        }
      }
    }
    for (final l in seasons.values) {
      l.sort((a, b) => a.number.compareTo(b.number));
    }
    return SeriesDetail(
      plot: _s(info['plot']),
      cover: _s(info['cover']),
      genre: _s(info['genre']),
      seasons: seasons,
    );
  }

  static Resolved episodeUrl(Source s, Episode e) =>
      Resolved(_Xt(s).episode(e.id, e.ext), {'User-Agent': kPlayerUa});

  static void clearCache(Source s) {
    _live.remove(s.id);
    _vod.remove(s.id);
    _series.remove(s.id);
  }
}
