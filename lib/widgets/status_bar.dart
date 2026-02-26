import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class StatusBarWidget extends StatelessWidget {
  const StatusBarWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(28, 14, 28, 6),
      color: AppColors.bg,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            '9:41',
            style: TextStyle(
              fontFamily: 'DM Mono',
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.text,
            ),
          ),
          Row(
            children: [
              _buildSignalIcon(),
              const SizedBox(width: 6),
              _buildBatteryIcon(),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSignalIcon() {
    return const Icon(
      Icons.signal_cellular_alt,
      size: 16,
      color: AppColors.text,
    );
  }

  Widget _buildBatteryIcon() {
    return const Row(
      children: [Icon(Icons.battery_full, size: 16, color: AppColors.text)],
    );
  }
}
