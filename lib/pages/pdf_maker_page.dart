import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/app_state.dart';
import '../services/file_import_service.dart';
import '../theme/app_theme.dart';

class PdfMakerPage extends StatefulWidget {
  const PdfMakerPage({super.key});

  @override
  State<PdfMakerPage> createState() => _PdfMakerPageState();
}

class _PdfMakerPageState extends State<PdfMakerPage> {
  final FileImportService _importService = FileImportService();
  final TextEditingController _nameController = TextEditingController(
    text: 'MyDocument',
  );
  final List<File> _images = [];
  bool _creating = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        title: const Text('PDF Maker'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'File name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickImages,
                    icon: const Icon(Icons.photo_library),
                    label: const Text('Add Images'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _importExistingPdf,
                    icon: const Icon(Icons.upload_file),
                    label: const Text('Import PDF'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Selected images: ${_images.length}',
                style: const TextStyle(color: AppColors.text2),
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: _images.isEmpty
                  ? const Center(
                      child: Text(
                        'No images selected yet',
                        style: TextStyle(color: AppColors.text3),
                      ),
                    )
                  : GridView.builder(
                      itemCount: _images.length,
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            crossAxisSpacing: 8,
                            mainAxisSpacing: 8,
                          ),
                      itemBuilder: (context, index) {
                        return Stack(
                          children: [
                            Positioned.fill(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.file(
                                  _images[index],
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                            Positioned(
                              right: 0,
                              top: 0,
                              child: GestureDetector(
                                onTap: () =>
                                    setState(() => _images.removeAt(index)),
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.55),
                                    borderRadius: const BorderRadius.only(
                                      bottomLeft: Radius.circular(8),
                                      topRight: Radius.circular(8),
                                    ),
                                  ),
                                  padding: const EdgeInsets.all(4),
                                  child: const Icon(
                                    Icons.close,
                                    size: 16,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: (_creating || _images.isEmpty) ? null : _createPdf,
                icon: _creating
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.picture_as_pdf),
                label: Text(_creating ? 'Creating...' : 'Create PDF'),
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

  Future<void> _pickImages() async {
    final files = await _importService.pickImages(multiple: true);
    if (files.isEmpty) return;
    setState(() => _images.addAll(files));
  }

  Future<void> _createPdf() async {
    setState(() => _creating = true);
    try {
      final appState = context.read<AppState>();
      final result = await appState.createPdfFromImagesTool(
        _images,
        name: _nameController.text.trim().isEmpty
            ? 'MyDocument'
            : _nameController.text.trim(),
      );
      if (!mounted) return;
      if (result != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('PDF created and saved in history')),
        );
        Navigator.of(context).pop();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to create PDF. No valid images found.'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _creating = false);
      }
    }
  }

  Future<void> _importExistingPdf() async {
    final file = await _importService.pickPdf();
    if (file == null) return;
    if (!mounted) return;
    final appState = context.read<AppState>();
    final imported = await appState.importPdfFile(file);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          imported != null ? 'PDF added to history' : 'Failed to import PDF',
        ),
      ),
    );
    if (imported != null) {
      Navigator.of(context).pop();
    }
  }
}
