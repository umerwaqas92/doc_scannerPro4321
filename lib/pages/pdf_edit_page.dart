import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/scanned_document.dart';
import '../services/app_state.dart';
import '../services/pdf_processing_service.dart';
import '../theme/app_theme.dart';

class PdfEditPage extends StatefulWidget {
  final ScannedDocument sourceDocument;

  const PdfEditPage({super.key, required this.sourceDocument});

  @override
  State<PdfEditPage> createState() => _PdfEditPageState();
}

class _PdfEditPageState extends State<PdfEditPage> {
  final PdfProcessingService _pdfProcessingService = PdfProcessingService();
  final TextEditingController _nameController = TextEditingController();

  List<Uint8List> _pages = <Uint8List>[];
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameController.text = widget.sourceDocument.name
        .replaceAll('.pdf', '')
        .replaceAll('.PDF', '');
    _loadPages();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _loadPages() async {
    final file = File(widget.sourceDocument.filePath);
    final pages = await _pdfProcessingService.renderAllPages(file, dpi: 120);
    if (!mounted) return;
    setState(() {
      _pages = pages;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        title: const Text('Edit PDF'),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.text),
            )
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  TextField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'Output file name',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_pages.isEmpty)
                    const Expanded(
                      child: Center(
                        child: Text(
                          'No PDF pages found',
                          style: TextStyle(color: AppColors.text2),
                        ),
                      ),
                    )
                  else
                    Expanded(
                      child: ReorderableListView.builder(
                        itemCount: _pages.length,
                        onReorder: _onReorder,
                        itemBuilder: (context, index) {
                          return Card(
                            key: ValueKey('pdf_page_$index'),
                            margin: const EdgeInsets.only(bottom: 10),
                            child: Padding(
                              padding: const EdgeInsets.all(8),
                              child: Row(
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(6),
                                    child: Image.memory(
                                      _pages[index],
                                      width: 72,
                                      height: 96,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      'Page ${index + 1}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'Rotate Left',
                                    onPressed: () => _rotatePage(index, -90),
                                    icon: const Icon(Icons.rotate_left),
                                  ),
                                  IconButton(
                                    tooltip: 'Rotate Right',
                                    onPressed: () => _rotatePage(index, 90),
                                    icon: const Icon(Icons.rotate_right),
                                  ),
                                  IconButton(
                                    tooltip: 'Delete Page',
                                    onPressed: _pages.length == 1
                                        ? null
                                        : () => _deletePage(index),
                                    icon: const Icon(
                                      Icons.delete_outline,
                                      color: Colors.red,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: (_saving || _pages.isEmpty) ? null : _savePdf,
                      icon: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.save_alt),
                      label: Text(_saving ? 'Saving...' : 'Save Edited PDF'),
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

  void _onReorder(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) {
        newIndex -= 1;
      }
      final item = _pages.removeAt(oldIndex);
      _pages.insert(newIndex, item);
    });
  }

  void _rotatePage(int index, int angle) {
    final rotated = _pdfProcessingService.rotateImage(
      _pages[index],
      angle: angle,
    );
    if (rotated == null) return;
    setState(() => _pages[index] = rotated);
  }

  void _deletePage(int index) {
    setState(() => _pages.removeAt(index));
  }

  Future<void> _savePdf() async {
    setState(() => _saving = true);
    try {
      final fileName = _nameController.text.trim().isEmpty
          ? 'EditedPDF'
          : _nameController.text.trim();
      final out = await _pdfProcessingService.buildPdfFromPageImages(
        _pages,
        fileName: '${fileName}_edited',
      );
      if (!mounted) return;
      if (out == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to build edited PDF')),
        );
        return;
      }

      final appState = context.read<AppState>();
      final saved = await appState.importAnyFile(
        out,
        name: fileName,
        pageCount: _pages.length,
      );
      if (!mounted) return;
      if (saved == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to save edited PDF')),
        );
        return;
      }
      Navigator.of(context).pop(saved);
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }
}
