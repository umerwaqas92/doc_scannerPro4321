import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class SettingsPage extends StatelessWidget {
  final bool autoCrop;
  final String flashMode;
  final String defaultFormat;
  final bool cloudBackup;
  final Function(bool) onAutoCropChanged;
  final Function(String) onFlashModeChanged;
  final Function(String) onDefaultFormatChanged;
  final Function(bool) onCloudBackupChanged;

  const SettingsPage({
    super.key,
    required this.autoCrop,
    required this.flashMode,
    required this.defaultFormat,
    required this.cloudBackup,
    required this.onAutoCropChanged,
    required this.onFlashModeChanged,
    required this.onDefaultFormatChanged,
    required this.onCloudBackupChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.bg,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            _buildSection('Scan', [
              _buildToggleRow(
                Icons.document_scanner_outlined,
                'Auto Crop',
                'Detect edges automatically',
                autoCrop,
                onAutoCropChanged,
              ),
              _buildValueRow(Icons.wb_sunny_outlined, 'Flash Mode', flashMode),
              _buildValueRow(
                Icons.picture_as_pdf_outlined,
                'Default Format',
                defaultFormat,
              ),
            ]),
            _buildSection('Storage', [
              _buildToggleRow(
                Icons.cloud_upload_outlined,
                'Cloud Backup',
                'Auto-save to cloud',
                cloudBackup,
                onCloudBackupChanged,
              ),
              _buildValueRow(Icons.storage_outlined, 'Storage Used', '48 MB'),
            ]),
            _buildSection('Account', [
              _buildNavRow(Icons.person_outline, 'Profile'),
              _buildNavRow(Icons.security_outlined, 'Privacy & Security'),
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

  Widget _buildToggleRow(
    IconData icon,
    String label,
    String sub,
    bool value,
    Function(bool) onChanged,
  ) {
    return Padding(
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: AppColors.text,
                  ),
                ),
                Text(
                  sub,
                  style: const TextStyle(fontSize: 12, color: AppColors.text3),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => onChanged(!value),
            child: Container(
              width: 44,
              height: 26,
              decoration: BoxDecoration(
                color: value ? AppColors.text : AppColors.border,
                borderRadius: BorderRadius.circular(13),
              ),
              child: AnimatedAlign(
                duration: const Duration(milliseconds: 200),
                alignment: value ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  margin: const EdgeInsets.all(3),
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.2),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildValueRow(IconData icon, String label, String value) {
    return Padding(
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
          Row(
            children: [
              Text(
                value,
                style: const TextStyle(fontSize: 13, color: AppColors.text2),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right, size: 16, color: AppColors.text3),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNavRow(IconData icon, String label) {
    return Padding(
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
    );
  }
}
