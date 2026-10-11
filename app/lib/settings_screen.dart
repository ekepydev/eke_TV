import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'settings.dart';

class SettingsTab extends StatefulWidget {
  const SettingsTab({super.key});

  @override
  State<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<SettingsTab> {
  final st = AppSettings.I;
  late final osKey = TextEditingController(text: st.osKey);
  late final osUser = TextEditingController(text: st.osUser);
  late final osPass = TextEditingController(text: st.osPass);
  late final xmltv = TextEditingController(text: st.xmltv);

  @override
  void dispose() {
    osKey.dispose();
    osUser.dispose();
    osPass.dispose();
    xmltv.dispose();
    super.dispose();
  }

  Widget _section(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 22, 16, 8),
        child: Text(
          t.toUpperCase(),
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w800,
                letterSpacing: 1,
              ),
        ),
      );

  Widget _pad(Widget w) => Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6), child: w);

  Future<void> _rebind(KeyAct a) async {
    final k = await showDialog<LogicalKeyboardKey>(
      context: context,
      builder: (_) => _KeyCaptureDialog(label: a.label),
    );
    if (k != null) {
      await st.setKey(a.id, k);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: st,
      builder: (context, _) {
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.only(bottom: 40),
              children: [
                _section('Izgled'),
                _pad(SegmentedButton<ThemeMode>(
                  segments: const [
                    ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode), label: Text('Tamni')),
                    ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode), label: Text('Svijetli')),
                    ButtonSegment(value: ThemeMode.system, icon: Icon(Icons.brightness_auto), label: Text('Sistem')),
                  ],
                  selected: {st.themeMode},
                  onSelectionChanged: (s) {
                    st.themeMode = s.first;
                    st.save();
                  },
                )),
                _section('Titlovi'),
                _pad(SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'bs', label: Text('Bosanski')),
                    ButtonSegment(value: 'hr', label: Text('Hrvatski')),
                    ButtonSegment(value: 'sr', label: Text('Srpski')),
                  ],
                  selected: {st.subLang},
                  onSelectionChanged: (s) {
                    st.subLang = s.first;
                    st.save();
                  },
                )),
                SwitchListTile(
                  title: const Text('Automatski uključi titl'),
                  subtitle: const Text('Za filmove i serije, na zadanom jeziku (ako postoji)'),
                  value: st.autoSubs,
                  onChanged: (v) {
                    st.autoSubs = v;
                    st.save();
                  },
                ),
                _pad(TextField(
                  controller: osKey,
                  decoration: const InputDecoration(
                    labelText: 'OpenSubtitles API ključ',
                    helperText: 'Besplatno na opensubtitles.com (Consumers → API). Bez ključa rade samo titlovi ugrađeni u film.',
                    helperMaxLines: 3,
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (v) {
                    st.osKey = v.trim();
                    st.save(notify: false);
                  },
                )),
                _pad(Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: osUser,
                        decoration: const InputDecoration(
                          labelText: 'OpenSubtitles korisnik',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (v) {
                          st.osUser = v.trim();
                          st.save(notify: false);
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: osPass,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'Lozinka',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (v) {
                          st.osPass = v;
                          st.save(notify: false);
                        },
                      ),
                    ),
                  ],
                )),
                _section('Program (EPG)'),
                _pad(TextField(
                  controller: xmltv,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    labelText: 'Zadani XMLTV link',
                    helperText: 'Koristi se za M3U liste koje nemaju svoj EPG. Xtream liste imaju EPG automatski.',
                    helperMaxLines: 2,
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (v) {
                    st.xmltv = v.trim();
                    st.save(notify: false);
                  },
                )),
                _section('Reprodukcija'),
                _pad(const Text('Skok naprijed/nazad (filmovi i serije)')),
                _pad(SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(value: 5, label: Text('5 s')),
                    ButtonSegment(value: 10, label: Text('10 s')),
                    ButtonSegment(value: 30, label: Text('30 s')),
                  ],
                  selected: {st.skipSeconds},
                  onSelectionChanged: (s) {
                    st.skipSeconds = s.first;
                    st.save();
                  },
                )),
                SwitchListTile(
                  title: const Text('Otvori zadnju listu pri pokretanju'),
                  value: st.autoOpenLast,
                  onChanged: (v) {
                    st.autoOpenLast = v;
                    st.save();
                  },
                ),
                _section('Prečice (tipkovnica i daljinski)'),
                for (final a in kKeyActs)
                  ListTile(
                    dense: true,
                    title: Text(a.label),
                    trailing: OutlinedButton(
                      onPressed: () => _rebind(a),
                      child: Text(keyName(st.keyFor(a.id))),
                    ),
                  ),
                _pad(Text(
                  'Uvijek rade i: Enter/OK = info, CH+/CH- = kanal, 0–9 = broj kanala, '
                  'tipke za medije (play/pauza, naprijed, nazad).',
                  style: Theme.of(context).textTheme.bodySmall,
                )),
                _pad(Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: st.resetKeys,
                    icon: const Icon(Icons.restore),
                    label: const Text('Vrati zadane prečice'),
                  ),
                )),
                _section('O aplikaciji'),
                const ListTile(
                  title: Text('STB Player 1.1'),
                  subtitle: Text(
                    'Plejer za tvoje vlastite IPTV pretplate (M3U, Xtream, Stalker/MAC). '
                    'Aplikacija ne sadrži kanale niti sadržaj.',
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _KeyCaptureDialog extends StatelessWidget {
  const _KeyCaptureDialog({required this.label});
  final String label;

  static final Set<LogicalKeyboardKey> _mods = {
    LogicalKeyboardKey.shiftLeft,
    LogicalKeyboardKey.shiftRight,
    LogicalKeyboardKey.controlLeft,
    LogicalKeyboardKey.controlRight,
    LogicalKeyboardKey.altLeft,
    LogicalKeyboardKey.altRight,
    LogicalKeyboardKey.metaLeft,
    LogicalKeyboardKey.metaRight,
  };

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(label),
      content: Focus(
        autofocus: true,
        onKeyEvent: (node, e) {
          if (e is KeyDownEvent && !_mods.contains(e.logicalKey)) {
            Navigator.pop(context, e.logicalKey);
          }
          return KeyEventResult.handled;
        },
        child: const Text('Pritisni tipku koju želiš dodijeliti ovoj radnji…'),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Odustani')),
      ],
    );
  }
}
