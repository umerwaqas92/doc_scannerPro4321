import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_theme.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
  });

  Future<void> _launchURL(String urlString) async {
    final Uri url = Uri.parse(urlString);
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      throw Exception('Could not launch $url');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.bg,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            _buildSection('Account', [
              _buildNavRow(
                Icons.security_outlined,
                'Privacy Policy',
                onTap:
                    () => _launchURL(
                      'https://www.freeprivacypolicy.com/live/0af5bf0f-a559-468c-bb51-e5cfabcc41a4',
                    ),
              ),
              _buildNavRow(
                Icons.gavel_outlined,
                'Terms and Conditions',
                onTap:
                    () => _launchURL(
                      'https://www.freeprivacypolicy.com/live/6acd82b0-38ff-45dc-901f-5e39e4eabe6f',
                    ),
              ),
            ]),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return const Padding(
      padding: EdgeInsets.fromLTRB(24, 10, 24, 16),
      child: Text(
        'Settings',
        style: TextStyle(
          fontSize: 26,
          fontWeight: FontWeight.w600,
          color: AppColors.text,
          letterSpacing: -0.5,
        ),
      ),
    );
  }

  Widget _buildSection(String title, List<Widget> children) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              title.toUpperCase(),
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.text3,
                letterSpacing: 0.06,
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(AppDimens.radiusSm),
            ),
            child: Column(children: children),
          ),
        ],
      ),
    );
  }

  Widget _buildNavRow(IconData icon, String label, {VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: AppColors.surface2,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(icon, size: 16, color: AppColors.text),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppColors.text,
                ),
              ),
            ),
            const Icon(Icons.chevron_right, size: 16, color: AppColors.text3),
          ],
        ),
      ),
    );
  }
}
