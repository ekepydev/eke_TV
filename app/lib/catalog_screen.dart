import 'package:flutter/material.dart';

import 'models.dart';
import 'movie_screen.dart';
import 'providers.dart';
import 'series_screen.dart';
import 'store.dart';
import 'widgets.dart';

/// Filmovi i serije: glavna kategorija je "Novo", a ostale kategorije biraš u zaglavlju.
class CatalogTab extends StatefulWidget {
  const CatalogTab({super.key, required this.source, required this.series});
  final Source source;
  final bool series;

  @override
  State<CatalogTab> createState() => _CatalogTabState();
}

class _CatalogTabState extends State<CatalogTab> {
  CatalogData<CatalogItem>? data;
  List<CatalogItem> shown = [];
  Set<String> favs = Store.favs();
  String query = '';
  String cat = '__new';
  bool loading = true;
  String? error;

  String get _p => widget.series ? 'S' : 'M';
  String _fk(CatalogItem x) => '$_p:${widget.source.id}:${x.id}';

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
      final CatalogData<CatalogItem> d = widget.series
          ? await Repo.loadSeries(widget.source, force: force)
          : await Repo.loadMovies(widget.source, force: force);
      if (!mounted) return;
      setState(() {
        data = d;
        cat = '__new';
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
    final d = data;
    if (d == null) return;
    final q = query.toLowerCase();
    Iterable<CatalogItem> it = d.items;
    if (q.isNotEmpty) it = it.where((x) => x.name.toLowerCase().contains(q));
    List<CatalogItem> out;
    if (cat == '__new') {
      out = it.toList()..sort((a, b) => b.added.compareTo(a.added));
      if (q.isEmpty && out.length > 120) out = out.sublist(0, 120);
    } else if (cat == '__all') {
      out = it.toList()..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    } else if (cat == '__fav') {
      out = it.where((x) => favs.contains(_fk(x))).toList();
    } else if (cat == '__recent') {
      final order = <String, int>{};
      final r = Store.recent();
      for (var i = 0; i < r.length; i++) {
        order[r[i]] = i;
      }
      out = it.where((x) => order.containsKey(_fk(x))).toList()
        ..sort((a, b) => order[_fk(a)]!.compareTo(order[_fk(b)]!));
    } else {
      out = it.where((x) => x.categoryId == cat).toList();
    }
    shown = out;
  }

  void _setCat(String c) => setState(() {
        cat = c;
        _apply();
      });

  Future<void> _open(CatalogItem x) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => widget.series
            ? SeriesScreen(source: widget.source, item: x as SeriesItem)
            : MovieScreen(source: widget.source, item: x as VodItem),
      ),
    );
    if (!mounted) return;
    setState(() {
      favs = Store.favs();
      if (cat == '__fav' || cat == '__recent') _apply();
    });
  }

  Future<void> _quickFav(CatalogItem x) async {
    final k = _fk(x);
    setState(() {
      favs.contains(k) ? favs.remove(k) : favs.add(k);
      if (cat == '__fav') _apply();
    });
    await Store.saveFavs(favs);
  }

  Widget _chips() {
    final d = data!;
    final entries = <MapEntry<String, String>>[
      const MapEntry('__new', 'Novo'),
      const MapEntry('__all', 'Sve'),
      const MapEntry('__recent', 'Nedavno'),
      const MapEntry('__fav', '★ Favoriti'),
      ...d.cats.map((c) => MapEntry(c.id, c.name)),
    ];
    return SizedBox(
      height: 52,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: entries.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final e = entries[i];
          return ChoiceChip(
            label: Text(e.value),
            selected: cat == e.key,
            onSelected: (_) => _setCat(e.key),
          );
        },
      ),
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
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: InputDecoration(
                    hintText: widget.series ? 'Pretraga serija…' : 'Pretraga filmova…',
                    prefixIcon: const Icon(Icons.search),
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (v) => setState(() {
                    query = v;
                    _apply();
                  }),
                ),
              ),
              IconButton(
                tooltip: 'Osvježi',
                onPressed: () => _load(force: true),
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
        ),
        _chips(),
        Expanded(
          child: shown.isEmpty
              ? MessageView(
                  icon: Icons.movie_filter_outlined,
                  text: cat == '__fav'
                      ? 'Još nema favorita. Dugo pritisni poster ili otvori naslov.'
                      : (cat == '__recent' ? 'Još ništa nije gledano.' : 'Nema rezultata.'),
                )
              : GridView.builder(
                  padding: const EdgeInsets.all(12),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 170,
                    childAspectRatio: 0.56,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  itemCount: shown.length,
                  itemBuilder: (context, i) {
                    final x = shown[i];
                    return PosterCard(
                      autofocus: i == 0,
                      name: x.name,
                      cover: x.cover,
                      subtitle: x.year,
                      rating: x.rating,
                      fav: favs.contains(_fk(x)),
                      onTap: () => _open(x),
                      onLongPress: () => _quickFav(x),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
