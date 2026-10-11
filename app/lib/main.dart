import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';

import 'home_screen.dart';
import 'settings.dart';
import 'store.dart';
import 'util.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await Store.init();
  AppSettings.I.load();
  if (isDesktop) {
    await windowManager.ensureInitialized();
    await windowManager.waitUntilReadyToShow(
      const WindowOptions(minimumSize: Size(480, 360), title: 'STB Player'),
      () async {
        await windowManager.show();
        await windowManager.focus();
      },
    );
  }
  runApp(const StbApp());
}

ThemeData _theme(Brightness b) {
  final dark = b == Brightness.dark;
  final cs = ColorScheme.fromSeed(seedColor: const Color(0xFF4F8CFF), brightness: b);
  return ThemeData(
    useMaterial3: true,
    colorScheme: cs,
    scaffoldBackgroundColor: dark ? const Color(0xFF0B1020) : const Color(0xFFF4F6FC),
    appBarTheme: AppBarTheme(
      backgroundColor: dark ? const Color(0xFF0B1020) : const Color(0xFFF4F6FC),
      surfaceTintColor: Colors.transparent,
      elevation: 0,
    ),
    visualDensity: VisualDensity.adaptivePlatformDensity,
  );
}

class StbApp extends StatelessWidget {
  const StbApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppSettings.I,
      builder: (context, _) => MaterialApp(
        title: 'STB Player',
        debugShowCheckedModeBanner: false,
        themeMode: AppSettings.I.themeMode,
        theme: _theme(Brightness.light),
        darkTheme: _theme(Brightness.dark),
        home: const HomeScreen(),
      ),
    );
  }
}
