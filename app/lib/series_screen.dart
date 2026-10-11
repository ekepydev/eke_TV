import 'package:flutter/material.dart';

import 'models.dart';
import 'player_screen.dart';
import 'providers.dart';
import 'store.dart';
import 'util.dart';
import 'widgets.dart';

class SeriesScreen extends StatefulWidget {
  const SeriesScreen({super.key, required this.source, required this.item});
  final Source source;
  final SeriesItem item;

  @override
  State<SeriesScreen> createState() => _SeriesScreenState();
}

class _SeriesScreenState extends State<SeriesScreen> {
  SeriesDetail? detail;
  String? error;
  bool loading = true;
  int season = 0;
  late bool fav = Store.favs().contains(_key);

  String get _key => 'S:${widget.source.id}:${widget.item.id}';

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
      final d = await Repo.seriesDetail(widget.source, widget.item.id);
      if (!mounted) return;
      final keys = d.seasons.keys.toList()..sort();
      setState(() {
        detail = d;
        season = keys.isEmpty ? 0 : keys.first;
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

  Future<void> _toggleFav() async {
    final f = Store.favs();
    fav ? f.remove(_key) : f.add(_key);
    await Store.saveFavs(f);
    setState(() => fav = !fav);
  }

  Future<void> _play(Episode start) async {
    final d = detail!;
    final s = widget.source;
    final seasons = d.seasons.keys.toList()..sort();
    final flat = <Episode>[];
    for (final sn in seasons) {
      flat.addAll(d.seasons[sn]!);
    }
    final items = <PlayItem>[];
    for (final e in flat) {
      final code = 'S${two(e.season)}E${two(e.number)}';
      items.add(PlayItem(
        title: widget.item.name,
        subtitle: e.title.isEmpty ? code : '$code · ${e.title}',
        historyKey: 'E:${s.id}:${e.id}',
        resolve: () async => Repo.episodeUrl(s, e),
        subtitleQuery: cleanTitle(widget.item.name),
        season: e.season,
        episode: e.number,
      ));
    }
    final idx = flat.indexWhere((e) => e.id == start.id);
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => PlayerScreen(items: items, index: idx < 0 ? 0 : idx)),
    );
    if (mounted) {
      await Store.pushRecent(_key);
      setState(() {});
    }
  }

  Widget _header() {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final it = widget.item;
    final plot = (detail?.plot ?? '').isNotEmpty ? detail!.plot : it.plot;
    final cover = it.cover.isNotEmpty ? it.cover : (detail?.cover ?? '');
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 120,
          child: AspectRatio(
            aspectRatio: 0.68,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: NetImage(cover, cacheWidth: 400),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(it.name, style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 12,
                children: [
                  if (it.rating.isNotEmpty)
                    Text('★ ${it.rating}', style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.w700)),
                  if (it.year.isNotEmpty) Text(it.year, style: TextStyle(color: cs.onSurfaceVariant)),
                  if ((detail?.genre ?? '').isNotEmpty)
                    Text(detail!.genre, style: TextStyle(color: cs.onSurfaceVariant)),
                ],
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _toggleFav,
                icon: Icon(fav ? Icons.favorite : Icons.favorite_border, color: fav ? Colors.redAccent : null),
                label: Text(fav ? 'U favoritima' : 'Dodaj u favorite'),
              ),
              if (plot.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(plot, maxLines: 6, overflow: TextOverflow.ellipsis),
              ],
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget body;
    if (loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (error != null) {
      body = MessageView(
        icon: Icons.cloud_off,
        text: error!,
        actionLabel: 'Pokušaj ponovo',
        onAction: _load,
      );
    } else {
      final d = detail!;
      final seasons = d.seasons.keys.toList()..sort();
      final eps = d.seasons[season] ?? const <Episode>[];
      final cs = Theme.of(context).colorScheme;
      body = ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _header(),
          const SizedBox(height: 16),
          if (seasons.isEmpty)
            const MessageView(icon: Icons.video_library_outlined, text: 'Nema epizoda za ovu seriju.')
          else ...[
            SizedBox(
              height: 48,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: seasons.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, i) => ChoiceChip(
                  label: Text('Sezona ${seasons[i]}'),
                  selected: season == seasons[i],
                  onSelected: (_) => setState(() => season = seasons[i]),
                ),
              ),
            ),
            const SizedBox(height: 8),
            for (var i = 0; i < eps.length; i++)
              Builder(builder: (context) {
                final e = eps[i];
                final pos = Store.pos('E:${widget.source.id}:${e.id}');
                return ListTile(
                  autofocus: i == 0,
                  leading: SizedBox(
                    width: 96,
                    height: 56,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: e.cover.isNotEmpty
                          ? NetImage(e.cover, cacheWidth: 300, icon: Icons.play_circle_outline)
                          : Container(
                              color: cs.surfaceContainerHighest,
                              alignment: Alignment.center,
                              child: Text('${e.number}', style: Theme.of(context).textTheme.titleLarge),
                            ),
                    ),
                  ),
                  title: Text(
                    '${e.number}. ${e.title.isEmpty ? 'Epizoda ${e.number}' : e.title}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    [
                      if (e.duration.isNotEmpty) e.duration,
                      if (pos > 10000) 'nastavi od ${fmtDur(Duration(milliseconds: pos))}',
                    ].join(' · '),
                  ),
                  trailing: const Icon(Icons.play_arrow),
                  onTap: () => _play(e),
                );
              }),
          ],
        ],
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(widget.item.name, maxLines: 1, overflow: TextOverflow.ellipsis)),
      body: body,
    );
  }
}
