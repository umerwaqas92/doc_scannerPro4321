import 'package:flutter/material.dart';
import '../services/compression_service.dart';
import '../services/export_optimization_service.dart';
import '../services/file_import_service.dart';
import '../theme/app_theme.dart';
import 'compress_result_page.dart';

class CompressorPage extends StatefulWidget {
  const CompressorPage({super.key});

  @override
  State<CompressorPage> createState() => _CompressorPageState();
}

class _CompressorPageState extends State<CompressorPage> {
  final FileImportService _importService = FileImportService();
  final CompressionService _compressionService = CompressionService();

  ImportedFile? _selected;
  ExportQualityPreset _quality = ExportQualityPreset.medium;
  bool _pickingFile = false;
  bool _processing = false;
  int? _beforeBytes;
  int? _afterBytes;

  @override
  Widget build(BuildContext context) {
    final name = _selected?.file.path.split('/').last ?? 'No file selected';
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        title: const Text('File Compressor'),
      ),
      body: Stack(
        children: [
          Padding(
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
                      const Text(
                        'Image or PDF',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: _pickingFile ? null : _pickFile,
                        icon: const Icon(Icons.attach_file),
                        label: const Text('Choose File'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  child: _pickingFile
                      ? const LinearProgressIndicator(
                          key: ValueKey('pick_progress'),
                          color: AppColors.text,
                        )
                      : const SizedBox(key: ValueKey('pick_idle'), height: 4),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Compression level',
                  style: TextStyle(color: AppColors.text2),
                ),
                const SizedBox(height: 8),
                SegmentedButton<ExportQualityPreset>(
                  segments: const [
                    ButtonSegment(
                      value: ExportQualityPreset.high,
                      label: Text('High'),
                    ),
                    ButtonSegment(
                      value: ExportQualityPreset.medium,
                      label: Text('Medium'),
                    ),
                    ButtonSegment(
                      value: ExportQualityPreset.small,
                      label: Text('Small'),
                    ),
                  ],
                  selected: {_quality},
                  onSelectionChanged: (selection) {
                    if (selection.isEmpty) return;
                    setState(() => _quality = selection.first);
                  },
                ),
                const SizedBox(height: 14),
                if (_beforeBytes != null && _afterBytes != null)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Text(
                      'Size: ${_format(_beforeBytes!)} -> ${_format(_afterBytes!)}',
                      style: const TextStyle(color: AppColors.text2),
                    ),
                  ),
                const Spacer(),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: (_processing || _selected == null)
                        ? null
                        : _compress,
                    icon: _processing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.folder_zip),
                    label: Text(
                      _processing ? 'Compressing...' : 'Compress File',
                    ),
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
          if (_processing) _buildCompressionOverlay(),
        ],
      ),
    );
  }

  Future<void> _pickFile() async {
    setState(() => _pickingFile = true);
    try {
      final imported = await _importService.pickImageOrPdf();
      if (imported == null) return;
      final bytes = await imported.file.length();
      if (!mounted) return;
      setState(() {
        _selected = imported;
        _beforeBytes = bytes;
        _afterBytes = null;
      });
    } finally {
      if (mounted) {
        setState(() => _pickingFile = false);
      }
    }
  }

  Future<void> _compress() async {
    final selected = _selected;
    if (selected == null) return;
    final startedAt = DateTime.now();
    setState(() => _processing = true);
    try {
      final out = await _compressionService.compressFile(
        selected.file,
        quality: _quality,
      );
      if (out.path == selected.file.path) {
        throw Exception('Compression produced no output file');
      }
      final outSize = await out.length();
      final elapsed = DateTime.now().difference(startedAt);
      const minDuration = Duration(milliseconds: 700);
      if (elapsed < minDuration) {
        await Future.delayed(minDuration - elapsed);
      }
      if (!mounted) return;

      setState(() => _afterBytes = outSize);
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => CompressResultPage(
            sourceFile: selected.file,
            outputFile: out,
            type: selected.type,
            beforeBytes: _beforeBytes ?? 0,
            afterBytes: outSize,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      final message =
          e.toString().toLowerCase().contains('unsupported') ||
              e.toString().toLowerCase().contains('format')
          ? 'Compression failed. Unsupported file format.'
          : 'Compression failed: $e';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) {
        setState(() => _processing = false);
      }
    }
  }

  String _format(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Widget _buildCompressionOverlay() {
    return Positioned.fill(
      child: IgnorePointer(
        child: Container(
          color: Colors.black.withValues(alpha: 0.24),
          child: Center(
            child: Container(
              width: 230,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  CircularProgressIndicator(color: AppColors.text),
                  SizedBox(height: 12),
                  Text(
                    'Compressing file...',
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
