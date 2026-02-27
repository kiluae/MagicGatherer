import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import 'theme/dark_theme.dart';
import 'screens/home_screen.dart';
import 'screens/splash_screen.dart';
import 'providers/splash_provider.dart';
import 'services/app_settings.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await AppSettings.load();

  await windowManager.ensureInitialized();
  await windowManager.setTitle('MagicGatherer v3.2');
  await windowManager.setMinimumSize(const Size(1050, 700));
  await windowManager.setSize(const Size(1280, 820));
  await windowManager.center();
  await windowManager.show();

  runApp(const MagicGathererApp());
}

class MagicGathererApp extends StatelessWidget {
  const MagicGathererApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => SplashProvider(),
      child: MaterialApp(
        title: 'MagicGatherer',
        debugShowCheckedModeBanner: false,
        theme: buildDarkTheme(),
        home: const SplashScreen(),
      ),
    );
  }
}
