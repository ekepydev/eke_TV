import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'models.dart';
import 'providers.dart';

class AddSourceScreen extends StatefulWidget {
  const AddSourceScreen({super.key});

  @override
  State<AddSourceScreen> createState() => _AddSourceScreenState();
}

class _AddSourceScreenState extends State<AddSourceScreen> {
  final _form = GlobalKey<FormState>();
  String type = 'm3u';
  final name = TextEditingController();
  final url = TextEditingController();
  final xmltv = TextEditingController();
  final server = TextEditingController();
  final user = TextEditingController();
  final pass = TextEditingController();
  final portal = TextEditingController();
  final mac = TextEditingController();

  List<int>? _fileBytes;
  String _fileInfo = '';
  bool useXtream = true;
  bool saving = false;

  @override
  void initState() {
    super.initState();
    url.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    for (final c in [name, url, xmltv, server, user, pass, portal, mac]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _req(String? v) => (v == null || v.trim().isEmpty) ? 'Obavezno polje' : null;

  String? _macCheck(String? v) {
    final e = _req(v);
    if (e != null) return e;
    return RegExp(r'^([0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}$').hasMatch(v!.trim())
        ? null
        : 'Format: 00:1A:79:XX:XX:XX';
  }

  /// Ako je M3U link zapravo Xtream (get.php?username=..&password=..), izvuci podatke.
  ({String server, String user, String pass})? get _xtreamFromUrl {
    final u = Uri.tryParse(url.text.trim());
    if (u == null || !u.hasAuthority) return null;
    if (!RegExp(r'/(get|playlist)\.php$', caseSensitive: false).hasMatch(u.path)) return null;
    final us = u.queryParameters['username'];
    final pw = u.queryParameters['password'];
    if (us == null || pw == null || us.isEmpty || pw.isEmpty) return null;
    return (server: '${u.scheme}://${u.authority}', user: us, pass: pw);
  }

  Future<void> _pick() async {
    try {
      final r = await FilePicker.platform.pickFiles(type: FileType.any, withData: true);
      if (r == null || r.files.isEmpty) return;
      final f = r.files.single;
      final bytes = f.bytes;
      if (bytes == null) throw Exception('Fajl se ne može pročitati');
      final text = utf8.decode(bytes, allowMalformed: true);
      if (!looksLikeM3u(text)) throw Exception('Ovo nije M3U lista');
      final n = parseM3u(text).length;
      setState(() {
        _fileBytes = bytes;
        _fileInfo = '${f.name} · $n kanala';
        if (name.text.trim().isEmpty) {
          name.text = f.name.replaceAll(RegExp(r'\.(m3u8?|txt)$', caseSensitive: false), '');
        }
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errMsg(e))));
    }
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final nm = name.text.trim();
    Source s;
    if (type == 'file') {
      if (_fileBytes == null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Odaberi M3U fajl')));
        return;
      }
      setState(() => saving = true);
      final dir = await getApplicationSupportDirectory();
      final f = File('${dir.path}${Platform.pathSeparator}m3u_$id.m3u');
      await f.writeAsBytes(_fileBytes!);
      s = Source(id: id, name: nm, type: 'file', file: f.path, xmltv: xmltv.text.trim());
    } else if (type == 'm3u') {
      final x = _xtreamFromUrl;
      if (x != null && useXtream) {
        s = Source(id: id, name: nm, type: 'xtream', server: x.server, user: x.user, pass: x.pass);
      } else {
        s = Source(id: id, name: nm, type: 'm3u', url: url.text.trim(), xmltv: xmltv.text.trim());
      }
    } else if (type == 'xtream') {
      s = Source(
        id: id,
        name: nm,
        type: 'xtream',
        server: server.text.trim(),
        user: user.text.trim(),
        pass: pass.text.trim(),
      );
    } else {
      s = Source(
        id: id,
        name: nm,
        type: 'stalker',
        portal: portal.text.trim(),
        mac: mac.text.trim().toUpperCase().replaceAll('-', ':'),
      );
    }
    if (!mounted) return;
    Navigator.pop(context, s);
  }

  Widget _field(
    TextEditingController c,
    String label, {
    String? hint,
    String? Function(String?)? validator,
    bool autofocus = false,
    TextInputType? keyboard,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextFormField(
        controller: c,
        autofocus: autofocus,
        keyboardType: keyboard,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: const OutlineInputBorder(),
        ),
        validator: validator ?? _req,
        textInputAction: TextInputAction.next,
      ),
    );
  }

  Widget _typeChip(String t, String label, IconData icon) {
    return ChoiceChip(
      avatar: Icon(icon, size: 18),
      label: Text(label),
      selected: type == t,
      onSelected: (_) => setState(() => type = t),
    );
  }

  @override
  Widget build(BuildContext context) {
    final x = type == 'm3u' ? _xtreamFromUrl : null;
    return Scaffold(
      appBar: AppBar(title: const Text('Dodaj listu')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Form(
            key: _form,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _typeChip('m3u', 'M3U link', Icons.link),
                    _typeChip('file', 'M3U fajl', Icons.upload_file),
                    _typeChip('xtream', 'Xtream', Icons.dns),
                    _typeChip('stalker', 'Portal + MAC', Icons.settings_input_antenna),
                  ],
                ),
                const SizedBox(height: 18),
                _field(name, 'Naziv liste', hint: 'Moja lista'),
                if (type == 'm3u') ...[
                  _field(url, 'M3U URL',
                      hint: 'http://server/get.php?username=..&password=..&type=m3u_plus',
                      keyboard: TextInputType.url),
                  if (x != null)
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: useXtream,
                      onChanged: (v) => setState(() => useXtream = v),
                      title: const Text('Prepoznat je Xtream pristup'),
                      subtitle: const Text('Uključi filmove, serije i program (EPG) iz iste pretplate'),
                    ),
                  if (x == null || !useXtream)
                    _field(xmltv, 'EPG (XMLTV) link, opcionalno',
                        validator: (_) => null, keyboard: TextInputType.url),
                ],
                if (type == 'file') ...[
                  OutlinedButton.icon(
                    onPressed: _pick,
                    icon: const Icon(Icons.folder_open),
                    label: Text(_fileInfo.isEmpty ? 'Odaberi M3U fajl' : _fileInfo),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Fajl se kopira u aplikaciju. Linkovi kanala unutar liste moraju biti dostupni.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 14),
                  _field(xmltv, 'EPG (XMLTV) link, opcionalno',
                      validator: (_) => null, keyboard: TextInputType.url),
                ],
                if (type == 'xtream') ...[
                  _field(server, 'Server', hint: 'http://server:port', keyboard: TextInputType.url),
                  _field(user, 'Korisničko ime'),
                  _field(pass, 'Lozinka'),
                ],
                if (type == 'stalker') ...[
                  _field(portal, 'Portal URL', hint: 'http://server:port/c/', keyboard: TextInputType.url),
                  _field(mac, 'MAC adresa', hint: '00:1A:79:XX:XX:XX', validator: _macCheck),
                ],
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: saving ? null : _save,
                  icon: const Icon(Icons.check),
                  label: const Text('Sačuvaj'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
