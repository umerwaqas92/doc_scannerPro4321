import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../services/ocr_service.dart';
import '../services/ocr_tool_service.dart';
import '../theme/app_theme.dart';

enum _ReadLayoutMode { clean, raw }

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
  _ReadLayoutMode _readLayoutMode = _ReadLayoutMode.clean;
  late List<String> _rawTexts;
  late List<TextEditingController> _cleanControllers;

  @override
  void initState() {
    super.initState();
    _rawTexts = widget.result.pages
        .map((page) => _normalizeRaw(_buildRawText(page)))
        .toList(growable: false);
    _cleanControllers = _rawTexts
        .map((raw) => TextEditingController(text: _normalizeForRead(raw)))
        .toList(growable: false);
  }

  @override
  void dispose() {
    for (final c in _cleanControllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.result.pages.length;
    final safePage = total == 0 ? 0 : _currentPage.clamp(0, total - 1);
    final currentController = total == 0 ? null : _cleanControllers[safePage];
    final pageText = total == 0
        ? ''
        : _currentDisplayText(safePage, cleanController: currentController);

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
            if (!_editMode) ...[
              const SizedBox(height: 8),
              SegmentedButton<_ReadLayoutMode>(
                segments: const [
                  ButtonSegment<_ReadLayoutMode>(
                    value: _ReadLayoutMode.clean,
                    label: Text('Clean'),
                  ),
                  ButtonSegment<_ReadLayoutMode>(
                    value: _ReadLayoutMode.raw,
                    label: Text('Raw'),
                  ),
                ],
                selected: {_readLayoutMode},
                onSelectionChanged: (selection) {
                  if (selection.isEmpty) return;
                  setState(() => _readLayoutMode = selection.first);
                },
              ),
            ],
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
                          pageText,
                          style: TextStyle(
                            fontSize: _readLayoutMode == _ReadLayoutMode.raw
                                ? 15
                                : 16,
                            height: _readLayoutMode == _ReadLayoutMode.raw
                                ? 1.6
                                : 1.7,
                            color: AppColors.text,
                            letterSpacing:
                                _readLayoutMode == _ReadLayoutMode.raw
                                ? 0
                                : 0.1,
                            fontFamily: _readLayoutMode == _ReadLayoutMode.raw
                                ? 'monospace'
                                : null,
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
        _flushParagraph(paragraphs, buffer);
        continue;
      }

      final isBullet = RegExp(r'^([-*•]|[0-9]+[.)])\s+').hasMatch(line);
      final isHeading =
          line.length <= 65 &&
          RegExp(r'^[A-Z][A-Za-z0-9\s,:-]+$').hasMatch(line);
      final looksLikeTableRow =
          RegExp(r'[:|]').hasMatch(line) &&
          line.split(RegExp(r'\s+')).length >= 3;

      if (isBullet || isHeading || looksLikeTableRow) {
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
          line.length < 24 && !RegExp(r'^[a-z]').hasMatch(line);
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

  String _normalizeRaw(String raw) {
    if (raw.trim().isEmpty) return '';
    return raw
        .replaceAll('\r\n', '\n')
        .split('\n')
        .map((line) => line.replaceAll(RegExp(r'[ \t]+$'), ''))
        .join('\n')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }

  String _buildRawText(OcrResult page) {
    final blocks = page.blocks;
    if (blocks.isNotEmpty) {
      final grouped = blocks
          .map((block) {
            final lines = block.lines
                .map((line) => line.replaceAll(RegExp(r'\s+$'), ''))
                .where((line) => line.trim().isNotEmpty)
                .toList(growable: false);
            return lines.join('\n');
          })
          .where((blockText) => blockText.trim().isNotEmpty)
          .toList(growable: false);
      if (grouped.isNotEmpty) {
        return grouped.join('\n\n');
      }
    }
    return page.text;
  }

  String _currentDisplayText(
    int pageIndex, {
    required TextEditingController? cleanController,
  }) {
    if (_editMode || _readLayoutMode == _ReadLayoutMode.clean) {
      return _normalizeForRead(cleanController?.text ?? '');
    }
    if (pageIndex < _rawTexts.length) {
      return _normalizeRaw(_rawTexts[pageIndex]);
    }
    return '';
  }

  String _allText() {
    if (_readLayoutMode == _ReadLayoutMode.raw && !_editMode) {
      return _rawTexts
          .map(_normalizeRaw)
          .where((text) => text.isNotEmpty)
          .join('\n\n');
    }
    return _cleanControllers
        .map((controller) => _normalizeForRead(controller.text))
        .where((text) => text.isNotEmpty)
        .join('\n\n');
  }

  Future<void> _copyCurrent() async {
    if (_cleanControllers.isEmpty) return;
    final safePage = _currentPage.clamp(0, _cleanControllers.length - 1);
    final text = _currentDisplayText(
      safePage,
      cleanController: _cleanControllers[safePage],
    );
    await Clipboard.setData(ClipboardData(text: text));
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
