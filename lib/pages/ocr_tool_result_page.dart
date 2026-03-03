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
  bool _editMode = false;
  late List<TextEditingController> _controllers;

  @override
  void initState() {
    super.initState();
    _controllers = widget.result.pages
        .map(
          (page) => TextEditingController(text: _normalizeForRead(page.text)),
        )
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
            Row(
              children: [
                if (total > 1)
                  Row(
                    children: [
                      const Text(
                        'Page:',
                        style: TextStyle(color: AppColors.text2),
                      ),
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
                const Spacer(),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment<bool>(value: false, label: Text('Read')),
                    ButtonSegment<bool>(value: true, label: Text('Edit')),
                  ],
                  selected: {_editMode},
                  onSelectionChanged: (selection) {
                    if (selection.isEmpty) return;
                    setState(() => _editMode = selection.first);
                  },
                ),
              ],
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
                child: total == 0
                    ? const Center(
                        child: Text(
                          'No text found',
                          style: TextStyle(color: AppColors.text2),
                        ),
                      )
                    : _editMode
                    ? TextField(
                        controller: currentController,
                        maxLines: null,
                        expands: true,
                        textAlignVertical: TextAlignVertical.top,
                        style: const TextStyle(
                          fontSize: 15,
                          height: 1.55,
                          color: AppColors.text,
                        ),
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          hintText: 'No text detected',
                        ),
                      )
                    : SingleChildScrollView(
                        child: SelectableText(
                          _normalizeForRead(currentController?.text ?? ''),
                          style: const TextStyle(
                            fontSize: 16,
                            height: 1.65,
                            color: AppColors.text,
                            letterSpacing: 0.1,
                          ),
                          textAlign: TextAlign.left,
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

  String _normalizeForRead(String raw) {
    if (raw.trim().isEmpty) return '';
    final lines = raw
        .replaceAll('\r\n', '\n')
        .split('\n')
        .map((line) => line.replaceAll(RegExp(r'\s+'), ' ').trim())
        .toList(growable: false);

    final paragraphs = <String>[];
    final buffer = StringBuffer();

    for (final line in lines) {
      if (line.isEmpty) {
        if (buffer.isNotEmpty) {
          paragraphs.add(buffer.toString().trim());
          buffer.clear();
        }
        continue;
      }

      if (buffer.isEmpty) {
        buffer.write(line);
        continue;
      }

      final current = buffer.toString();
      final endsSentence = RegExp(r'[.!?;:]$').hasMatch(current);
      final forceBreak = line.length < 26;
      if (endsSentence || forceBreak) {
        paragraphs.add(current.trim());
        buffer
          ..clear()
          ..write(line);
      } else {
        buffer.write(' $line');
      }
    }

    if (buffer.isNotEmpty) {
      paragraphs.add(buffer.toString().trim());
    }

    return paragraphs.join('\n\n').replaceAll(RegExp(r'\n{3,}'), '\n\n');
  }

  String _allText() {
    return _controllers
        .map((controller) => _normalizeForRead(controller.text))
        .where((text) => text.isNotEmpty)
        .join('\n\n');
  }

  Future<void> _copyCurrent() async {
    await Clipboard.setData(
      ClipboardData(text: _normalizeForRead(_controllers[_currentPage].text)),
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
