import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/scanned_document.dart';

class HomePage extends StatefulWidget {
  final List<ScannedDocument> documents;
  final VoidCallback onScanTap;
  final ValueChanged<ScannedDocument> onDocTap;
  final VoidCallback onSeeAllTap;
  final VoidCallback onPdfToolTap;
  final VoidCallback onOcrToolTap;
  final VoidCallback onClearScanToolTap;
  final VoidCallback onShareToolTap;
  final VoidCallback onCompressToolTap;

  const HomePage({
    super.key,
    required this.documents,
    required this.onScanTap,
    required this.onDocTap,
    required this.onSeeAllTap,
    required this.onPdfToolTap,
    required this.onOcrToolTap,
    required this.onClearScanToolTap,
    required this.onShareToolTap,
    required this.onCompressToolTap,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  @override
  void initState() {
    super.initState();
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
            _buildScanBanner(),
            _buildClearScanBanner(),
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
      child: const Text(
        'DocScan',
        style: TextStyle(
          fontSize: 26,
          fontWeight: FontWeight.w600,
          color: AppColors.text,
          letterSpacing: -0.5,
        ),
      ),
    );
  }

  Widget _buildScanBanner() {
    return GestureDetector(
      onTap: widget.onScanTap,
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
                    'Doc Scanner',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Tap to scan documents',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.white.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.12),
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

  Widget _buildClearScanBanner() {
    return GestureDetector(
      onTap: widget.onClearScanToolTap,
      child: Container(
        margin: const EdgeInsets.fromLTRB(20, 0, 20, 18),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppDimens.radiusSm),
          border: Border.all(color: AppColors.border),
        ),
        child: const Row(
          children: [
            Icon(Icons.auto_fix_high, color: AppColors.text),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Clear Scan: import image/PDF and extract cleaner text',
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.text2,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Icon(Icons.arrow_forward_ios, size: 14, color: AppColors.text3),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActions() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Row(
        children: [
          _buildQuickAction(Icons.picture_as_pdf, 'PDF', widget.onPdfToolTap),
          _buildQuickAction(
            Icons.text_snippet_outlined,
            'OCR Text',
            widget.onOcrToolTap,
          ),
          _buildQuickAction(
            Icons.share_outlined,
            'Share',
            widget.onShareToolTap,
          ),
          _buildQuickAction(
            Icons.folder_zip_outlined,
            'Compress',
            widget.onCompressToolTap,
          ),
        ],
      ),
    );
  }

  Widget _buildQuickAction(IconData icon, String label, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
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
            onTap: widget.onSeeAllTap,
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
    if (widget.documents.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Container(
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(AppDimens.radiusSm),
          ),
          child: Column(
            children: [
              const Icon(
                Icons.document_scanner_outlined,
                size: 48,
                color: AppColors.text3,
              ),
              const SizedBox(height: 12),
              Text(
                'No documents yet',
                style: const TextStyle(fontSize: 14, color: AppColors.text2),
              ),
              const SizedBox(height: 4),
              Text(
                'Tap the scan button to get started',
                style: const TextStyle(fontSize: 12, color: AppColors.text3),
              ),
            ],
          ),
        ),
      );
    }

    final recentDocs = widget.documents.take(4).toList(growable: false);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(
        children: List.generate(recentDocs.length, (index) {
          final doc = recentDocs[index];
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _buildDocCard(
              document: doc,
              meta:
                  '${doc.formattedDate} · ${doc.pageCount} page${doc.pageCount > 1 ? 's' : ''} · ${doc.formattedSize}',
            ),
          );
        }),
      ),
    );
  }

  Widget _buildDocCard({
    required ScannedDocument document,
    required String meta,
  }) {
    return GestureDetector(
      onTap: () => widget.onDocTap(document),
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
                document.isPdf ? Icons.picture_as_pdf : Icons.image,
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
                    document.name,
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
                color: document.isPdf ? AppColors.pdfRed : AppColors.jpgBlue,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color:
                      document.isPdf
                          ? const Color(0xFFF5C0BB)
                          : const Color(0xFFB9D8F0),
                ),
              ),
              child: Text(
                document.isPdf ? 'PDF' : 'JPG',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                  color:
                      document.isPdf
                          ? AppColors.pdfRedText
                          : AppColors.jpgBlueText,
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
