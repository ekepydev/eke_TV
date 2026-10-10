import 'package:flutter/material.dart';

import 'models.dart';
import 'player_screen.dart';
import 'providers.dart';
import 'store.dart';

class ChannelsScreen extends StatefulWidget {
  const ChannelsScreen({super.key, required this.source});
  final Source source;

  @override
  State<ChannelsScreen> createState() => _ChannelsScreenState();
}

class _ChannelsScreenState extends State<ChannelsScreen> {
  List<Channel> all = [];
  List<Channel> shown = [];
  List<String> groups = [];
  Set<String> favs = Store.favs();
  String query = '';
  String group = '';
  bool loading = true;
  String? error;

  String _key(Channel c) => '${widget.source.id}:${c.id}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final c = await Repo.loadChannels(widget.source);
      if (!mounted) return;
      setState(() {
        all = c;
        groups = (c.map((x) => x.group).toSet().toList()..sort());
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
    shown = all.where((c) {
      if (q.isNotEmpty && !c.name.toLowerCase().contains(q)) return false;
      if (group.isEmpty) return true;
      if (group == '__fav') return favs.contains(_key(c));
      return c.group == group;
    }).toList();
  }

  Future<void> _toggleFav(Channel c) async {
    final k = _key(c);
    setState(() {
      favs.contains(k) ? favs.remove(k) : favs.add(k);
      if (group == '__fav') _apply();
    });
    await Store.saveFavs(favs);
  }

  Widget _body() {
    if (loading) return const Center(child: CircularProgressIndicator());
    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton.icon(
                autofocus: true,
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: const Text('Pokušaj ponovo'),
              ),
            ],
          ),
        ),
      );
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
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
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: DropdownButton<String>(
                  value: group,
                  isExpanded: true,
                  items: [
                    const DropdownMenuItem(value: '', child: Text('Sve kategorije')),
                    const DropdownMenuItem(value: '__fav', child: Text('★ Favoriti')),
                    ...groups.map((g) => DropdownMenuItem(
                          value: g,
                          child: Text(g, overflow: TextOverflow.ellipsis),
                        )),
                  ],
                  onChanged: (v) => setState(() {
                    group = v ?? '';
                    _apply();
                  }),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text('${shown.length} kanala', style: Theme.of(context).textTheme.bodySmall),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: shown.length,
            itemBuilder: (context, i) {
              final c = shown[i];
              final fav = favs.contains(_key(c));
              return ListTile(
                autofocus: i == 0,
                leading: SizedBox(
                  width: 44,
                  height: 44,
                  child: c.logo.isEmpty
                      ? const Icon(Icons.tv)
                      : Image.network(
                          c.logo,
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => const Icon(Icons.tv),
                        ),
                ),
                title: Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(c.group, maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: IconButton(
                  icon: Icon(
                    fav ? Icons.star : Icons.star_border,
                    color: fav ? Colors.amber : null,
                  ),
                  tooltip: 'Favorit',
                  onPressed: () => _toggleFav(c),
                ),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PlayerScreen(
                      source: widget.source,
                      channels: shown,
                      index: i,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.source.name),
        actions: [
          IconButton(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
            tooltip: 'Osvježi',
          ),
        ],
      ),
      body: _body(),
    );
  }
}
