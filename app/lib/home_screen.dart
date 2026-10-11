import 'dart:io';

import 'package:flutter/material.dart';

import 'add_source_screen.dart';
import 'catalog_screen.dart';
import 'live_screen.dart';
import 'models.dart';
import 'providers.dart';
import 'settings.dart';
import 'settings_screen.dart';
import 'store.dart';

class _TabDef {
  const _TabDef(this.label, this.icon, this.build);
  final String label;
  final IconData icon;
  final Widget Function(Source s) build;
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Source> sources = Store.sources();
  Source? current;
  int tab = 0;

  @override
  void initState() {
    super.initState();
    if (sources.isNotEmpty) {
      final last = AppSettings.I.autoOpenLast ? AppSettings.I.lastSourceId : '';
      current = sources.where((s) => s.id == last).firstOrNull ?? sources.first;
    }
  }

  List<_TabDef> _tabs() {
    final s = current;
    return [
      _TabDef('TV', Icons.live_tv, (s) => LiveTab(key: ValueKey('live-${s.id}'), source: s)),
      if (s != null && s.hasVod)
        _TabDef('Filmovi', Icons.movie_outlined,
            (s) => CatalogTab(key: ValueKey('mov-${s.id}'), source: s, series: false)),
      if (s != null && s.hasVod)
        _TabDef('Serije', Icons.video_library_outlined,
            (s) => CatalogTab(key: ValueKey('ser-${s.id}'), source: s, series: true)),
      _TabDef('Postavke', Icons.settings_outlined, (_) => const SettingsTab()),
    ];
  }

  void _select(Source s) {
    AppSettings.I.lastSourceId = s.id;
    AppSettings.I.save(notify: false);
    setState(() {
      current = s;
      tab = 0;
    });
  }

  Future<void> _add() async {
    final s = await Navigator.push<Source>(
      context,
      MaterialPageRoute(builder: (_) => const AddSourceScreen()),
    );
    if (s == null) return;
    sources = [...sources, s];
    await Store.saveSources(sources);
    _select(s);
  }

  Future<void> _delete() async {
    final s = current;
    if (s == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Obrisati listu "${s.name}"?'),
        content: const Text('Brišu se samo podaci o listi na ovom uređaju.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Ne')),
          FilledButton(
            autofocus: true,
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Obriši'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    if (s.type == 'file') {
      try {
        File(s.file).deleteSync();
      } catch (_) {}
    }
    Repo.clearCache(s);
    sources = sources.where((x) => x.id != s.id).toList();
    await Store.saveSources(sources);
    setState(() {
      current = sources.isEmpty ? null : sources.first;
      tab = 0;
    });
  }

  Widget _sourceMenu() {
    return PopupMenuButton<String>(
      tooltip: 'Liste',
      onSelected: (v) {
        if (v == '__add') {
          _add();
        } else if (v == '__del') {
          _delete();
        } else {
          _select(sources.firstWhere((s) => s.id == v));
        }
      },
      itemBuilder: (_) => [
        for (final s in sources)
          CheckedPopupMenuItem<String>(
            value: s.id,
            checked: s.id == current?.id,
            child: Text(s.name),
          ),
        const PopupMenuDivider(),
        const PopupMenuItem(value: '__add', child: Text('Dodaj listu…')),
        if (current != null) const PopupMenuItem(value: '__del', child: Text('Obriši ovu listu')),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.dns_outlined, size: 20),
            const SizedBox(width: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 160),
              child: Text(current?.name ?? 'Liste', overflow: TextOverflow.ellipsis),
            ),
            const Icon(Icons.arrow_drop_down),
          ],
        ),
      ),
    );
  }

  Widget _welcome() {
    final tt = Theme.of(context).textTheme;
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.play_circle_fill, size: 72, color: Theme.of(context).colorScheme.primary),
                const SizedBox(height: 16),
                Text('STB Player', style: tt.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                const Text(
                  'Dodaj svoju IPTV listu: M3U link ili fajl, Xtream pristup ili portal s MAC adresom.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  autofocus: true,
                  onPressed: _add,
                  icon: const Icon(Icons.add),
                  label: const Text('Dodaj listu'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = current;
    if (s == null) return _welcome();
    final tabs = _tabs();
    if (tab >= tabs.length) tab = 0;
    final body = KeyedSubtree(key: ValueKey('${s.id}-$tab'), child: tabs[tab].build(s));
    final wide = MediaQuery.sizeOf(context).width >= 760;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 12,
        title: Row(
          children: [
            Icon(Icons.play_circle_fill, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            const Text('STB Player', style: TextStyle(fontWeight: FontWeight.w800)),
          ],
        ),
        actions: [_sourceMenu(), const SizedBox(width: 4)],
      ),
      body: wide
          ? Row(
              children: [
                NavigationRail(
                  selectedIndex: tab,
                  onDestinationSelected: (i) => setState(() => tab = i),
                  labelType: NavigationRailLabelType.all,
                  destinations: [
                    for (final t in tabs)
                      NavigationRailDestination(icon: Icon(t.icon), label: Text(t.label)),
                  ],
                ),
                const VerticalDivider(width: 1),
                Expanded(child: body),
              ],
            )
          : body,
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: tab,
              onDestinationSelected: (i) => setState(() => tab = i),
              destinations: [
                for (final t in tabs) NavigationDestination(icon: Icon(t.icon), label: t.label),
              ],
            ),
    );
  }
}
