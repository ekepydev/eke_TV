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
  });

  final String id;
  final String name;

  /// 'm3u', 'xtream' ili 'stalker'
  final String type;
  final String url;
  final String server;
  final String user;
  final String pass;
  final String portal;
  final String mac;

  String get typeLabel {
    switch (type) {
      case 'm3u':
        return 'M3U link';
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
}

class Resolved {
  const Resolved(this.url, this.headers);
  final String url;
  final Map<String, String> headers;
}
