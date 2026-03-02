import 'dart:io';
import 'package:flutter/material.dart';
import '../models/scan_pipeline_models.dart';
import '../pages/corner_adjust_page.dart';
import '../services/document_scanner_service.dart';
import '../theme/app_theme.dart';

class ImageEditPage extends StatefulWidget {
  final List<File> images;
  final List<ScanPipelineResult?> pipelineResults;
  final VoidCallback onBack;
  final ValueChanged<List<EditSessionState>> onContinue;

  const ImageEditPage({
    super.key,
    required this.images,
    required this.pipelineResults,
    required this.onBack,
    required this.onContinue,
  });

  @override
  State<ImageEditPage> createState() => _ImageEditPageState();
}

class _ImageEditPageState extends State<ImageEditPage> {
  final DocumentScannerService _scannerService = DocumentScannerService();

  int _currentPage = 0;
  bool _isProcessing = false;
  final Set<int> _dirtyPages = <int>{};
  late List<File> _previewImages;
  late List<File?> _manualPerspectiveBases;
  late List<EditSessionState> _sessions;

  @override
  void initState() {
    super.initState();
    _previewImages = List<File>.from(widget.images);
    _manualPerspectiveBases = List<File?>.filled(widget.images.length, null);
    _sessions = List<EditSessionState>.generate(widget.images.length, (index) {
      final pipeline = index < widget.pipelineResults.length
          ? widget.pipelineResults[index]
          : null;
      final filter =
          pipeline?.selectedFilter ?? DocumentFilterMode.colorEnhanced;
      final output = pipeline?.selectedOutputFile ?? widget.images[index];
      _previewImages[index] = output;
      return EditSessionState(
        pageIndex: index,
        filterMode: filter,
        outputFile: output,
      );
    });
  }

