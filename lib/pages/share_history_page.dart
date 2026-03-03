import 'dart:io';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../models/scanned_document.dart';
import '../theme/app_theme.dart';

class ShareHistoryPage extends StatefulWidget {
  final List<ScannedDocument> documents;

  const ShareHistoryPage({super.key, required this.documents});

  @override
  State<ShareHistoryPage> createState() => _ShareHistoryPageState();
}

class _ShareHistoryPageState extends State<ShareHistoryPage> {
  final Set<String> _selectedIds = <String>{};
  bool _sharing = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        title: const Text('Share Documents'),
      ),
      body: Column(
        children: [
          Expanded(
            child: widget.documents.isEmpty
                ? const Center(
                    child: Text(
                      'No documents in history',
                      style: TextStyle(color: AppColors.text2),
                    ),
                  )
                : ListView.builder(
                    itemCount: widget.documents.length,
                    itemBuilder: (context, index) {
                      final doc = widget.documents[index];
                      final checked = _selectedIds.contains(doc.id);
                      return CheckboxListTile(
                        value: checked,
                        onChanged: (_) {
                          setState(() {
                            if (checked) {
                              _selectedIds.remove(doc.id);
                            } else {
                              _selectedIds.add(doc.id);
                            }
                          });
                        },
                        title: Text(
                          doc.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${doc.isPdf ? 'PDF' : 'Image'} • ${doc.formattedSize}',
                        ),
                        secondary: Icon(
                          doc.isPdf ? Icons.picture_as_pdf : Icons.image,
                          color: doc.isPdf
                              ? AppColors.pdfRedText
                              : AppColors.jpgBlueText,
                        ),
                      );
                    },
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: (_selectedIds.isEmpty || _sharing)
                    ? null
                    : _shareSelected,
                icon: _sharing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.share),
                label: Text(_sharing ? 'Sharing...' : 'Share Selected'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.text,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _shareSelected() async {
    setState(() => _sharing = true);
    try {
      final picked = widget.documents.where((d) => _selectedIds.contains(d.id));
      final files = <XFile>[];
      for (final doc in picked) {
        final file = File(doc.filePath);
        if (await file.exists()) {
          files.add(XFile(file.path));
        }
      }

      if (files.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No valid files available to share')),
        );
        return;
      }

      await Share.shareXFiles(files, text: 'Shared from DocScan');
    } finally {
      if (mounted) {
        setState(() => _sharing = false);
      }
    }
  }
}
