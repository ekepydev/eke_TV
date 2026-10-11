import 'dart:io';

String two(int n) => n.toString().padLeft(2, '0');

String hm(DateTime d) {
  final l = d.toLocal();
  return '${two(l.hour)}:${two(l.minute)}';
}

String fmtDur(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  final s = d.inSeconds.remainder(60);
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
}

/// Skida godinu i zagrade iz naziva ("Film (2024) [HD]" -> "Film").
String cleanTitle(String t) => t
    .replaceAll(RegExp(r'[\(\[].*?[\)\]]'), '')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

bool get isDesktop => Platform.isWindows || Platform.isLinux || Platform.isMacOS;

bool get isMobile => Platform.isAndroid || Platform.isIOS;
