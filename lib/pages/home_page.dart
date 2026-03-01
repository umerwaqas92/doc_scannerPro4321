import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/scanned_document.dart';

class HomePage extends StatelessWidget {
  final List<ScannedDocument> documents;
  final VoidCallback onScanTap;
  final Function(int) onDocTap;
  final VoidCallback onSeeAllTap;
  final VoidCallback onSearchTap;
  final VoidCallback onProfileTap;

  const HomePage({
    super.key,
    required this.documents,
    required this.onScanTap,
    required this.onDocTap,
    required this.onSeeAllTap,
    required this.onSearchTap,
    required this.onProfileTap,
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
            _buildScanBanner(),
            _buildSectionLabel('Tools'),
            _buildQuickActions(),
            _buildRecentHeader(),
            _buildDocList(),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 10, 24, 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            'DocScan',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w600,
              color: AppColors.text,
              letterSpacing: -0.5,
            ),
          ),
          Row(
            children: [
              _buildIconButton(Icons.search, onSearchTap),
              const SizedBox(width: 10),
              _buildIconButton(Icons.person_outline, onProfileTap),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildIconButton(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, size: 20, color: AppColors.text),
      ),
    );
  }

  Widget _buildScanBanner() {
    return GestureDetector(
      onTap: onScanTap,
      child: Container(
        margin: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.text,
          borderRadius: BorderRadius.circular(AppDimens.radius),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Scan Document',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Tap to open camera scanner',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.white.withOpacity(0.6),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(
                Icons.document_scanner,
                size: 26,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 10),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: AppColors.text2,
          letterSpacing: 0.04,
        ),
      ),
    );
  }

  Widget _buildQuickActions() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Row(
        children: [
          _buildQuickAction(Icons.picture_as_pdf, 'PDF'),
          _buildQuickAction(Icons.text_snippet_outlined, 'OCR Text'),
          _buildQuickAction(Icons.share_outlined, 'Share'),
          _buildQuickAction(Icons.folder_zip_outlined, 'Compress'),
        ],
      ),
    );
  }

  Widget _buildQuickAction(IconData icon, String label) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 5),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            Icon(icon, size: 22, color: AppColors.text),
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: AppColors.text2,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            'Recent',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: AppColors.text2,
              letterSpacing: 0.04,
            ),
          ),
          GestureDetector(
            onTap: onSeeAllTap,
            child: const Text(
              'See all',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppColors.text2,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDocList() {
    if (documents.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Container(
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(AppDimens.radiusSm),
          ),
          child: const Column(
            children: [
              Icon(
                Icons.document_scanner_outlined,
                size: 48,
                color: AppColors.text3,
              ),
              SizedBox(height: 12),
              Text(
                'No documents yet',
                style: TextStyle(fontSize: 14, color: AppColors.text2),
              ),
              SizedBox(height: 4),
              Text(
                'Tap the scan button to get started',
                style: TextStyle(fontSize: 12, color: AppColors.text3),
              ),
            ],
          ),
        ),
      );
    }

    final recentDocs = documents.take(4).toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(
        children: List.generate(recentDocs.length, (index) {
          final doc = recentDocs[index];
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _buildDocCard(
              doc.name,
              '${doc.formattedDate} · ${doc.pageCount} page${doc.pageCount > 1 ? 's' : ''} · ${doc.formattedSize}',
              doc.isPdf,
              index,
            ),
          );
        }),
      ),
    );
  }

  Widget _buildDocCard(String name, String meta, bool isPdf, int index) {
    return GestureDetector(
      onTap: () => onDocTap(index),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(AppDimens.radiusSm),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 56,
              decoration: BoxDecoration(
                color: AppColors.surface2,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppColors.border),
              ),
              child: Icon(
                isPdf ? Icons.picture_as_pdf : Icons.image,
                size: 22,
                color: AppColors.text3,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: AppColors.text,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    meta,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.text3,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: isPdf ? AppColors.pdfRed : AppColors.jpgBlue,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: isPdf
                      ? const Color(0xFFF5C0BB)
                      : const Color(0xFFB9D8F0),
                ),
              ),
              child: Text(
                isPdf ? 'PDF' : 'JPG',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                  color: isPdf ? AppColors.pdfRedText : AppColors.jpgBlueText,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
