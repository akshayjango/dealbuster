import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/push_notification_service.dart';
import '../theme/app_theme.dart';
import 'home_screen.dart';

/// Screen prompting the user to allow push notifications for deals.
/// Inspired by the minimalist notification card & phone mockup design.
class NotificationPermissionScreen extends StatefulWidget {
  final VoidCallback? onComplete;

  const NotificationPermissionScreen({super.key, this.onComplete});

  @override
  State<NotificationPermissionScreen> createState() =>
      _NotificationPermissionScreenState();
}

class _NotificationPermissionScreenState
    extends State<NotificationPermissionScreen> {
  bool _requesting = false;

  String _getTodayString() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  Future<void> _handleAllow() async {
    if (_requesting) return;
    setState(() => _requesting = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('last_notif_prompt_date', _getTodayString());

      // Request notification permission from system
      await PushNotificationService.instance.requestPermission();
    } finally {
      if (mounted) {
        setState(() => _requesting = false);
        _finish();
      }
    }
  }

  Future<void> _handleNotNow() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('last_notif_prompt_date', _getTodayString());
    _finish();
  }

  void _finish() {
    if (widget.onComplete != null) {
      widget.onComplete!();
    } else if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28.0),
          child: Column(
            children: [
              const Spacer(flex: 2),

              // ── Phone Mockup + Floating Notification Card Illustration ──
              _buildNotificationIllustration(),

              const Spacer(flex: 2),

              // ── Headline & Body ──
              Text(
                'Stay in the loop about\nthe best deals',
                textAlign: TextAlign.center,
                style: GoogleFonts.sora(
                  fontSize: 27,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                  letterSpacing: -0.6,
                  height: 1.22,
                ),
              ),
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10.0),
                child: Text(
                  'Get instant alerts for loot deals, lowest price drops, and flash offers. Adjust settings anytime.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w400,
                    color: AppColors.ink700,
                    height: 1.48,
                  ),
                ),
              ),

              const Spacer(flex: 3),

              // ── "Not now" button ──
              TextButton(
                onPressed: _requesting ? null : _handleNotNow,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.ink400,
                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 20),
                  splashFactory: NoSplash.splashFactory,
                ),
                child: Text(
                  'Not now',
                  style: GoogleFonts.inter(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink400,
                  ),
                ),
              ),
              const SizedBox(height: 10),

              // ── "Allow notifications" CTA pill button ──
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: _requesting ? null : _handleAllow,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0F0E17), // Deep black pill
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                  ),
                  child: _requesting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          'Allow notifications',
                          style: GoogleFonts.sora(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            letterSpacing: -0.2,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  /// Builds the stylized phone frame with the floating notification pill
  /// with a smooth blended gradient fade on the bottom area into the background.
  Widget _buildNotificationIllustration() {
    return SizedBox(
      height: 260,
      width: double.infinity,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          // ── Phone Frame Mockup with Bottom Gradient Fade ──
          Positioned(
            top: 10,
            bottom: 0,
            child: ShaderMask(
              shaderCallback: (Rect bounds) {
                return const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black,
                    Colors.black,
                    Colors.transparent,
                  ],
                  stops: [0.0, 0.42, 0.85],
                ).createShader(bounds);
              },
              blendMode: BlendMode.dstIn,
              child: Container(
                width: 180,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.65),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(34),
                    bottom: Radius.circular(34),
                  ),
                  border: Border.all(
                    color: const Color(0xFFDDD9E5),
                    width: 3.5,
                  ),
                ),
                child: Column(
                  children: [
                    const SizedBox(height: 12),
                    // Dynamic Island / Speaker Notch
                    Container(
                      width: 48,
                      height: 13,
                      decoration: BoxDecoration(
                        color: const Color(0xFFD6D1E0),
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── Floating Notification Card (Paytm/Reference Style) ──
          Positioned(
            top: 72,
            child: Container(
              width: 295,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                    spreadRadius: -2,
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  // Box icon with warm gradient
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(11),
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color(0xFFFF8E53),
                          Color(0xFFFF5A3C),
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFFF5A3C).withValues(alpha: 0.25),
                          blurRadius: 6,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.local_offer_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Title + Timestamp + Subtitle
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Text(
                              'Best offer',
                              style: GoogleFonts.sora(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: AppColors.ink,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              'Just now',
                              style: GoogleFonts.inter(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w500,
                                color: AppColors.ink400,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2.5),
                        Text(
                          'Lowest price detected on your favorite deal',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.w400,
                            color: AppColors.ink700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
