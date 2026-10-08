import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'config/app_config.dart';
import 'database/app_database.dart';
import 'services/background_service.dart';
import 'services/notifications.dart';
import 'services/providers.dart';
import 'services/seed.dart';
import 'screens/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final db = await AppDatabase.open();
  await seedDefaults(db);
  final prefs = await SharedPreferences.getInstance();

  try {
    await RadarNotifications.init();
  } catch (_) {
    // الإشعارات اختيارية: الفشل لا يمنع تشغيل التطبيق.
  }

  final settings = loadSettings(prefs);
  if (settings.backgroundEnabled) {
    try {
      await initBackground();
      await applyBackgroundSchedule(
        enabled: true,
        requestedMinutes: settings.backgroundIntervalMinutes,
      );
    } catch (_) {
      // المهام الخلفية اختيارية: الفشل لا يمنع استخدام التطبيق.
    }
  }

  runApp(ProviderScope(
    overrides: [
      databaseProvider.overrideWithValue(db),
      prefsProvider.overrideWithValue(prefs),
    ],
    child: const RadarApp(),
  ));
}

class RadarApp extends ConsumerWidget {
  const RadarApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    const seed = Color(0xFF0F766E);
    return MaterialApp(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: seed, useMaterial3: true, brightness: Brightness.light),
      darkTheme: ThemeData(colorSchemeSeed: seed, useMaterial3: true, brightness: Brightness.dark),
      themeMode: s.themeMode,
      locale: Locale(s.language),
      supportedLocales: const [Locale('ar'), Locale('en')],
      home: const MainShell(),
    );
  }
}
