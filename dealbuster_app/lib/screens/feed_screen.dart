import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';

class FeedScreen extends StatelessWidget {
  const FeedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final imageWidth = (screenWidth * 0.58).clamp(180.0, 240.0);

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Top Header & Title (Matching Stores & Offers) ──
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Text(
                'Feed',
                style: GoogleFonts.sora(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                  letterSpacing: -0.4,
                ),
              ),
            ),

            // ── Centered Graphic & Content (No buttons, no cards) ──
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(32, 16, 32, 80),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Image.asset(
                        'assets/images/feed_illustration.webp',
                        width: imageWidth,
                        fit: BoxFit.contain,
                      ),
                      const SizedBox(height: 28),
                      Text(
                        'Coming Soon',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.sora(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: AppColors.ink,
                          letterSpacing: -0.4,
                        ),
                      ),
                      const SizedBox(height: 10),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 320),
                        child: Text(
                          'Discover the latest deals, price drops, shopping updates, and connect with a growing community of deal hunters.',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w400,
                            color: AppColors.ink700,
                            height: 1.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
