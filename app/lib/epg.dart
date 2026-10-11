import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'models.dart';

class _EpgJob {
  const _EpgJob(this.bytes, this.nowMs);
  final Uint8List bytes;
  final int nowMs;
}

DateTime? _xmlTime(String s) {
  final m = RegExp(r'^(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})?\s*([+-]\d{4})?')
      .firstMatch(s.trim());
  if (m == null) return null;
  var d = DateTime.utc(
    int.parse(m[1]!),
    int.parse(m[2]!),
    int.parse(m[3]!),
    int.parse(m[4]!),
    int.parse(m[5]!),
    m[6] == null ? 0 : int.parse(m[6]!),
  );
  final off = m[7];
  if (off != null) {
    final sign = off[0] == '-' ? -1 : 1;
    final oh = int.parse(off.substring(1, 3));
    final om = int.parse(off.substring(3, 5));
    d = d.subtract(Duration(minutes: sign * (oh * 60 + om)));
  }
  return d;
}

String _unxml(String s) {
  var t = s.trim();
  if (t.startsWith('<![CDATA[') && t.endsWith(']]>')) {
    t = t.substring(9, t.length - 3);
  }
  return t
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&#39;', "'")
      .replaceAll('&amp;', '&');
}

/// Čita XMLTV i vraća programe po kanalu (ključ je mala slova). Radi u zasebnom isolate-u.
Map<String, List<Programme>> _parseXmltv(_EpgJob job) {
  List<int> data = job.bytes;
  if (data.length > 2 && data[0] == 0x1f && data[1] == 0x8b) {
    data = gzip.decode(data);
  }
  final text = utf8.decode(data, allowMalformed: true);
  final now = DateTime.fromMillisecondsSinceEpoch(job.nowMs, isUtc: true);
  final from = now.subtract(const Duration(hours: 3));
  final to = now.add(const Duration(hours: 48));

  final prog = RegExp(r'<programme\s([^>]*)>(.*?)</programme>', dotAll: true);
  final attr = RegExp(r'(\w+)="([^"]*)"');
  final titleRe = RegExp(r'<title[^>]*>(.*?)</title>', dotAll: true);
  final descRe = RegExp(r'<desc[^>]*>(.*?)</desc>', dotAll: true);

  final out = <String, List<Programme>>{};
  for (final m in prog.allMatches(text)) {
    String? start, stop, channel;
    for (final a in attr.allMatches(m.group(1)!)) {
      switch (a.group(1)) {
        case 'start':
          start = a.group(2);
          break;
        case 'stop':
          stop = a.group(2);
          break;
        case 'channel':
          channel = a.group(2);
          break;
      }
    }
    if (start == null || stop == null || channel == null) continue;
    final st = _xmlTime(start);
    final en = _xmlTime(stop);
    if (st == null || en == null) continue;
    if (en.isBefore(from) || st.isAfter(to)) continue;
    final body = m.group(2)!;
    final t = titleRe.firstMatch(body)?.group(1);
    final d = descRe.firstMatch(body)?.group(1);
    out
        .putIfAbsent(channel.toLowerCase(), () => <Programme>[])
        .add(Programme(_unxml(t ?? ''), _unxml(d ?? ''), st, en));
  }
  for (final l in out.values) {
    l.sort((a, b) => a.start.compareTo(b.start));
  }
  return out;
}

/// XMLTV preuzimanje i keširanje (jedan fajl je obično veliki, pa se učitava jednom).
class Epg {
  static final Map<String, Future<Map<String, List<Programme>>>> _jobs = {};
  static final Map<String, DateTime> _at = {};

  static Future<Map<String, List<Programme>>> load(String url) {
    final prev = _jobs[url];
    final at = _at[url];
    if (prev != null &&
        at != null &&
        DateTime.now().difference(at) < const Duration(hours: 6)) {
      return prev;
    }
    _at[url] = DateTime.now();
    final f = _fetch(url);
    _jobs[url] = f;
    f.then((_) {}, onError: (Object _) {
      _jobs.remove(url);
      _at.remove(url);
    });
    return f;
  }

  static Future<Map<String, List<Programme>>> _fetch(String url) async {
    final r = await http
        .get(Uri.parse(url), headers: {'User-Agent': 'Mozilla/5.0'})
        .timeout(const Duration(seconds: 180));
    if (r.statusCode != 200) throw Exception('EPG: HTTP ${r.statusCode}');
    return compute(
      _parseXmltv,
      _EpgJob(r.bodyBytes, DateTime.now().toUtc().millisecondsSinceEpoch),
    );
  }
}
