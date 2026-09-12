import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

/// Top-level background message handler for FCM
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  debugPrint('[FCM Background] Message received: ${message.messageId}');
}

/// Service managing Firebase Cloud Messaging push notifications and deal deep linking.
class PushNotificationService {
  PushNotificationService._();
  static final PushNotificationService instance = PushNotificationService._();

  /// Topic subscribed to by all app users for deal broadcasts
  static const String dealsTopic = 'deals';

  /// ValueNotifier holding the product ID to open when a push notification is tapped.
  final ValueNotifier<String?> productToOpen = ValueNotifier<String?>(null);

  bool _initialized = false;

  /// Initializes Firebase and Firebase Cloud Messaging listeners.
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    try {
      await Firebase.initializeApp();

      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

      // Configure foreground notification presentation
      await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );

      // Auto-subscribe to deals broadcast topic
      await FirebaseMessaging.instance.subscribeToTopic(dealsTopic);

      // Handle notification tapped while app is running in background
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        _handleMessagePayload(message);
      });

      // Handle notification tapped when app was completely terminated (cold start)
      final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
      if (initialMessage != null) {
        _handleMessagePayload(initialMessage);
      }
    } catch (e) {
      debugPrint('[FCM Service] Initialization notice: $e');
    }
  }

  void _handleMessagePayload(RemoteMessage message) {
    final data = message.data;
    final productId = data['productId'] as String? ??
        data['id'] as String? ??
        data['dealId'] as String?;

    if (productId != null && productId.isNotEmpty) {
      productToOpen.value = productId;
    }
  }

  /// Prompts the Android 13+ native permission dialog for notifications.
  Future<bool> requestPermission() async {
    try {
      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
        sound: true,
      );

      final granted = settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional;

      if (granted) {
        await FirebaseMessaging.instance.subscribeToTopic(dealsTopic);
      }
      return granted;
    } catch (e) {
      debugPrint('[FCM Service] Request permission error: $e');
      return false;
    }
  }

  /// Checks if notification permission is currently granted.
  Future<bool> hasPermission() async {
    try {
      final settings = await FirebaseMessaging.instance.getNotificationSettings();
      return settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional;
    } catch (_) {
      return false;
    }
  }
}
