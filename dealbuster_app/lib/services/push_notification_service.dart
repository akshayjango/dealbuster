import 'package:flutter/foundation.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';

/// Service managing OneSignal push notifications and deep linking to deals.
class PushNotificationService {
  PushNotificationService._();
  static final PushNotificationService instance = PushNotificationService._();

  /// OneSignal App ID for DealBuster.
  /// Replace with your OneSignal App ID from dashboard (e.g. from keys or remote config).
  static const String defaultAppId = 'YOUR_ONESIGNAL_APP_ID';

  /// ValueNotifier holding the product ID to open when a push notification is tapped.
  final ValueNotifier<String?> productToOpen = ValueNotifier<String?>(null);

  bool _initialized = false;

  /// Initializes the OneSignal SDK and sets up notification click handlers.
  Future<void> init([String appId = defaultAppId]) async {
    if (_initialized) return;
    _initialized = true;

    try {
      if (kDebugMode) {
        OneSignal.Debug.setLogLevel(OSLogLevel.verbose);
      }

      if (appId.isNotEmpty && appId != 'YOUR_ONESIGNAL_APP_ID') {
        OneSignal.initialize(appId);
      }

      // Handle notification clicks (Paytm-style small status bar notification tapped)
      OneSignal.Notifications.addClickListener((event) {
        final additionalData = event.notification.additionalData;
        if (additionalData != null) {
          final productId = additionalData['productId'] as String? ??
              additionalData['id'] as String? ??
              additionalData['dealId'] as String?;

          if (productId != null && productId.isNotEmpty) {
            productToOpen.value = productId;
          }
        }
      });
    } catch (e) {
      debugPrint('[PushNotificationService] Initialization error: $e');
    }
  }

  /// Prompts the Android 13+ native permission dialog.
  Future<bool> requestPermission() async {
    try {
      final granted = await OneSignal.Notifications.requestPermission(true);
      return granted;
    } catch (e) {
      debugPrint('[PushNotificationService] Request permission error: $e');
      return false;
    }
  }

  /// Checks if notification permission is currently granted.
  Future<bool> hasPermission() async {
    try {
      return OneSignal.Notifications.permission;
    } catch (_) {
      return false;
    }
  }
}
