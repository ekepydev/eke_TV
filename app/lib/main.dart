import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'sources_screen.dart';
import 'store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await Store.init();
  runApp(const StbApp());
}

class StbApp extends StatelessWidget {
  const StbApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'STB Player',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorSchemeSeed: const Color(0xFF4F8CFF),
        scaffoldBackgroundColor: const Color(0xFF0B1020),
      ),
      home: const SourcesScreen(),
    );
  }
}
