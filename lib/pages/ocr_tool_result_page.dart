import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../services/ocr_tool_service.dart';
import '../theme/app_theme.dart';

class OcrToolResultPage extends StatefulWidget {
  final OcrToolPageResult result;

  const OcrToolResultPage({super.key, required this.result});

  @override
  State<OcrToolResultPage> createState() => _OcrToolResultPageState();
}

class _OcrToolResultPageState extends State<OcrToolResultPage> {
  int _currentPage = 0;
  late List<TextEditingController> _controllers;

  @override
  void initState() {
    super.initState();
    _controllers = widget.result.pages
        .map((page) => TextEditingController(text: page.text))
        .toList(growable: false);
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.result.pages.length;
    final safePage = total == 0 ? 0 : _currentPage.clamp(0, total - 1);
    final currentController = total == 0 ? null : _controllers[safePage];

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        title: const Text('OCR Result'),
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
            const SizedBox(height: 8),
            if (total > 1)
              Row(
                children: [
                  const Text('Page:', style: TextStyle(color: AppColors.text2)),
                  const SizedBox(width: 8),
                  DropdownButton<int>(
                    value: safePage,
                    items: List.generate(
                      total,
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
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: total == 0
                    ? const Center(
                        child: Text(
                          'No text found',
                          style: TextStyle(color: AppColors.text2),
                        ),
                      )
                    : TextField(
                        controller: currentController,
                        maxLines: null,
                        expands: true,
                        textAlignVertical: TextAlignVertical.top,
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          hintText: 'No text detected',
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: total == 0 ? null : _copyCurrent,
                    icon: const Icon(Icons.copy),
                    label: const Text('Copy Page'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: total == 0 ? null : _copyAll,
                    icon: const Icon(Icons.copy_all),
                    label: const Text('Copy All'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: total == 0 ? null : _shareAll,
                icon: const Icon(Icons.share),
                label: const Text('Share Text'),
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

  String _allText() {
    return _controllers
        .map((controller) => controller.text.trim())
        .where((text) => text.isNotEmpty)
        .join('\n\n');
  }

  Future<void> _copyCurrent() async {
    await Clipboard.setData(
      ClipboardData(text: _controllers[_currentPage].text),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Copied current page text')));
  }

  Future<void> _copyAll() async {
    final all = _allText();
    await Clipboard.setData(ClipboardData(text: all));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Copied all text')));
  }

  Future<void> _shareAll() async {
    final all = _allText();
    if (all.trim().isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No extracted text to share')),
      );
      return;
    }
    await Share.share(all, subject: 'OCR Text from DocScan');
  }
}
