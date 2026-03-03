import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/scanned_document.dart';
import '../services/app_state.dart';
import '../services/ocr_tool_service.dart';
import '../services/pdf_processing_service.dart';
import '../theme/app_theme.dart';
import 'ocr_tool_result_page.dart';
import 'pdf_edit_page.dart';

class PdfResultPage extends StatefulWidget {
  final ScannedDocument document;
  final VoidCallback? onBack;
  final ValueChanged<ScannedDocument>? onDocumentChanged;

  const PdfResultPage({
    super.key,
    required this.document,
    this.onBack,
    this.onDocumentChanged,
  });

  @override
  State<PdfResultPage> createState() => _PdfResultPageState();
}

class _PdfResultPageState extends State<PdfResultPage> {
  final PdfProcessingService _pdfProcessingService = PdfProcessingService();
  final OcrToolService _ocrToolService = OcrToolService();

  late ScannedDocument _document;
  Future<Uint8List?>? _previewFuture;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    _document = widget.document;
    _previewFuture = _loadPreview();
  }

  @override
  void dispose() {
    _ocrToolService.dispose();
    super.dispose();
  }

  Future<Uint8List?> _loadPreview() async {
    if (!_document.isPdf) return null;
    return _pdfProcessingService.renderFirstPage(
      File(_document.filePath),
      dpi: 130,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (widget.onBack != null) {
              widget.onBack!();
            } else {
              Navigator.of(context).pop();
            }
          },
        ),
        title: const Text('Result PDF'),
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _document.name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.text,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _buildPreview(),
                  const SizedBox(height: 16),
                  _buildActionTiles(),
                  const SizedBox(height: 12),
                  _buildInfoCard(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreview() {
    final file = File(_document.filePath);
    if (!file.existsSync()) {
      return Container(
        height: 360,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: const Center(
          child: Text('File not found', style: TextStyle(color: Colors.red)),
        ),
      );
    }

    return Container(
      height: 420,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: _document.isPdf
          ? FutureBuilder<Uint8List?>(
              future: _previewFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(color: AppColors.text),
                  );
                }
                final bytes = snapshot.data;
                if (bytes == null) {
                  return const Center(
                    child: Text(
                      'Unable to render PDF preview',
                      style: TextStyle(color: AppColors.text2),
                    ),
                  );
                }
                return ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.memory(bytes, fit: BoxFit.contain),
                );
              },
            )
          : ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.file(file, fit: BoxFit.contain),
            ),
    );
  }

  Widget _buildActionTiles() {
    return Row(
      children: [
        _buildActionTile(Icons.save_outlined, 'Save', _working ? null : _save),
        _buildActionTile(
          Icons.share_outlined,
          'Share',
          _working ? null : _share,
        ),
        _buildActionTile(
          Icons.text_snippet_outlined,
          'OCR',
          _working ? null : _ocr,
        ),
        _buildActionTile(Icons.edit_outlined, 'Edit', _working ? null : _edit),
      ],
    );
  }

  Widget _buildActionTile(IconData icon, String label, VoidCallback? onTap) {
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
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          _buildInfoRow('Type', _document.isPdf ? 'PDF' : 'Image'),
          const Divider(height: 1, color: AppColors.border),
          _buildInfoRow('Pages', '${_document.pageCount}'),
          const Divider(height: 1, color: AppColors.border),
          _buildInfoRow('Size', _document.formattedSize),
          const Divider(height: 1, color: AppColors.border),
          _buildInfoRow('Scanned', _document.formattedDate),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: AppColors.text3)),
          Text(
            value,
            style: const TextStyle(
              color: AppColors.text,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    setState(() => _working = true);
    try {
      final appState = context.read<AppState>();
      final file = File(_document.filePath);
      if (!await file.exists()) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Document file missing')));
        return;
      }

      final baseName = _document.name
          .replaceAll('.pdf', '')
          .replaceAll('.PDF', '');
      final saved = await appState.importAnyFile(
        file,
        name: '${baseName}_saved',
        pageCount: _document.pageCount,
      );
      if (!mounted) return;
      if (saved == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to save document')),
        );
        return;
      }
      setState(() => _document = saved);
      widget.onDocumentChanged?.call(saved);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Document saved successfully')),
      );
    } finally {
      if (mounted) {
        setState(() => _working = false);
      }
    }
  }

  Future<void> _share() async {
    final file = File(_document.filePath);
    if (!await file.exists()) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('File not found')));
      return;
    }
    await Share.shareXFiles([XFile(file.path)], text: 'Shared from DocScan');
  }

  Future<void> _ocr() async {
    setState(() => _working = true);
    try {
      final file = File(_document.filePath);
      if (!await file.exists()) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('File not found')));
        return;
      }

      final result = _document.isPdf
          ? await _ocrToolService.processPdf(file)
          : await _ocrToolService.processImage(file);

      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => OcrToolResultPage(result: result)),
      );
    } finally {
      if (mounted) {
        setState(() => _working = false);
      }
    }
  }

  Future<void> _edit() async {
    if (!_document.isPdf) return;
    final updated = await Navigator.of(context).push<ScannedDocument>(
      MaterialPageRoute(builder: (_) => PdfEditPage(sourceDocument: _document)),
    );
    if (!mounted || updated == null) return;

    setState(() {
      _document = updated;
      _previewFuture = _loadPreview();
    });
    widget.onDocumentChanged?.call(updated);
  }
}
