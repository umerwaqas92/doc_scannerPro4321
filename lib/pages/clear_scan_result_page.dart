import 'dart:io';
import 'package:flutter/material.dart';
import '../services/export_service.dart';
import '../services/ocr_tool_service.dart';
import '../theme/app_theme.dart';

class ClearScanResultPage extends StatefulWidget {
  final OcrToolPageResult result;

  const ClearScanResultPage({super.key, required this.result});

  @override
  State<ClearScanResultPage> createState() => _ClearScanResultPageState();
}

class _ClearScanResultPageState extends State<ClearScanResultPage> {
  final ExportService _exportService = ExportService();
  int _currentPage = 0;

  @override
  Widget build(BuildContext context) {
    final totalClearPages = widget.result.clearPages.length;
    final safePage =
        totalClearPages == 0 ? 0 : _currentPage.clamp(0, totalClearPages - 1);
    final clearFile =
        totalClearPages == 0 ? null : widget.result.clearPages[safePage];

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        title: const Text('Clear Scan Result'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.result.sourceName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.text2),
            ),
            const SizedBox(height: 10),
            if (totalClearPages > 1)
              Row(
                children: [
                  const Text('Page:', style: TextStyle(color: AppColors.text2)),
                  const SizedBox(width: 8),
                  DropdownButton<int>(
                    value: safePage,
                    items: List.generate(
                      totalClearPages,
                      (index) => DropdownMenuItem<int>(
                        value: index,
                        child: Text('Page ${index + 1}'),
                      ),
                    ),
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() => _currentPage = value);
                    },
                  ),
                ],
              ),
            const SizedBox(height: 8),
            const Text(
              'Clear Scan Output',
              style: TextStyle(
                color: AppColors.text2,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: _buildClearViewCard(clearFile),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed:
                    clearFile == null
                        ? null
                        : () => _saveCurrentClearImage(clearFile),
                icon: const Icon(Icons.save_alt),
                label: const Text('Save Clear Image'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.text,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildClearViewCard(File? clearFile) {
    if (clearFile == null) {
      return const Center(
        child: Text(
          'No clear scan image available',
          style: TextStyle(color: AppColors.text2),
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: InteractiveViewer(
        minScale: 1.0,
        maxScale: 5.0,
        child: Image.file(
          clearFile,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) {
            return const Center(
              child: Text(
                'Failed to load clear scan image',
                style: TextStyle(color: AppColors.text2),
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _saveCurrentClearImage(File clearFile) async {
    final result = await _exportService.saveImagesToGallery([clearFile]);
    if (!mounted) return;

    if (result.saved > 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Clear image saved')));
      return;
    }

    final message =
        result.errors.isNotEmpty
            ? result.errors.first
            : 'Failed to save clear image';
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}
