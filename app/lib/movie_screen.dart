import 'package:flutter/material.dart';

import 'models.dart';
import 'player_screen.dart';
import 'providers.dart';
import 'store.dart';
import 'util.dart';
import 'widgets.dart';

class MovieScreen extends StatefulWidget {
  const MovieScreen({super.key, required this.source, required this.item});
  final Source source;
  final VodItem item;

  @override
  State<MovieScreen> createState() => _MovieScreenState();
}

class _MovieScreenState extends State<MovieScreen> {
  VodInfo? info;
  bool loadingInfo = true;
  late bool fav = Store.favs().contains(_key);

  String get _key => 'M:${widget.source.id}:${widget.item.id}';

  @override
  void initState() {
    super.initState();
    _loadInfo();
  }

  Future<void> _loadInfo() async {
    try {
      final i = await Repo.vodInfo(widget.source, widget.item.id);
      if (mounted) setState(() => info = i);
    } catch (_) {
      // Opis nije obavezan.
    }
    if (mounted) setState(() => loadingInfo = false);
  }

  Future<void> _toggleFav() async {
    final f = Store.favs();
    fav ? f.remove(_key) : f.add(_key);
    await Store.saveFavs(f);
    setState(() => fav = !fav);
  }

  Future<void> _play({bool fromStart = false}) async {
    final s = widget.source;
    final m = widget.item;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PlayerScreen(
          items: [
            PlayItem(
              title: m.name,
              subtitle: m.year,
              historyKey: _key,
              resolve: () async => Repo.movieUrl(s, m),
              subtitleQuery: cleanTitle(m.name),
              year: int.tryParse(m.year),
            ),
          ],
          index: 0,
          fromStart: fromStart,
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.item;
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final pos = Store.pos(_key);
    final meta = <String>[
      if (m.year.isNotEmpty) m.year else if ((info?.year ?? '').isNotEmpty) info!.year,
      if ((info?.duration ?? '').isNotEmpty) info!.duration,
      if ((info?.genre ?? '').isNotEmpty) info!.genre,
    ].join('  ·  ');
    final rating = m.rating.isNotEmpty ? m.rating : (info?.rating ?? '');

    final poster = AspectRatio(
      aspectRatio: 0.68,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: NetImage(m.cover, cacheWidth: 600),
      ),
    );

    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(m.name, style: tt.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (rating.isNotEmpty)
              Text('★ $rating', style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.w700)),
            if (meta.isNotEmpty) Text(meta, style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
          ],
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            FilledButton.icon(
              autofocus: true,
              onPressed: () => _play(),
              icon: const Icon(Icons.play_arrow),
              label: Text(pos > 10000 ? 'Nastavi od ${fmtDur(Duration(milliseconds: pos))}' : 'Gledaj'),
            ),
            if (pos > 10000)
              OutlinedButton.icon(
                onPressed: () => _play(fromStart: true),
                icon: const Icon(Icons.replay),
                label: const Text('Od početka'),
              ),
            OutlinedButton.icon(
              onPressed: _toggleFav,
              icon: Icon(fav ? Icons.favorite : Icons.favorite_border, color: fav ? Colors.redAccent : null),
              label: Text(fav ? 'U favoritima' : 'Dodaj u favorite'),
            ),
          ],
        ),
        const SizedBox(height: 20),
        if (loadingInfo)
          const LinearProgressIndicator()
        else if ((info?.plot ?? '').isNotEmpty)
          Text(info!.plot, style: tt.bodyLarge)
        else if (m.plot.isNotEmpty)
          Text(m.plot, style: tt.bodyLarge),
        if ((info?.director ?? '').isNotEmpty) ...[
          const SizedBox(height: 14),
          Text('Režija: ${info!.director}', style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
        ],
        if ((info?.cast ?? '').isNotEmpty) ...[
          const SizedBox(height: 6),
          Text('Uloge: ${info!.cast}', style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
        ],
      ],
    );

    return Scaffold(
      appBar: AppBar(title: Text(m.name, maxLines: 1, overflow: TextOverflow.ellipsis)),
      body: LayoutBuilder(
        builder: (context, c) {
          final wide = c.maxWidth >= 700;
          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: wide
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(width: 260, child: poster),
                      const SizedBox(width: 28),
                      Expanded(child: details),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(child: SizedBox(width: 200, child: poster)),
                      const SizedBox(height: 20),
                      details,
                    ],
                  ),
          );
        },
      ),
    );
  }
}