  EditSessionState get _currentSession => _sessions[_currentPage];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.text),
          onPressed: widget.onBack,
        ),
        title: const Text(
          'Edit Document',
          style: TextStyle(color: AppColors.text),
        ),
        actions: [
          TextButton(
            onPressed: _isProcessing ? null : _continueToResult,
            child: const Text(
              'Continue',
              style: TextStyle(
                color: AppColors.text,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(child: _buildImagePreview()),
          _buildPageSelector(),
          _buildPipelineInfo(),
          _buildControls(),
        ],
      ),
    );
  }

  Widget _buildImagePreview() {
    if (_previewImages.isEmpty) {
      return const Center(child: Text('No images'));
    }

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Image.file(
            _previewImages[_currentPage],
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) {
              return const Center(child: Text('Unable to load image'));
            },
          ),
        ),
      ),
    );
  }

  Widget _buildPageSelector() {
    if (widget.images.length <= 1) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: _currentPage > 0
                ? () => setState(() => _currentPage--)
                : null,
          ),
          Text('Page ${_currentPage + 1} of ${widget.images.length}'),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: _currentPage < widget.images.length - 1
                ? () => setState(() => _currentPage++)
                : null,
          ),
        ],
      ),
    );
  }

  Widget _buildPipelineInfo() {
    final pipeline = _currentPage < widget.pipelineResults.length
        ? widget.pipelineResults[_currentPage]
        : null;

    if (pipeline == null) return const SizedBox.shrink();

    final confidence = (pipeline.detectionConfidence * 100)
        .clamp(0, 100)
        .toStringAsFixed(0);
    final warning = pipeline.usedFallback;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: warning ? const Color(0xFFFFF3E0) : AppColors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: warning ? Colors.orange : AppColors.border),
        ),
        child: Text(
          warning
              ? 'Auto edge fallback used. Detection confidence: $confidence%'
              : 'Detection confidence: $confidence%',
          style: TextStyle(
            fontSize: 12,
            color: warning ? Colors.orange.shade800 : AppColors.text2,
          ),
        ),
      ),
    );
  }

  Widget _buildControls() {
    final session = _currentSession;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSlider('Brightness', session.brightness, 0.7, 1.4, (v) {
              _updateCurrentSession(session.copyWith(brightness: v));
            }),
            _buildSlider('Contrast', session.contrast, 0.7, 2.0, (v) {
              _updateCurrentSession(session.copyWith(contrast: v));
            }),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _isProcessing ? null : _openCornerAdjust,
                icon: const Icon(Icons.crop_free),
                label: const Text('Adjust Corners'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.text,
                  side: const BorderSide(color: AppColors.border),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Filters',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: DocumentFilterMode.values.map((mode) {
                return ChoiceChip(
                  label: Text(mode.label),
                  selected: session.filterMode == mode,
                  onSelected: (_) {
                    _updateCurrentSession(session.copyWith(filterMode: mode));
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            const Text(
              'Rotation',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildRotateBtn(Icons.rotate_left, 'Left', () {
                  _updateCurrentSession(
                    session.copyWith(rotation: session.rotation - 90),
                  );
                }),
                _buildRotateBtn(Icons.rotate_right, 'Right', () {
                  _updateCurrentSession(
                    session.copyWith(rotation: session.rotation + 90),
                  );
                }),
                _buildRotateBtn(Icons.restore, 'Reset', () {
                  _updateCurrentSession(
                    session.copyWith(
                      brightness: 1.0,
                      contrast: 1.0,
                      rotation: 0.0,
                      filterMode: DocumentFilterMode.original,
                    ),
                  );
                }),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isProcessing ? null : _applyCurrentPage,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.text,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: _isProcessing
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Apply This Page'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSlider(
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> onChanged,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [Text(label), Text(value.toStringAsFixed(2))],
        ),
        Slider(
          value: value,
          min: min,
          max: max,
          activeColor: AppColors.text,
          onChanged: onChanged,
        ),
      ],
    );
  }

  Widget _buildRotateBtn(IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: AppColors.surface2,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Icon(icon, color: AppColors.text),
          ),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(fontSize: 11)),
        ],
      ),
    );
  }

  void _updateCurrentSession(EditSessionState updated) {
    final current = _sessions[_currentPage];
    final filterChanged = updated.filterMode != current.filterMode;

    setState(() {
      _sessions[_currentPage] = filterChanged
          ? updated.copyWith(clearOutputFile: true)
          : updated;
      _dirtyPages.add(_currentPage);
    });
  }

  Future<void> _applyCurrentPage() async {
    if (_isProcessing) return;

    setState(() => _isProcessing = true);
    try {
      await _applyPage(_currentPage);
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  Future<void> _applyPage(int index) async {
    if (index < 0 || index >= _sessions.length) return;

    final session = _sessions[index];
    final pipeline = index < widget.pipelineResults.length
        ? widget.pipelineResults[index]
        : null;
    final manualBase = _manualPerspectiveBases[index];
    final base =
        manualBase ??
        pipeline?.enhancedVariants[session.filterMode] ??
        widget.images[index];
    final filterForManual = switch (session.filterMode) {
      DocumentFilterMode.blackWhite => 2,
      DocumentFilterMode.grayscale => 3,
      _ => 0,
    };

    final adjusted = await _scannerService.applyAdjustments(
      base,
      brightness: session.brightness,
      contrast: session.contrast,
      rotation: session.rotation,
      filter: manualBase != null ? filterForManual : 0,
    );

    if (!mounted) return;

    setState(() {
      _previewImages[index] = adjusted ?? base;
      _sessions[index] = session.copyWith(outputFile: adjusted ?? base);
      _dirtyPages.remove(index);
    });
  }

  Future<void> _openCornerAdjust() async {
    final index = _currentPage;
    final pipeline = index < widget.pipelineResults.length
        ? widget.pipelineResults[index]
        : null;
    final source = pipeline?.originalFile ?? widget.images[index];
    final initialCorners = (pipeline?.corners ?? const <ScanCorner>[])
        .take(4)
        .toList(growable: false);

    final updatedCorners = await Navigator.push<List<ScanCorner>>(
      context,
      MaterialPageRoute(
        builder: (context) =>
            CornerAdjustPage(imageFile: source, initialCorners: initialCorners),
      ),
    );

    if (!mounted || updatedCorners == null || updatedCorners.length != 4) {
      return;
    }

    setState(() => _isProcessing = true);
    try {
      final warped = await _scannerService.applyPerspectiveFromCorners(
        source,
        updatedCorners.map((c) => ScanPoint(c.x, c.y)).toList(growable: false),
        suffix: 'manual_warp',
      );

      if (!mounted) return;

      setState(() {
        _manualPerspectiveBases[index] = warped;
        _previewImages[index] = warped ?? source;
        _sessions[index] = _sessions[index].copyWith(
          outputFile: warped ?? source,
          clearOutputFile: false,
        );
        _dirtyPages.remove(index);
      });
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  Future<void> _continueToResult() async {
    if (_isProcessing) return;

    setState(() => _isProcessing = true);
    try {
      final pagesToApply = _dirtyPages.toList(growable: false);
      for (final index in pagesToApply) {
        await _applyPage(index);
      }
      if (!mounted) return;
      widget.onContinue(_sessions);
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }
}
