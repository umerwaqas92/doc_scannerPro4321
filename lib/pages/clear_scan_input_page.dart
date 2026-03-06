import 'package:flutter/material.dart';
import '../services/file_import_service.dart';
import '../services/ocr_tool_service.dart';
import '../theme/app_theme.dart';
import 'clear_scan_result_page.dart';

class ClearScanInputPage extends StatefulWidget {
  const ClearScanInputPage({super.key});

  @override
  State<ClearScanInputPage> createState() => _ClearScanInputPageState();
}

class _ClearScanInputPageState extends State<ClearScanInputPage> {
  final FileImportService _importService = FileImportService();
  final OcrToolService _ocrToolService = OcrToolService();

  ImportedFile? _selected;
  bool _picking = false;
  bool _processing = false;

  @override
  void dispose() {
    _ocrToolService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selectedName =
        _selected?.file.path.split('/').last ?? 'No file selected';
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        title: const Text('Clear Scan'),
      ),
      body: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildImportCard(selectedName),
                const SizedBox(height: 14),
                Expanded(child: _buildPreviewCard()),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed:
                      (_selected == null || _processing)
                          ? null
                          : _processSelected,
                  icon:
                      _processing
                          ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                          : const Icon(Icons.auto_fix_high),
                  label: Text(_processing ? 'Processing...' : 'Scan & Clear'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.text,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ],
            ),
          ),
          if (_processing) _buildProcessingOverlay(),
        ],
      ),
    );
  }

  Widget _buildImportCard(String selectedName) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Add Document',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            selectedName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppColors.text2),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _picking ? null : _pickImage,
                  icon: const Icon(Icons.photo),
                  label: const Text('Add Image'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _picking ? null : _pickPdf,
                  icon: const Icon(Icons.picture_as_pdf),
                  label: const Text('Add PDF'),
                ),
              ),
            ],
          ),
          if (_picking) ...[
            const SizedBox(height: 10),
            const LinearProgressIndicator(color: AppColors.text),
          ],
        ],
      ),
    );
  }

  Widget _buildPreviewCard() {
    final selected = _selected;
    if (selected == null) {
      return Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: const Center(
          child: Text(
            'Select an image or PDF first.\nA preview appears here before processing.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.text3),
          ),
        ),
      );
    }

    if (selected.type == ImportedFileType.image) {
      return Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.file(
            selected.file,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) {
              return const Center(
                child: Text(
                  'Could not load image preview',
                  style: TextStyle(color: AppColors.text2),
                ),
              );
            },
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.all(20),
      child: const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.picture_as_pdf, size: 64, color: AppColors.text2),
          SizedBox(height: 12),
          Text(
            'PDF selected',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.text,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'All pages will be scanned, cleared, and converted to readable text.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.text2),
          ),
        ],
      ),
    );
  }

  Future<void> _pickImage() async {
    setState(() => _picking = true);
    try {
      final files = await _importService.pickImages(multiple: false);
      if (files.isEmpty || !mounted) return;
      setState(() {
        _selected = ImportedFile(
          file: files.first,
          type: ImportedFileType.image,
        );
      });
    } finally {
      if (mounted) {
        setState(() => _picking = false);
      }
    }
  }

  Future<void> _pickPdf() async {
    setState(() => _picking = true);
    try {
      final pdf = await _importService.pickPdf();
      if (pdf == null || !mounted) return;
      setState(() {
        _selected = ImportedFile(file: pdf, type: ImportedFileType.pdf);
      });
    } finally {
      if (mounted) {
        setState(() => _picking = false);
      }
    }
  }

  Future<void> _processSelected() async {
    final selected = _selected;
    if (selected == null) return;
    setState(() => _processing = true);
    try {
      final result =
          selected.type == ImportedFileType.pdf
              ? await _ocrToolService.processPdf(selected.file)
              : await _ocrToolService.processImage(selected.file);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ClearScanResultPage(result: result)),
      );
    } finally {
      if (mounted) {
        setState(() => _processing = false);
      }
    }
  }

  Widget _buildProcessingOverlay() {
    return Positioned.fill(
      child: IgnorePointer(
        child: Container(
          color: Colors.black.withValues(alpha: 0.22),
          child: const Center(
            child: CircularProgressIndicator(color: AppColors.text),
          ),
        ),
      ),
    );
  }
}
