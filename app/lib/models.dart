class Source {
  const Source({
    required this.id,
    required this.name,
    required this.type,
    this.url = '',
    this.server = '',
    this.user = '',
    this.pass = '',
    this.portal = '',
    this.mac = '',
    this.file = '',
    this.xmltv = '',
  });

  final String id;
  final String name;

  /// 'm3u', 'file', 'xtream' ili 'stalker'
  final String type;
  final String url;
  final String server;
  final String user;
  final String pass;
  final String portal;
  final String mac;

  /// Putanja do spremljene M3U liste (type == 'file').
  final String file;

  /// Opcionalni XMLTV (EPG) URL za M3U liste.
  final String xmltv;

  bool get hasVod => type == 'xtream';

  String get typeLabel {
    switch (type) {
      case 'm3u':
        return 'M3U link';
      case 'file':
        return 'M3U fajl';
      case 'xtream':
        return 'Xtream';
      case 'stalker':
        return 'Portal + MAC';
      default:
        return type;
    }
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type,
        'url': url,
        'server': server,
        'user': user,
        'pass': pass,
        'portal': portal,
        'mac': mac,
        'file': file,
        'xmltv': xmltv,
      };

  factory Source.fromJson(Map<String, dynamic> j) => Source(
        id: j['id'] as String,
        name: (j['name'] as String?) ?? '',
        type: (j['type'] as String?) ?? 'm3u',
        url: (j['url'] as String?) ?? '',
        server: (j['server'] as String?) ?? '',
        user: (j['user'] as String?) ?? '',
        pass: (j['pass'] as String?) ?? '',
        portal: (j['portal'] as String?) ?? '',
        mac: (j['mac'] as String?) ?? '',
        file: (j['file'] as String?) ?? '',
        xmltv: (j['xmltv'] as String?) ?? '',
      );
}

class Channel {
  const Channel({
    required this.id,
    required this.name,
    this.logo = '',
    this.group = 'Ostalo',
    this.url,
    this.cmd,
    this.num = 0,
    this.epgId = '',
  });

  final String id;
  final String name;
  final String logo;
  final String group;

  /// Direktan link (M3U / Xtream). Kod Stalkera je null, link se traži pri puštanju.
  final String? url;

  /// Stalker "cmd" za create_link.
  final String? cmd;
  final int num;

  /// tvg-id iz M3U liste (za XMLTV EPG).
  final String epgId;
}

class Category {
  const Category(this.id, this.name);
  final String id;
  final String name;
}

/// Zajednički prikaz za filmove i serije (poster u mreži).
abstract class CatalogItem {
  String get id;
  String get name;
  String get cover;
  String get plot;
  String get rating;
  String get year;
  int get added;
  String get categoryId;
}

class VodItem implements CatalogItem {
  const VodItem({
    required this.id,
    required this.name,
    this.cover = '',
    this.plot = '',
    this.rating = '',
    this.year = '',
    this.added = 0,
    this.categoryId = '',
    this.ext = 'mp4',
  });

  @override
  final String id;
  @override
  final String name;
  @override
  final String cover;
  @override
  final String plot;
  @override
  final String rating;
  @override
  final String year;
  @override
  final int added;
  @override
  final String categoryId;
  final String ext;
}

class SeriesItem implements CatalogItem {
  const SeriesItem({
    required this.id,
    required this.name,
    this.cover = '',
    this.plot = '',
    this.rating = '',
    this.year = '',
    this.added = 0,
    this.categoryId = '',
  });

  @override
  final String id;
  @override
  final String name;
  @override
  final String cover;
  @override
  final String plot;
  @override
  final String rating;
  @override
  final String year;
  @override
  final int added;
  @override
  final String categoryId;
}

class Episode {
  const Episode({
    required this.id,
    required this.title,
    required this.season,
    required this.number,
    this.ext = 'mp4',
    this.plot = '',
    this.cover = '',
    this.duration = '',
  });

  final String id;
  final String title;
  final int season;
  final int number;
  final String ext;
  final String plot;
  final String cover;
  final String duration;
}

class SeriesDetail {
  const SeriesDetail({required this.plot, required this.cover, required this.genre, required this.seasons});
  final String plot;
  final String cover;
  final String genre;
  final Map<int, List<Episode>> seasons;
}

class Programme {
  const Programme(this.title, this.desc, this.start, this.stop);
  final String title;
  final String desc;
  final DateTime start;
  final DateTime stop;

  double progress(DateTime now) {
    final total = stop.difference(start).inSeconds;
    if (total <= 0) return 0;
    return (now.difference(start).inSeconds / total).clamp(0.0, 1.0).toDouble();
  }
}

class Resolved {
  const Resolved(this.url, this.headers);
  final String url;
  final Map<String, String> headers;
}

/// Jedna stavka u plejeru: kanal, film ili epizoda.
class PlayItem {
  const PlayItem({
    required this.title,
    required this.resolve,
    this.subtitle = '',
    this.live = false,
    this.num = 0,
    this.historyKey,
    this.epg,
    this.subtitleQuery,
    this.year,
    this.season,
    this.episode,
  });

  final String title;
  final String subtitle;
  final Future<Resolved> Function() resolve;
  final bool live;
  final int num;
  final String? historyKey;
  final Future<List<Programme>> Function()? epg;
  final String? subtitleQuery;
  final int? year;
  final int? season;
  final int? episode;
}

class CatalogData<T extends CatalogItem> {
  const CatalogData(this.cats, this.items);
  final List<Category> cats;
  final List<T> items;
}

class VodInfo {
  const VodInfo({
    this.plot = '',
    this.genre = '',
    this.duration = '',
    this.cast = '',
    this.director = '',
    this.backdrop = '',
    this.year = '',
    this.rating = '',
  });

  final String plot;
  final String genre;
  final String duration;
  final String cast;
  final String director;
  final String backdrop;
  final String year;
  final String rating;
}

class SubOption {
  const SubOption({
    required this.label,
    required this.lang,
    required this.fileId,
    this.downloads = 0,
  });

  final String label;
  final String lang;
  final int fileId;
  final int downloads;
}
