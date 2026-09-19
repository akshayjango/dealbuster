import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'screens/splash_screen.dart';
import 'services/push_notification_service.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
      systemNavigationBarColor: AppColors.bg,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );

  // Initialize Firebase (local config only, background network sync)
  await PushNotificationService.instance.init();

  // Determine notification permission prompt status with fast-path logic
  bool shouldPrompt = false;
  try {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final today =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final lastPromptDate = prefs.getString('last_notif_prompt_date');

    // If already prompted today, skip permission query completely
    if (lastPromptDate != today) {
      final hasPermission =
          await PushNotificationService.instance.hasPermission();
      if (!hasPermission) {
        shouldPrompt = true;
      }
    }
  } catch (e) {
    debugPrint('[Startup] Permission check error: $e');
  }

  runApp(DealBusterApp(shouldPrompt: shouldPrompt));
}

class DealBusterApp extends StatelessWidget {
  final bool shouldPrompt;
  const DealBusterApp({super.key, required this.shouldPrompt});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DealBuster',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: SplashScreen(shouldPrompt: shouldPrompt),
    );
  }
}
