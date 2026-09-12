import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'screens/home_screen.dart';
import 'screens/notification_permission_screen.dart';
import 'services/push_notification_service.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize push notification SDK
  await PushNotificationService.instance.init();

  // Check notification permission status
  final hasPermission = await PushNotificationService.instance.hasPermission();

  // If user already enabled notifications, never show the prompt screen.
  // If not enabled, show it on the first app launch of each day.
  bool shouldPrompt = false;
  if (!hasPermission) {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final today = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final lastPromptDate = prefs.getString('last_notif_prompt_date');

    if (lastPromptDate != today) {
      shouldPrompt = true;
    }
  }

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
      home: shouldPrompt
          ? const NotificationPermissionScreen()
          : const HomeScreen(),
    );
  }
}
