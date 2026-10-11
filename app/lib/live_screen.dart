import 'package:flutter/material.dart';

import 'models.dart';
import 'player_screen.dart';
import 'providers.dart';
import 'store.dart';
import 'util.dart';
import 'widgets.dart';

/// TV uživo: kategorije, pretraga, favoriti, nedavno i program (EPG) uz svaki kanal.
class LiveTab extends StatefulWidget {
  const LiveTab({super.key, required this.source});
  final Source source;

  @override
  State<LiveTab> createState() => _LiveTabState();
}

class _LiveTabState extends State<LiveTab> {
  List<Channel> all = [];
  List<Channel> shown = [];
  List<String> groups = [];
  Set<String> favs = Store.favs();
  String query = '';
  String group = '';
  bool loading = true;
  String? error;

  String _fk(Channel c) => 'L:${widget.source.id}:${c.id}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool force = false}) async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final c = await Repo.loadChannels(widget.source, force: force);
      if (!mounted) return;
      setState(() {
        all = c;
        groups = c.map((x) => x.group).toSet().toList()..sort();
        group = '';
        _apply();
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        error = errMsg(e);
        loading = false;
      });
    }
  }

  void _apply() {
    final q = query.toLowerCase();
    bool match(Channel c) => q.isEmpty || c.name.toLowerCase().contains(q);
    if (group == '__recent') {
      final order = <String, int>{};
      final r = Store.recent();
      for (var i = 0; i < r.length; i++) {
        order[r[i]] = i;
      }
      shown = all.where((c) => order.containsKey(_fk(c)) && match(c)).toList()
        ..sort((a, b) => order[_fk(a)]!.compareTo(order[_fk(b)]!));
      return;
    }
    shown = all.where((c) {
      if (!match(c)) return false;
      if (group.isEmpty) return true;
      if (group == '__fav') return favs.contains(_fk(c));
      return c.group == group;
    }).toList();
  }

  Future<void> _toggleFav(Channel c) async {
    final k = _fk(c);
    setState(() {
      favs.contains(k) ? favs.remove(k) : favs.add(k);
      if (group == '__fav') _apply();
    });
    await Store.saveFavs(favs);
  }

  List<PlayItem> _items() {
    final s = widget.source;
    return shown
        .map((c) => PlayItem(
              title: c.name,
              subtitle: c.group,
              live: true,
              num: c.num,
              historyKey: _fk(c),
              resolve: () => Repo.resolve(s, c),
              epg: () => Repo.epg(s, c),
            ))
        .toList();
  }

  Future<void> _open(int i) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => PlayerScreen(items: _items(), index: i)),
    );
    if (mounted) {
      setState(() {
        if (group == '__recent') _apply();
      });
    }
  }

  void _setGroup(String g) => setState(() {
        group = g;
        _apply();
      });

  Widget _toolbar(bool wide) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Pretraga kanala…',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) => setState(() {
                query = v;
                _apply();
              }),
            ),
          ),
          if (!wide) ...[
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: DropdownButton<String>(
                value: group,
                isExpanded: true,
                items: [
                  const DropdownMenuItem(value: '', child: Text('Svi kanali')),
                  const DropdownMenuItem(value: '__recent', child: Text('Nedavno')),
                  const DropdownMenuItem(value: '__fav', child: Text('★ Favoriti')),
                  ...groups.map((g) => DropdownMenuItem(
                        value: g,
                        child: Text(g, overflow: TextOverflow.ellipsis),
                      )),
                ],
                onChanged: (v) => _setGroup(v ?? ''),
              ),
            ),
          ],
          IconButton(
            tooltip: 'Osvježi listu',
            onPressed: () {
              Repo.clearCache(widget.source);
              _load(force: true);
            },
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
    );
  }

  Widget _groupsPane() {
    Widget tile(String id, String label, IconData icon) => ListTile(
          dense: true,
          selected: group == id,
          leading: Icon(icon, size: 20),
          title: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
          onTap: () => _setGroup(id),
        );
    return ListView(
      children: [
        tile('', 'Svi kanali', Icons.live_tv),
        tile('__recent', 'Nedavno', Icons.history),
        tile('__fav', 'Favoriti', Icons.star),
        const Divider(height: 8),
        for (final g in groups) tile(g, g, Icons.folder_outlined),
      ],
    );
  }

  Widget _list() {
    if (shown.isEmpty) {
      return MessageView(
        icon: group == '__fav' ? Icons.star_border : Icons.search_off,
        text: group == '__fav'
            ? 'Još nema favorita. Pritisni zvjezdicu uz kanal.'
            : (group == '__recent' ? 'Još ništa nije gledano.' : 'Nema kanala.'),
      );
    }
    final cs = Theme.of(context).colorScheme;
    return ListView.builder(
      itemCount: shown.length,
      itemBuilder: (context, i) {
        final c = shown[i];
        final fav = favs.contains(_fk(c));
        return ListTile(
          autofocus: i == 0,
          leading: SizedBox(
            width: 52,
            height: 52,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Container(
                color: cs.surfaceContainerHighest,
                padding: const EdgeInsets.all(4),
                child: NetImage(c.logo, fit: BoxFit.contain, icon: Icons.tv, cacheWidth: 120),
              ),
            ),
          ),
          title: Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: _NowNext(key: ValueKey('${widget.source.id}/${c.id}'), source: widget.source, channel: c),
          trailing: IconButton(
            icon: Icon(fav ? Icons.star : Icons.star_border, color: fav ? Colors.amber : null),
            tooltip: 'Favorit',
            onPressed: () => _toggleFav(c),
          ),
          onTap: () => _open(i),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    if (error != null) {
      return MessageView(
        icon: Icons.cloud_off,
        text: error!,
        actionLabel: 'Pokušaj ponovo',
        onAction: () => _load(force: true),
      );
    }
    final wide = MediaQuery.sizeOf(context).width >= 900;
    if (!wide) {
      return Column(children: [_toolbar(false), Expanded(child: _list())]);
    }
    return Row(
      children: [
        SizedBox(width: 250, child: _groupsPane()),
        const VerticalDivider(width: 1),
        Expanded(child: Column(children: [_toolbar(true), Expanded(child: _list())])),
      ],
    );
  }
}

/// Šta se trenutno emituje (iz EPG-a), ili kategorija ako EPG nije dostupan.
class _NowNext extends StatefulWidget {
  const _NowNext({super.key, required this.source, required this.channel});
  final Source source;
  final Channel channel;

  @override
  State<_NowNext> createState() => _NowNextState();
}

class _NowNextState extends State<_NowNext> {
  late final Future<List<Programme>> f = Repo.epg(widget.source, widget.channel);

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall;
    return FutureBuilder<List<Programme>>(
      future: f,
      builder: (context, snap) {
        final now = DateTime.now();
        final list = snap.data ?? const <Programme>[];
        final i = list.indexWhere((p) => !now.isBefore(p.start) && now.isBefore(p.stop));
        if (i < 0) {
          return Text(widget.channel.group, maxLines: 1, overflow: TextOverflow.ellipsis, style: style);
        }
        final p = list[i];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${hm(p.start)}  ${p.title}', maxLines: 1, overflow: TextOverflow.ellipsis, style: style),
            const SizedBox(height: 3),
            LinearProgressIndicator(value: p.progress(now), minHeight: 3),
          ],
        );
      },
    );
  }
}
