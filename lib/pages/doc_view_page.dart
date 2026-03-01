import 'dart:io';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/scanned_document.dart';

class DocViewPage extends StatelessWidget {
  final ScannedDocument? document;
  final VoidCallback onBack;
  final VoidCallback onMoreTap;
  final VoidCallback onSave;
  final VoidCallback onShare;
  final VoidCallback onOcr;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const DocViewPage({
    super.key,
    required this.document,
    required this.onBack,
    required this.onMoreTap,
    required this.onSave,
    required this.onShare,
    required this.onOcr,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.bg,
      child: SingleChildScrollView(
        child: Column(
          children: [
            _buildHeader(),
            _buildPreview(),
            _buildActionTiles(),
            _buildInfoCard(),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
      child: Row(
        children: [
          GestureDetector(
            onTap: onBack,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.border),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.arrow_back_ios,
                size: 18,
                color: AppColors.text2,
              ),
            ),
          ),
          Expanded(
            child: Text(
              document?.name ?? 'Document',
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: AppColors.text,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          GestureDetector(
            onTap: onMoreTap,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.border),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.more_horiz,
                size: 20,
                color: AppColors.text,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreview() {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      height: 400,
      decoration: BoxDecoration(
        color: const Color(0xFFE0DFD9),
        borderRadius: BorderRadius.circular(AppDimens.radius),
      ),
      child: Center(
        child:
            document != null &&
                !document!.isPdf &&
                File(document!.filePath).existsSync()
            ? ClipRRect(
                borderRadius: BorderRadius.circular(AppDimens.radius),
                child: Image.file(
                  File(document!.filePath),
                  fit: BoxFit.contain,
                ),
              )
            : Container(
                width: 220,
                height: 310,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(4),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 32,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    _buildDocLine(12, 0.7),
                    const SizedBox(height: 10),
                    _buildDocLine(8, 0.6),
                    const SizedBox(height: 18),
                    _buildDocLine(8, 0.85),
                    const SizedBox(height: 8),
                    _buildDocLine(8, 1.0),
                    const SizedBox(height: 8),
                    _buildDocLine(8, 0.85),
                    const SizedBox(height: 8),
                    _buildDocLine(8, 0.4),
                    const SizedBox(height: 14),
                    _buildDocLine(8, 0.85),
                    const SizedBox(height: 8),
                    _buildDocLine(8, 1.0),
                    const SizedBox(height: 8),
                    _buildDocLine(8, 0.75),
                    const SizedBox(height: 8),
                    _buildDocLine(8, 0.5),
                    const SizedBox(height: 8),
                    _buildDocLine(8, 1.0),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildDocLine(double height, double widthFactor) {
    return Container(
      height: height,
      width: double.infinity * widthFactor,
      decoration: BoxDecoration(
        color: const Color(0xFFF0F0EE),
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }

  Widget _buildActionTiles() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: Row(
        children: [
          _buildActionTile(Icons.save_outlined, 'Save', onSave),
          _buildActionTile(Icons.share_outlined, 'Share', onShare),
          _buildActionTile(Icons.text_snippet_outlined, 'OCR', onOcr),
          _buildActionTile(Icons.edit_outlined, 'Edit', onEdit),
        ],
      ),
    );
  }

  Widget _buildActionTile(IconData icon, String label, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              Icon(icon, size: 20, color: AppColors.text),
              const SizedBox(height: 6),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                  color: AppColors.text2,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoCard() {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppDimens.radiusSm),
      ),
      child: Column(
        children: [
          _buildInfoRow('Type', document?.isPdf == true ? 'PDF' : 'JPG'),
          const Divider(height: 1, color: AppColors.border),
          _buildInfoRow('Pages', '${document?.pageCount ?? 1}'),
          const Divider(height: 1, color: AppColors.border),
          _buildInfoRow('Size', document?.formattedSize ?? '0 B'),
          const Divider(height: 1, color: AppColors.border),
          _buildInfoRow('Scanned', document?.formattedDate ?? 'Unknown'),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 13, color: AppColors.text3),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: AppColors.text,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}
