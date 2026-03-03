import 'package:flutter/material.dart';
import '../services/file_import_service.dart';
import '../services/ocr_tool_service.dart';
import '../theme/app_theme.dart';
import 'ocr_tool_result_page.dart';

class OcrToolInputPage extends StatefulWidget {
  const OcrToolInputPage({super.key});

  @override
  State<OcrToolInputPage> createState() => _OcrToolInputPageState();
}

class _OcrToolInputPageState extends State<OcrToolInputPage> {
  final FileImportService _importService = FileImportService();
  final OcrToolService _ocrToolService = OcrToolService();

  ImportedFile? _selected;
  bool _picking = false;
  bool _analyzing = false;

  @override
  void dispose() {
    _ocrToolService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fileName = _selected?.file.path.split('/').last ?? 'None';
    final fileType = _selected == null
        ? 'No file selected'
        : _selected!.type == ImportedFileType.pdf
        ? 'PDF file'
        : 'Image file';

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        title: const Text('OCR Text'),
      ),
      body: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Container(
                  width: double.infinity,
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
                        'Select image or PDF',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppColors.text,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        fileName,
                        style: const TextStyle(color: AppColors.text2),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        fileType,
                        style: const TextStyle(color: AppColors.text3),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _picking ? null : _pickFile,
                          icon: const Icon(Icons.attach_file),
                          label: const Text('Choose File'),
                        ),
                      ),
                      const SizedBox(height: 8),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        child: _picking
                            ? const LinearProgressIndicator(
                                key: ValueKey('ocr_pick_progress'),
                                color: AppColors.text,
                              )
                            : const SizedBox(
                                key: ValueKey('ocr_pick_idle'),
                                height: 4,
                              ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: (_selected == null || _analyzing)
                        ? null
                        : _analyze,
                    icon: _analyzing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.auto_awesome),
                    label: Text(_analyzing ? 'Analyzing...' : 'Analyze Text'),
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
          if (_analyzing) _buildAnalyzingOverlay(),
        ],
      ),
    );
  }

  Future<void> _pickFile() async {
    setState(() => _picking = true);
    try {
      final imported = await _importService.pickImageOrPdf();
      if (imported == null) return;
      if (!mounted) return;
      setState(() => _selected = imported);
    } finally {
      if (mounted) {
        setState(() => _picking = false);
      }
    }
  }

  Future<void> _analyze() async {
    final selected = _selected;
    if (selected == null) return;

    final startedAt = DateTime.now();
    setState(() => _analyzing = true);
    try {
      final result = selected.type == ImportedFileType.pdf
          ? await _ocrToolService.processPdf(selected.file)
          : await _ocrToolService.processImage(selected.file);

      final elapsed = DateTime.now().difference(startedAt);
      const minDuration = Duration(milliseconds: 700);
      if (elapsed < minDuration) {
        await Future.delayed(minDuration - elapsed);
      }

      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => OcrToolResultPage(result: result)),
      );
    } finally {
      if (mounted) {
        setState(() => _analyzing = false);
      }
    }
  }

  Widget _buildAnalyzingOverlay() {
    return Positioned.fill(
      child: IgnorePointer(
        child: Container(
          color: Colors.black.withValues(alpha: 0.25),
          child: Center(
            child: Container(
              width: 220,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0.88, end: 1.08),
                    duration: const Duration(milliseconds: 780),
                    curve: Curves.easeInOut,
                    builder: (context, value, child) =>
                        Transform.scale(scale: value, child: child),
                    child: const Icon(
                      Icons.auto_awesome,
                      color: AppColors.text,
                      size: 30,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const CircularProgressIndicator(color: AppColors.text),
                  const SizedBox(height: 12),
                  const Text(
                    'Analyzing document...',
                    style: TextStyle(
                      color: AppColors.text,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
