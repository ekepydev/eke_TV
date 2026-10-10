import 'package:flutter/material.dart';

import 'add_source_screen.dart';
import 'channels_screen.dart';
import 'models.dart';
import 'store.dart';

/// Početni ekran: spremljene liste. Odabereš listu i otvaraju se kanali.
class SourcesScreen extends StatefulWidget {
  const SourcesScreen({super.key});

  @override
  State<SourcesScreen> createState() => _SourcesScreenState();
}

class _SourcesScreenState extends State<SourcesScreen> {
  late List<Source> sources = Store.sources();

  Future<void> _add() async {
    final s = await Navigator.push<Source>(
      context,
      MaterialPageRoute(builder: (_) => const AddSourceScreen()),
    );
    if (s == null) return;
    setState(() => sources = [...sources, s]);
    await Store.saveSources(sources);
  }

  Future<void> _delete(Source s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Obrisati "${s.name}"?'),
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
    setState(() => sources = sources.where((x) => x.id != s.id).toList());
    await Store.saveSources(sources);
  }

  IconData _icon(Source s) {
    switch (s.type) {
      case 'xtream':
        return Icons.dns;
      case 'stalker':
        return Icons.settings_input_antenna;
      default:
        return Icons.link;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('STB Player'),
        actions: [
          IconButton(
            onPressed: _add,
            icon: const Icon(Icons.add),
            tooltip: 'Dodaj listu',
          ),
        ],
      ),
      body: sources.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Još nema nijedne liste.'),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    autofocus: true,
                    onPressed: _add,
                    icon: const Icon(Icons.add),
                    label: const Text('Dodaj listu'),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: sources.length,
              itemBuilder: (context, i) {
                final s = sources[i];
                return Card(
                  child: ListTile(
                    autofocus: i == 0,
                    leading: Icon(_icon(s)),
                    title: Text(s.name),
                    subtitle: Text(s.typeLabel),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      tooltip: 'Obriši',
                      onPressed: () => _delete(s),
                    ),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => ChannelsScreen(source: s)),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
