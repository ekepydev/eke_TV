import 'package:flutter/material.dart';

import 'models.dart';

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
  final server = TextEditingController();
  final user = TextEditingController();
  final pass = TextEditingController();
  final portal = TextEditingController();
  final mac = TextEditingController();

  @override
  void dispose() {
    for (final c in [name, url, server, user, pass, portal, mac]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _req(String? v) =>
      (v == null || v.trim().isEmpty) ? 'Obavezno polje' : null;

  String? _macCheck(String? v) {
    final e = _req(v);
    if (e != null) return e;
    return RegExp(r'^([0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}$').hasMatch(v!.trim())
        ? null
        : 'Format: 00:1A:79:XX:XX:XX';
  }

  void _save() {
    if (!_form.currentState!.validate()) return;
    Navigator.pop(
      context,
      Source(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: name.text.trim(),
        type: type,
        url: url.text.trim(),
        server: server.text.trim(),
        user: user.text.trim(),
        pass: pass.text.trim(),
        portal: portal.text.trim(),
        mac: mac.text.trim().toUpperCase().replaceAll('-', ':'),
      ),
    );
  }

  Widget _field(
    TextEditingController c,
    String label, {
    String? hint,
    String? Function(String?)? validator,
    bool autofocus = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextFormField(
        controller: c,
        autofocus: autofocus,
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Dodaj listu')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'm3u', label: Text('M3U link')),
                ButtonSegment(value: 'xtream', label: Text('Xtream')),
                ButtonSegment(value: 'stalker', label: Text('Portal + MAC')),
              ],
              selected: {type},
              onSelectionChanged: (s) => setState(() => type = s.first),
            ),
            const SizedBox(height: 18),
            _field(name, 'Naziv liste', hint: 'Moja lista'),
            if (type == 'm3u')
              _field(url, 'M3U URL', hint: 'http://server/get.php?username=..&password=..&type=m3u_plus'),
            if (type == 'xtream') ...[
              _field(server, 'Server', hint: 'http://server:port'),
              _field(user, 'Korisničko ime'),
              _field(pass, 'Lozinka'),
            ],
            if (type == 'stalker') ...[
              _field(portal, 'Portal URL', hint: 'http://server:port/c/'),
              _field(mac, 'MAC adresa', hint: '00:1A:79:XX:XX:XX', validator: _macCheck),
            ],
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.check),
              label: const Text('Sačuvaj'),
            ),
          ],
        ),
      ),
    );
  }
}
