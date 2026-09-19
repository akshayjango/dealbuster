import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/push_notification_service.dart';
import '../theme/app_theme.dart';
import '../utils/svg_icons.dart';

const _telegramUrl = 'https://t.me/dealbusterindia';
const _whatsappUrl = 'https://whatsapp.com/channel/0029Vb8eJlcA2pLCSwCSi00V';
const _privacyUrl = 'https://dealbuster.in/privacy';
const _termsUrl = 'https://dealbuster.in/terms';
const _affiliateDisclosureUrl = 'https://dealbuster.in/affiliate-disclosure';
const _playStoreUrl =
    'https://play.google.com/store/apps/details?id=com.dealbusterindia.app';
const _supportEmail =
    'mailto:contactdealbuster@gmail.com?subject=DealBuster%20App%20Support';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _notificationsEnabled = false;
  bool _loadingNotifState = true;

  @override
  void initState() {
    super.initState();
    _checkNotificationPermission();
  }

  Future<void> _checkNotificationPermission() async {
    try {
      final hasPerm = await PushNotificationService.instance.hasPermission();
      if (mounted) {
        setState(() {
          _notificationsEnabled = hasPerm;
          _loadingNotifState = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _loadingNotifState = false);
      }
    }
  }

  Future<void> _toggleNotification(bool value) async {
    setState(() => _notificationsEnabled = value);
    if (value) {
      final granted =
          await PushNotificationService.instance.requestPermission();
      if (mounted) {
        setState(() => _notificationsEnabled = granted);
      }
    }
  }

  Future<void> _launch(String urlStr) async {
    final uri = Uri.parse(urlStr);
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  void _shareApp() {
    Share.share(
      '🔥 Check out DealBuster for the hottest online deals, coupons & price crash alerts!\nDownload now: https://play.google.com/store/apps/details?id=com.dealbusterindia.app',
      subject: 'DealBuster - Best Deals & Price Drops',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(
            Icons.chevron_left_rounded,
            size: 30,
            color: AppColors.ink,
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Settings',
          style: GoogleFonts.sora(
            color: AppColors.ink,
            fontSize: 15,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(0.6),
          child: Container(
            color: AppColors.cardStroke,
            height: 0.6,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        children: [
          // ── Section 1: Preferences ──
          const _SectionHeader(title: 'PREFERENCES'),
          const SizedBox(height: 8),
          _SettingsGroup(
            children: [
              _SettingsToggleRow(
                icon: Icons.notifications_active_outlined,
                title: 'Lowest Price Notification',
                subtitle: 'Instant alerts when prices crash to all-time lows',
                value: _notificationsEnabled,
                loading: _loadingNotifState,
                onChanged: _toggleNotification,
              ),
            ],
          ),
          const SizedBox(height: 24),

          // ── Section 2: Community & Channels ──
          const _SectionHeader(title: 'COMMUNITY'),
          const SizedBox(height: 8),
          _SettingsGroup(
            children: [
              _SettingsActionRow(
                customLeading: const _BrandIconContainer(
                  color: Color(0xFF29A9EA),
                  icon: SvgIcons.telegram,
                ),
                title: 'Join Telegram Channel',
                subtitle: 'Real-time deal feed with 25k+ members',
                onTap: () => _launch(_telegramUrl),
              ),
              const _SettingsDivider(),
              _SettingsActionRow(
                customLeading: const _BrandIconContainer(
                  color: Color(0xFF25D366),
                  icon: SvgIcons.whatsapp,
                ),
                title: 'Join WhatsApp Channel',
                subtitle: 'Top handpicked deals on WhatsApp',
                onTap: () => _launch(_whatsappUrl),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // ── Section 3: Support ──
          const _SectionHeader(title: 'SUPPORT'),
          const SizedBox(height: 8),
          _SettingsGroup(
            children: [
              _SettingsActionRow(
                icon: Icons.share_outlined,
                title: 'Share App',
                onTap: _shareApp,
              ),
              const _SettingsDivider(),
              _SettingsActionRow(
                icon: Icons.star_outline_rounded,
                title: 'Rate and Review',
                onTap: () => _launch(_playStoreUrl),
              ),
              const _SettingsDivider(),
              _SettingsActionRow(
                icon: Icons.support_agent_rounded,
                title: 'Contact Support',
                subtitle: 'Email contactdealbuster@gmail.com',
                onTap: () => _launch(_supportEmail),
              ),
              const _SettingsDivider(),
              _SettingsActionRow(
                icon: Icons.verified_outlined,
                title: 'Affiliate Disclosure',
                subtitle: 'Transparency regarding our store links',
                onTap: () => _launch(_affiliateDisclosureUrl),
              ),
              const _SettingsDivider(),
              _SettingsActionRow(
                icon: Icons.privacy_tip_outlined,
                title: 'Privacy Policy',
                onTap: () => _launch(_privacyUrl),
              ),
              const _SettingsDivider(),
              _SettingsActionRow(
                icon: Icons.description_outlined,
                title: 'Terms of Use',
                onTap: () => _launch(_termsUrl),
              ),
              const _SettingsDivider(),
              _SettingsActionRow(
                icon: Icons.system_update_alt_rounded,
                title: 'Update App',
                subtitle: 'Check for latest version',
                onTap: () => _launch(_playStoreUrl),
              ),
            ],
          ),
          const SizedBox(height: 36),

          // ── Footer: Version & Love from India ──
          const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'DealBuster Version 1.0.3',
                  style: TextStyle(
                    color: AppColors.ink400,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.2,
                  ),
                ),
                SizedBox(height: 6),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Made with ',
                      style: TextStyle(
                        color: AppColors.ink400,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Icon(
                      Icons.favorite_rounded,
                      color: AppColors.brand,
                      size: 14,
                    ),
                    Text(
                      ' in India',
                      style: TextStyle(
                        color: AppColors.ink400,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          SizedBox(height: 36 + MediaQuery.paddingOf(context).bottom),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        title,
        style: const TextStyle(
          color: AppColors.ink400,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.cardStroke, width: 0.6),
        boxShadow: cardShadow(),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: children,
      ),
    );
  }
}

class _SettingsDivider extends StatelessWidget {
  const _SettingsDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 0.6,
      margin: const EdgeInsets.only(left: 54),
      color: AppColors.cardStroke,
    );
  }
}

class _SettingsToggleRow extends StatelessWidget {
  const _SettingsToggleRow({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.value,
    this.loading = false,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final bool value;
  final bool loading;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(icon, size: 22, color: AppColors.ink),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.ink,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle!,
                    style: const TextStyle(
                      color: AppColors.ink400,
                      fontSize: 11.5,
                      height: 1.2,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          loading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Transform.scale(
                  scale: 0.8,
                  child: Switch.adaptive(
                    value: value,
                    activeTrackColor: AppColors.brand,
                    activeThumbColor: Colors.white,
                    onChanged: onChanged,
                  ),
                ),
        ],
      ),
    );
  }
}

class _SettingsActionRow extends StatelessWidget {
  const _SettingsActionRow({
    this.icon,
    this.customLeading,
    required this.title,
    this.subtitle,
    required this.onTap,
  });

  final IconData? icon;
  final Widget? customLeading;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            if (customLeading != null)
              customLeading!
            else if (icon != null)
              Icon(icon, size: 22, color: AppColors.ink),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: AppColors.ink,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.ink400,
                        fontSize: 11.5,
                        height: 1.2,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: AppColors.ink400,
            ),
          ],
        ),
      ),
    );
  }
}

class _BrandIconContainer extends StatelessWidget {
  const _BrandIconContainer({
    required this.color,
    required this.icon,
  });

  final Color color;
  final String icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        shape: BoxShape.circle,
      ),
      child: Center(
        child: SvgIcon(
          icon,
          size: 14,
          color: color,
        ),
      ),
    );
  }
}
