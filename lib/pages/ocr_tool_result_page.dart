import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../services/ocr_service.dart';
import '../services/ocr_tool_service.dart';
import '../theme/app_theme.dart';

class OcrToolResultPage extends StatefulWidget {
  final OcrToolPageResult result;
  final VoidCallback? onBackToHome;

  const OcrToolResultPage({super.key, required this.result, this.onBackToHome});

  @override
  State<OcrToolResultPage> createState() => _OcrToolResultPageState();
}

class _OcrToolResultPageState extends State<OcrToolResultPage> {
  int _currentPage = 0;
  bool _editMode = false;
  bool _cardVisible = false;
  late List<TextEditingController> _controllers;

  @override
  void initState() {
    super.initState();
    final normalized = widget.result.pages
        .map(_buildSourceText)
        .map(_formatForRead)
        .toList(growable: false);
    _controllers = normalized
        .map((text) => TextEditingController(text: text))
        .toList(growable: false);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _cardVisible = true);
    });
  }

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
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
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _goHome,
        ),
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
            const SizedBox(height: 10),
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
            const Text(
              'Extracted Text',
              style: TextStyle(
                color: AppColors.text2,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: AnimatedOpacity(
                opacity: _cardVisible ? 1 : 0,
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeOut,
                child: AnimatedSlide(
                  offset: _cardVisible ? Offset.zero : const Offset(0, 0.03),
                  duration: const Duration(milliseconds: 280),
                  curve: Curves.easeOutCubic,
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
                              height: 1.7,
                              color: AppColors.text,
                            ),
                            decoration: const InputDecoration(
                              border: InputBorder.none,
                              hintText: 'No text detected',
                            ),
                          )
                        : SingleChildScrollView(
                            child: SelectableText(
                              currentController?.text ?? '',
                              style: const TextStyle(
                                fontSize: 16,
                                height: 1.75,
                                color: AppColors.text,
                              ),
                              textAlign: TextAlign.left,
                            ),
                          ),
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

  String _buildSourceText(OcrResult page) {
    if (page.blocks.isEmpty) return page.text;

    final blockTexts = <String>[];
    for (final block in page.blocks) {
      final lines = block.lines
          .map((line) => line.replaceAll(RegExp(r'\s+'), ' ').trim())
          .where((line) => line.isNotEmpty && !_isNoiseLine(line))
          .toList(growable: false);
      if (lines.isEmpty) continue;
      blockTexts.add(lines.join('\n'));
    }

    if (blockTexts.isNotEmpty) {
      return blockTexts.join('\n\n');
    }
    return page.text;
  }

  String _formatForRead(String raw) {
    if (raw.trim().isEmpty) return '';

    final lines = raw
        .replaceAll('\r\n', '\n')
        .split('\n')
        .map((line) => line.replaceAll(RegExp(r'\s+'), ' ').trim())
        .where((line) => !_isNoiseLine(line))
        .toList(growable: false);

    final paragraphs = <String>[];
    final buffer = StringBuffer();

    for (final line in lines) {
      if (line.isEmpty) {
        _flushParagraph(paragraphs, buffer);
        continue;
      }

      final isBullet = RegExp(r'^([-*]|[0-9]+[.)])\s+').hasMatch(line);
      final isHeading =
          line.length <= 70 &&
          RegExp(r'^[A-Z][A-Za-z0-9\s,:()\-]+$').hasMatch(line);
      final looksLikeTable =
          RegExp(r'[:|]').hasMatch(line) &&
          line.split(RegExp(r'\s+')).length >= 3;

      if (isBullet || isHeading || looksLikeTable) {
        _flushParagraph(paragraphs, buffer);
        paragraphs.add(line);
        continue;
      }

      if (buffer.isEmpty) {
        buffer.write(line);
        continue;
      }

      final current = buffer.toString();
      final endsSentence = RegExp(r'[.!?;:]$').hasMatch(current);
      final shortLineBreak =
          line.length < 24 && RegExp(r'^[A-Z0-9]').hasMatch(line);

      if (current.endsWith('-')) {
        buffer
          ..clear()
          ..write(current.substring(0, current.length - 1))
          ..write(line);
      } else if (endsSentence || shortLineBreak) {
        _flushParagraph(paragraphs, buffer);
        buffer.write(line);
      } else {
        buffer.write(' $line');
      }
    }

    _flushParagraph(paragraphs, buffer);
    return paragraphs.join('\n\n').replaceAll(RegExp(r'\n{3,}'), '\n\n');
  }

  bool _isNoiseLine(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) return false;
    if (RegExp(r'^\d{1,2}:\d{2}(\s?[APap][Mm])?$').hasMatch(trimmed)) {
      return true;
    }
    if (RegExp(r'^(no sim)$', caseSensitive: false).hasMatch(trimmed)) {
      return true;
    }
    if (RegExp(r'^[<>|]+$').hasMatch(trimmed)) return true;
    if (trimmed.length <= 2 && RegExp(r'^[^A-Za-z0-9]+$').hasMatch(trimmed)) {
      return true;
    }
    return false;
  }

  String _allText() {
    return _controllers
        .map((controller) => controller.text.trim())
        .where((text) => text.isNotEmpty)
        .join('\n\n');
  }

  Future<void> _copyCurrent() async {
    if (_controllers.isEmpty) return;
    final safePage = _currentPage.clamp(0, _controllers.length - 1);
    await Clipboard.setData(ClipboardData(text: _controllers[safePage].text));
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

  void _flushParagraph(List<String> paragraphs, StringBuffer buffer) {
    if (buffer.isEmpty) return;
    paragraphs.add(buffer.toString().trim());
    buffer.clear();
  }

  void _goHome() {
    if (widget.onBackToHome != null) {
      Navigator.of(context).pop();
      widget.onBackToHome!.call();
      return;
    }
    Navigator.of(context).popUntil((route) => route.isFirst);
  }
}
