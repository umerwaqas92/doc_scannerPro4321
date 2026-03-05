import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
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
  bool _isCommitting = false;
  final Set<int> _dirtyPages = <int>{};
  late List<File> _previewImages;
  late List<File?> _renderedOutputs;
  late List<File?> _manualPerspectiveBases;
  late List<EditSessionState> _sessions;
  late List<int> _previewTokens;
  late List<int> _renderInFlightCounts;
  late List<String?> _lastPreviewSignatures;
  Timer? _previewDebounce;

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
    _renderedOutputs = List<File?>.from(_previewImages);
    _previewTokens = List<int>.filled(widget.images.length, 0);
    _renderInFlightCounts = List<int>.filled(widget.images.length, 0);
    _lastPreviewSignatures = List<String?>.filled(widget.images.length, null);
  }

  @override
  void didUpdateWidget(covariant ImageEditPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.pipelineResults.length != oldWidget.pipelineResults.length) {
      // keep indices aligned if lists expand
      final newLength = widget.images.length;
      if (_previewImages.length != newLength) {
        _previewImages = List<File>.from(widget.images);
        _renderedOutputs = List<File?>.filled(newLength, null);
        _manualPerspectiveBases = List<File?>.filled(newLength, null);
        _sessions = List<EditSessionState>.generate(newLength, (index) {
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
        _renderedOutputs = List<File?>.from(_previewImages);
        _previewTokens = List<int>.filled(newLength, 0);
        _renderInFlightCounts = List<int>.filled(newLength, 0);
        _lastPreviewSignatures = List<String?>.filled(newLength, null);
        return;
      }
    }

    var updated = false;
    for (var i = 0; i < widget.pipelineResults.length; i++) {
      final pipeline = widget.pipelineResults[i];
      final oldPipeline =
          i < oldWidget.pipelineResults.length ? oldWidget.pipelineResults[i] : null;
      if (pipeline == null || pipeline == oldPipeline) continue;
      if (_dirtyPages.contains(i)) continue;

      final output = pipeline.selectedOutputFile;
      _previewImages[i] = output;
      _renderedOutputs[i] = output;
      _sessions[i] = _sessions[i].copyWith(
        filterMode: pipeline.selectedFilter,
        outputFile: output,
      );
      _lastPreviewSignatures[i] = null;
      updated = true;
    }

    if (updated && mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _previewDebounce?.cancel();
    super.dispose();
  }

  EditSessionState get _currentSession => _sessions[_currentPage];
  bool get _isCurrentPageRendering => _renderInFlightCounts[_currentPage] > 0;

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
            onPressed: _isCommitting ? null : _continueToResult,
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
      body: LayoutBuilder(
        builder: (context, constraints) {
          final minPreviewHeight = math.min(
            320.0,
            constraints.maxHeight * 0.55,
          );
          final maxPreviewHeight = math.max(
            minPreviewHeight,
            constraints.maxHeight - 260,
          );
          final previewHeight = (constraints.maxHeight * 0.72)
              .clamp(minPreviewHeight, maxPreviewHeight)
              .toDouble();

          return Column(
            children: [
              SizedBox(height: previewHeight, child: _buildImagePreview()),
              Expanded(child: _buildBottomPanel()),
            ],
          );
        },
      ),
    );
  }

  Widget _buildImagePreview() {
    if (_previewImages.isEmpty) {
      return const Center(child: Text('No images'));
    }

    final currentFile = _previewImages[_currentPage];
    if (!currentFile.existsSync()) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.border),
          ),
          child: const Center(
            child: Text(
              'Image not available yet. Please retry.',
              style: TextStyle(color: AppColors.text2),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      child: Stack(
        children: [
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: InteractiveViewer(
                minScale: 1.0,
                maxScale: 4.0,
                child: Center(
                  child: Image.file(
                    currentFile,
                    fit: BoxFit.contain,
                    gaplessPlayback: true,
                    filterQuality: FilterQuality.medium,
                    errorBuilder: (context, error, stackTrace) {
                      return const Center(
                        child: Text(
                          'Unable to load image',
                          style: TextStyle(color: AppColors.text2),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
          if (_isCurrentPageRendering || _isCommitting)
            Positioned(
              right: 12,
              top: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.66),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Updating',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBottomPanel() {
    final pipelineInfo = _buildPipelineInfo();

    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildPageSelector(),
            if (pipelineInfo != null) ...[
              const SizedBox(height: 10),
              pipelineInfo,
            ],
            const SizedBox(height: 12),
            _buildEditStateBanner(),
            const SizedBox(height: 12),
            _buildControls(),
          ],
        ),
      ),
    );
  }

  Widget _buildEditStateBanner() {
    final isDirty = _dirtyPages.contains(_currentPage);
    final isBusy = _isCurrentPageRendering || _isCommitting;
    final text = isBusy
        ? 'Applying latest changes...'
        : isDirty
        ? 'Unsaved changes on this page'
        : 'Changes applied';
    final color = isBusy
        ? Colors.blueGrey
        : isDirty
        ? Colors.orange
        : Colors.green;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(
            isBusy
                ? Icons.autorenew
                : isDirty
                ? Icons.pending_actions
                : Icons.check_circle,
            size: 18,
            color: color.shade700,
          ),
          const SizedBox(width: 8),
          Text(
            text,
            style: TextStyle(
              color: color.shade700,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
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

  Widget? _buildPipelineInfo() {
    final pipeline = _currentPage < widget.pipelineResults.length
        ? widget.pipelineResults[_currentPage]
        : null;

    if (pipeline == null) return null;

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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSlider(
          'Brightness',
          session.brightness,
          0.2,
          2.5,
          (v) {
            _updateCurrentSession(session.copyWith(brightness: v));
            _schedulePreviewApply();
          },
          () => _renderPagePreview(_currentPage),
        ),
        _buildSlider('Contrast', session.contrast, 0.2, 2.0, (v) {
          _updateCurrentSession(session.copyWith(contrast: v));
          _schedulePreviewApply();
        }, () => _renderPagePreview(_currentPage)),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _isCommitting ? null : _openCornerAdjust,
            icon: const Icon(Icons.crop_free),
            label: const Text('Adjust Corners'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.text,
              side: const BorderSide(color: AppColors.border),
            ),
          ),
        ),
        const SizedBox(height: 16),
        const Text('Filters', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: DocumentFilterMode.values.map((mode) {
            return ChoiceChip(
              label: Text(mode.label),
              selected: session.filterMode == mode,
              onSelected: _isCommitting
                  ? null
                  : (_) {
                      _updateCurrentSession(session.copyWith(filterMode: mode));
                      _renderPagePreview(_currentPage);
                    },
            );
          }).toList(),
        ),
        const SizedBox(height: 16),
        const Text('Rotation', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildRotateBtn(Icons.rotate_left, 'Left', () {
              _updateCurrentSession(
                session.copyWith(rotation: session.rotation - 90),
              );
              _renderPagePreview(_currentPage);
            }),
            _buildRotateBtn(Icons.rotate_right, 'Right', () {
              _updateCurrentSession(
                session.copyWith(rotation: session.rotation + 90),
              );
              _renderPagePreview(_currentPage);
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
              _renderPagePreview(_currentPage);
            }),
          ],
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: (_isCommitting || _isCurrentPageRendering)
                ? null
                : _applyCurrentPage,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.text,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: (_isCommitting || _isCurrentPageRendering)
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
    );
  }

  Widget _buildSlider(
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> onChanged,
    VoidCallback onChangeEnd,
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
          onChanged: _isCommitting ? null : onChanged,
          onChangeEnd: _isCommitting ? null : (_) => onChangeEnd(),
        ),
      ],
    );
  }

  Widget _buildRotateBtn(IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: _isCommitting ? null : onTap,
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
    setState(() {
      _sessions[_currentPage] = updated.copyWith(clearOutputFile: true);
      _renderedOutputs[_currentPage] = null;
      _lastPreviewSignatures[_currentPage] = null;
      _dirtyPages.add(_currentPage);
    });
  }

  void _schedulePreviewApply() {
    final pageIndex = _currentPage;
    _previewDebounce?.cancel();
    _previewDebounce = Timer(const Duration(milliseconds: 260), () async {
      if (!mounted) return;
      await _renderPagePreview(pageIndex);
    });
  }

  Future<File> _renderAdjustedFile(
    int index, {
    required String tagPrefix,
    int? maxDimension,
    int quality = 95,
  }) async {
    final session = _sessions[index];
    final pipeline = index < widget.pipelineResults.length
        ? widget.pipelineResults[index]
        : null;
    final manualBase = _manualPerspectiveBases[index];
    final base = manualBase ?? pipeline?.croppedFile ?? widget.images[index];
    final filterCode = _filterCodeForMode(session.filterMode);
    final tag =
        '${tagPrefix}_p${index}_${DateTime.now().microsecondsSinceEpoch}';

    final adjusted = await _scannerService.applyAdjustments(
      base,
      brightness: session.brightness,
      contrast: session.contrast,
      rotation: session.rotation,
      filter: filterCode,
      outputTag: tag,
      maxDimension: maxDimension,
      quality: quality,
    );
    return adjusted ?? base;
  }

  Future<void> _renderPagePreview(int index) async {
    if (index < 0 || index >= _sessions.length) return;
    final signature = _buildPreviewSignature(index);
    if (_lastPreviewSignatures[index] == signature &&
        _renderedOutputs[index] != null) {
      return;
    }

    final token = ++_previewTokens[index];
    _incrementRenderCount(index);
    try {
      final rendered = await _renderAdjustedFile(
        index,
        tagPrefix: 'preview',
        maxDimension: 1200,
        quality: 82,
      );
      if (!mounted || token != _previewTokens[index]) return;
      setState(() {
        _previewImages[index] = rendered;
        _renderedOutputs[index] = rendered;
        _lastPreviewSignatures[index] = signature;
      });
    } finally {
      _decrementRenderCount(index);
    }
  }

  void _incrementRenderCount(int index) {
    if (!mounted) return;
    setState(() {
      _renderInFlightCounts[index] = _renderInFlightCounts[index] + 1;
    });
  }

  void _decrementRenderCount(int index) {
    if (!mounted) return;
    setState(() {
      _renderInFlightCounts[index] = math.max(
        0,
        _renderInFlightCounts[index] - 1,
      );
    });
  }

  Future<void> _applyCurrentPage() async {
    if (_isCommitting) return;
    _previewDebounce?.cancel();
    setState(() => _isCommitting = true);
    try {
      await _applyPage(_currentPage);
    } finally {
      if (mounted) {
        setState(() => _isCommitting = false);
      }
    }
  }

  Future<void> _applyPage(int index) async {
    if (index < 0 || index >= _sessions.length) return;
    ++_previewTokens[index];
    _incrementRenderCount(index);
    try {
      final rendered = await _renderAdjustedFile(
        index,
        tagPrefix: 'applied',
        quality: 95,
      );
      if (!mounted) return;
      setState(() {
        _previewImages[index] = rendered;
        _renderedOutputs[index] = rendered;
        _lastPreviewSignatures[index] = null;
        _sessions[index] = _sessions[index].copyWith(outputFile: rendered);
        _dirtyPages.remove(index);
      });
    } finally {
      _decrementRenderCount(index);
    }
  }

  int _filterCodeForMode(DocumentFilterMode mode) {
    switch (mode) {
      case DocumentFilterMode.original:
        return 0;
      case DocumentFilterMode.blackWhite:
        return 2;
      case DocumentFilterMode.grayscale:
        return 3;
      case DocumentFilterMode.colorEnhanced:
        return 4;
      case DocumentFilterMode.highContrastText:
        return 5;
      case DocumentFilterMode.warmPaper:
        return 6;
      case DocumentFilterMode.photoNatural:
        return 7;
    }
  }

  Future<void> _openCornerAdjust() async {
    final index = _currentPage;
    final pipeline = index < widget.pipelineResults.length
        ? widget.pipelineResults[index]
        : null;
    final source = pipeline?.originalFile ?? widget.images[index];
    final initialCorners =
        (pipeline?.orderedCorners ?? pipeline?.corners ?? const <ScanCorner>[])
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

    setState(() => _isCommitting = true);
    try {
      final warped = await _scannerService.applyPerspectiveFromCorners(
        source,
        updatedCorners.map((c) => ScanPoint(c.x, c.y)).toList(growable: false),
        suffix: 'manual_warp',
        useDefaultOnInvalid: false,
      );
      final cleaned = warped == null
          ? null
          : await _scannerService.postProcessWarpedDocument(
              warped,
              suffix: 'manual_clean',
            );
      final finalBase = cleaned ?? warped ?? source;

      if (!mounted) return;

      setState(() {
        _manualPerspectiveBases[index] = finalBase;
        _renderedOutputs[index] = null;
        _lastPreviewSignatures[index] = null;
        _sessions[index] = _sessions[index].copyWith(clearOutputFile: true);
        _dirtyPages.add(index);
      });
      await _renderPagePreview(index);
    } finally {
      if (mounted) {
        setState(() => _isCommitting = false);
      }
    }
  }

  Future<void> _continueToResult() async {
    if (_isCommitting) return;

    _previewDebounce?.cancel();
    setState(() => _isCommitting = true);
    try {
      final pagesToApply = <int>[];
      for (var i = 0; i < _sessions.length; i++) {
        if (_dirtyPages.contains(i) || _sessions[i].outputFile == null) {
          pagesToApply.add(i);
        }
      }
      for (final index in pagesToApply) {
        await _applyPage(index);
      }
      if (!mounted) return;
      widget.onContinue(_sessions);
    } finally {
      if (mounted) {
        setState(() => _isCommitting = false);
      }
    }
  }

  String _buildPreviewSignature(int index) {
    final session = _sessions[index];
    final pipeline = index < widget.pipelineResults.length
        ? widget.pipelineResults[index]
        : null;
    final manualBase = _manualPerspectiveBases[index];
    final basePath =
        (manualBase ?? pipeline?.croppedFile ?? widget.images[index]).path;
    return [
      basePath,
      session.filterMode.name,
      session.brightness.toStringAsFixed(3),
      session.contrast.toStringAsFixed(3),
      session.rotation.toStringAsFixed(1),
    ].join('|');
  }
}
