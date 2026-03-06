import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../services/ocr_service.dart';
import '../services/ocr_tool_service.dart';
import '../theme/app_theme.dart';

class ClearScanResultPage extends StatefulWidget {
  final OcrToolPageResult result;

  const ClearScanResultPage({super.key, required this.result});

  @override
  State<ClearScanResultPage> createState() => _ClearScanResultPageState();
}

class _ClearScanResultPageState extends State<ClearScanResultPage> {
  int _currentPage = 0;
  int _tab = 0; // 0 = clear view, 1 = text
  bool _editMode = false;
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
    if (widget.result.clearPages.isEmpty) {
      _tab = 1;
    }
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
    final totalPages = widget.result.pages.length;
    final totalClearPages = widget.result.clearPages.length;
    final maxPages =
        totalPages > totalClearPages ? totalPages : totalClearPages;
    final safePage = maxPages == 0 ? 0 : _currentPage.clamp(0, maxPages - 1);
    final hasClearView = totalClearPages > 0;
    final showClearView = hasClearView && _tab == 0;
    final textController =
        totalPages == 0
            ? null
            : _controllers[safePage.clamp(0, totalPages - 1)];
    final clearFile =
        hasClearView
            ? widget.result.clearPages[safePage.clamp(0, totalClearPages - 1)]
            : null;

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        title: const Text('Clear Scan Result'),
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
                if (maxPages > 1)
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
                          maxPages,
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
                if (hasClearView)
                  SegmentedButton<int>(
                    segments: const [
                      ButtonSegment<int>(
                        value: 0,
                        icon: Icon(Icons.auto_fix_high),
                        label: Text('Clear View'),
                      ),
                      ButtonSegment<int>(
                        value: 1,
                        icon: Icon(Icons.text_fields),
                        label: Text('Text'),
                      ),
                    ],
                    selected: {_tab},
                    onSelectionChanged: (selection) {
                      if (selection.isEmpty) return;
                      setState(() => _tab = selection.first);
                    },
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (!showClearView)
              Align(
                alignment: Alignment.centerRight,
                child: SegmentedButton<bool>(
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
              ),
            const SizedBox(height: 8),
            Text(
              showClearView ? 'Clear Scan Output' : 'Readable Text Output',
              style: const TextStyle(
                color: AppColors.text2,
                fontWeight: FontWeight.w600,
              ),
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
                child:
                    showClearView
                        ? _buildClearViewCard(clearFile)
                        : _buildTextCard(textController, totalPages),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: totalPages == 0 ? null : _copyCurrent,
                    icon: const Icon(Icons.copy),
                    label: const Text('Copy Page'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: totalPages == 0 ? null : _copyAll,
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
                onPressed: totalPages == 0 ? null : _shareAll,
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

  Widget _buildClearViewCard(File? clearFile) {
    if (clearFile == null) {
      return const Center(
        child: Text(
          'No clear scan image available',
          style: TextStyle(color: AppColors.text2),
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: InteractiveViewer(
        minScale: 1.0,
        maxScale: 5.0,
        child: Image.file(
          clearFile,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) {
            return const Center(
              child: Text(
                'Failed to load clear scan image',
                style: TextStyle(color: AppColors.text2),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildTextCard(TextEditingController? controller, int totalPages) {
    if (totalPages == 0 || controller == null) {
      return const Center(
        child: Text('No text found', style: TextStyle(color: AppColors.text2)),
      );
    }
    if (_editMode) {
      return TextField(
        controller: controller,
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
      );
    }
    return SingleChildScrollView(
      child: SelectableText(
        controller.text,
        style: const TextStyle(
          fontSize: 16,
          height: 1.75,
          color: AppColors.text,
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No text to share')));
      return;
    }
    await Share.share(all, subject: 'Clear Scan Text');
  }

  void _flushParagraph(List<String> paragraphs, StringBuffer buffer) {
    if (buffer.isEmpty) return;
    paragraphs.add(buffer.toString().trim());
    buffer.clear();
  }
}
