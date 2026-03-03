import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/scanned_document.dart';
import '../services/app_state.dart';
import '../services/export_service.dart';
import '../services/file_import_service.dart';
import '../services/pdf_processing_service.dart';
import '../theme/app_theme.dart';

class CompressResultPage extends StatefulWidget {
  final File sourceFile;
  final File outputFile;
  final ImportedFileType type;
  final int beforeBytes;
  final int afterBytes;

  const CompressResultPage({
    super.key,
    required this.sourceFile,
    required this.outputFile,
    required this.type,
    required this.beforeBytes,
    required this.afterBytes,
  });

  @override
  State<CompressResultPage> createState() => _CompressResultPageState();
}

class _CompressResultPageState extends State<CompressResultPage> {
  final PdfProcessingService _pdfProcessingService = PdfProcessingService();
  final ExportService _exportService = ExportService();
  Future<Uint8List?>? _pdfPreviewFuture;
  bool _saving = false;
  ScannedDocument? _savedDoc;

  @override
  void initState() {
    super.initState();
    if (widget.type == ImportedFileType.pdf) {
      _pdfPreviewFuture = _pdfProcessingService.renderFirstPage(
        widget.outputFile,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final reduction = widget.beforeBytes <= 0
        ? 0.0
        : (1 - (widget.afterBytes / widget.beforeBytes)) * 100;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _goHome,
        ),
        title: const Text('Compress Result'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.surface,
                border: Border.all(color: AppColors.border),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.outputFile.path.split('/').last,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppColors.text,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${_format(widget.beforeBytes)} -> ${_format(widget.afterBytes)} (${reduction.toStringAsFixed(1)}%)',
                    style: const TextStyle(color: AppColors.text2),
                  ),
                  if (reduction < 3) ...[
                    const SizedBox(height: 6),
                    const Text(
                      'File already near optimized size.',
                      style: TextStyle(fontSize: 12, color: AppColors.text3),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            Expanded(child: _buildPreview()),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _share,
                    icon: const Icon(Icons.share),
                    label: const Text('Share'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _saving || _savedDoc != null
                        ? null
                        : _saveToHistory,
                    icon: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.save),
                    label: Text(_savedDoc != null ? 'Saved' : 'Save'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.text,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreview() {
    if (widget.type == ImportedFileType.pdf) {
      return Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: FutureBuilder<Uint8List?>(
          future: _pdfPreviewFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(color: AppColors.text),
              );
            }
            if (snapshot.data == null) {
              return const Center(
                child: Text(
                  'Unable to preview PDF',
                  style: TextStyle(color: AppColors.text2),
                ),
              );
            }
            return ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.memory(snapshot.data!, fit: BoxFit.contain),
            );
          },
        ),
      );
    }

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Image.file(widget.outputFile, fit: BoxFit.contain),
      ),
    );
  }

  Future<void> _saveToHistory() async {
    setState(() => _saving = true);
    try {
      final appState = context.read<AppState>();
      var pageCount = 1;
      if (widget.type == ImportedFileType.pdf) {
        final pages = await _pdfProcessingService.renderAllPages(
          widget.outputFile,
          dpi: 90,
        );
        if (pages.isNotEmpty) {
          pageCount = pages.length;
        }
      }
      final saved = await appState.importAnyFile(
        widget.outputFile,
        name: 'Compressed_${DateTime.now().millisecondsSinceEpoch}',
        pageCount: pageCount,
      );
      if (!mounted) return;
      if (saved == null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Failed to save file')));
        return;
      }

      if (widget.type == ImportedFileType.image) {
        await _exportService.saveImagesToGallery([widget.outputFile]);
      }
      if (!mounted) return;

      setState(() => _savedDoc = saved);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Compressed file saved successfully')),
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _share() async {
    if (!await widget.outputFile.exists()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Compressed file not found')),
      );
      return;
    }
    await Share.shareXFiles([
      XFile(widget.outputFile.path),
    ], text: 'Compressed via DocScan');
  }

  String _format(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  void _goHome() {
    Navigator.of(context).popUntil((route) => route.isFirst);
  }
}
