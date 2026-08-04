import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'screens/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Set system bar styling to match the website's dark status header
  SystemChrome.setSystemUIOverlayStyle(
    const SystemOverlayStyle(
      statusBarColor: Color(0xFF4A1B96), // Matches purple top wrap
      statusBarIconBrightness: Brightness.light, // Light icons
      statusBarBrightness: Brightness.dark, // iOS Status bar color theme
      systemNavigationBarColor: Color(0xFFF6F7FB), // Matches bottom background
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );
  
  runApp(const DealbusterApp());
}

class DealbusterApp extends StatelessWidget {
  const DealbusterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Dealbuster',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF6F7FB),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6C47FF),
          primary: const Color(0xFF6C47FF),
          background: const Color(0xFFF6F7FB),
        ),
        textTheme: const TextTheme(
          bodyLarge: TextStyle(fontFamily: 'Plus Jakarta Sans'),
          bodyMedium: TextStyle(fontFamily: 'Plus Jakarta Sans'),
          titleLarge: TextStyle(fontFamily: 'Montserrat', fontWeight: FontWeight.w900),
        ),
      ),
      home: const HomeScreen(),
    );
  }
}
