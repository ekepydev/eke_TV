import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';
import 'settings.dart';

/// Titlovi preko OpenSubtitles.com REST API-ja (potreban je besplatan API ključ korisnika).
class OpenSubs {
  static const _base = 'https://api.opensubtitles.com/api/v1';
  static String? _token;
  static String _tokenFor = '';

  static Map<String, String> _headers({bool auth = false}) => {
        'Api-Key': AppSettings.I.osKey,
        'User-Agent': 'STBPlayer v1.1',
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        if (auth && _token != null) 'Authorization': 'Bearer $_token',
      };

  static Future<void> _login() async {
    final st = AppSettings.I;
    if (st.osUser.isEmpty || st.osPass.isEmpty) return;
    final id = '${st.osKey}|${st.osUser}|${st.osPass}';
    if (_token != null && _tokenFor == id) return;
    final r = await http
        .post(
          Uri.parse('$_base/login'),
          headers: _headers(),
          body: jsonEncode({'username': st.osUser, 'password': st.osPass}),
        )
        .timeout(const Duration(seconds: 20));
    if (r.statusCode != 200) {
      throw Exception('OpenSubtitles prijava nije uspjela (HTTP ${r.statusCode})');
    }
    final j = jsonDecode(r.body);
    if (j is Map && j['token'] != null) {
      _token = '${j['token']}';
      _tokenFor = id;
    }
  }

  /// Traži titlove na bosanskom, hrvatskom i srpskom. Zadani jezik ide prvi.
  static Future<List<SubOption>> search(
    String query, {
    int? year,
    int? season,
    int? episode,
  }) async {
    final st = AppSettings.I;
    if (st.osKey.isEmpty) throw Exception('Nedostaje OpenSubtitles API ključ (Postavke → Titlovi)');
    final langs = <String>[st.subLang, ...['bs', 'hr', 'sr'].where((l) => l != st.subLang)];
    final qp = <String, String>{
      'languages': langs.join(','),
      'query': query,
      if (year != null) 'year': '$year',
      if (season != null) 'season_number': '$season',
      if (episode != null) 'episode_number': '$episode',
      'type': season != null ? 'episode' : 'movie',
    };
    final uri = Uri.parse('$_base/subtitles').replace(queryParameters: qp);
    final r = await http.get(uri, headers: _headers()).timeout(const Duration(seconds: 25));
    if (r.statusCode == 401 || r.statusCode == 403) {
      throw Exception('OpenSubtitles: pogrešan API ključ');
    }
    if (r.statusCode != 200) throw Exception('OpenSubtitles: HTTP ${r.statusCode}');
    final j = jsonDecode(utf8.decode(r.bodyBytes, allowMalformed: true));
    final out = <SubOption>[];
    final data = j is Map ? j['data'] : null;
    if (data is List) {
      for (final d in data) {
        if (d is! Map) continue;
        final a = d['attributes'];
        if (a is! Map) continue;
        final files = a['files'];
        if (files is! List || files.isEmpty || files.first is! Map) continue;
        final fid = int.tryParse('${(files.first as Map)['file_id']}');
        if (fid == null) continue;
        final lang = '${a['language'] ?? ''}'.toLowerCase();
        final rel = '${a['release'] ?? (files.first as Map)['file_name'] ?? ''}';
        out.add(SubOption(
          label: '${lang.toUpperCase()} · $rel',
          lang: lang,
          fileId: fid,
          downloads: int.tryParse('${a['download_count']}') ?? 0,
        ));
      }
    }
    int rank(String l) {
      final i = langs.indexOf(l);
      return i < 0 ? 99 : i;
    }

    out.sort((a, b) {
      final c = rank(a.lang).compareTo(rank(b.lang));
      return c != 0 ? c : b.downloads.compareTo(a.downloads);
    });
    return out;
  }

  /// Preuzima tekst titla (SRT).
  static Future<String> download(SubOption o) async {
    try {
      await _login();
    } catch (_) {
      // Bez prijave pokušavamo i dalje sa samim API ključem.
    }
    final r = await http
        .post(
          Uri.parse('$_base/download'),
          headers: _headers(auth: true),
          body: jsonEncode({'file_id': o.fileId, 'sub_format': 'srt'}),
        )
        .timeout(const Duration(seconds: 25));
    if (r.statusCode != 200) {
      throw Exception(r.statusCode == 406
          ? 'OpenSubtitles: dnevni limit preuzimanja je potrošen'
          : 'OpenSubtitles: preuzimanje nije uspjelo (HTTP ${r.statusCode})');
    }
    final j = jsonDecode(r.body);
    final link = j is Map ? '${j['link'] ?? ''}' : '';
    if (link.isEmpty) throw Exception('OpenSubtitles nije vratio link');
    final f = await http.get(Uri.parse(link)).timeout(const Duration(seconds: 30));
    if (f.statusCode != 200) throw Exception('Titl se ne može preuzeti (HTTP ${f.statusCode})');
    return _decode(f.bodyBytes);
  }

  /// UTF-8, a ako nije, Windows-1250 (stari titlovi za naše jezike).
  static String _decode(List<int> b) {
    try {
      return utf8.decode(b);
    } catch (_) {
      const map = <int, String>{
        0x8A: 'Š', 0x8E: 'Ž', 0x9A: 'š', 0x9E: 'ž',
        0xC8: 'Č', 0xE8: 'č', 0xC6: 'Ć', 0xE6: 'ć',
        0xD0: 'Đ', 0xF0: 'đ',
      };
      final sb = StringBuffer();
      for (final c in b) {
        sb.write(map[c] ?? String.fromCharCode(c));
      }
      return sb.toString();
    }
  }
}
