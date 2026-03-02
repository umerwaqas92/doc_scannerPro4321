import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class ScannerPage extends StatefulWidget {
  final VoidCallback onCancel;
  final VoidCallback onDone;
  final Future<void> Function() onCapture;
  final Future<void> Function() onAddFromGallery;
  final CameraController? cameraController;
  final bool isCameraInitialized;
  final bool isAnalyzing;
  final String? analysisStageText;
  final List<File> capturedImages;

  const ScannerPage({
    super.key,
    required this.onCancel,
    required this.onDone,
    required this.onCapture,
    required this.onAddFromGallery,
    required this.cameraController,
    required this.isCameraInitialized,
    required this.isAnalyzing,
    required this.analysisStageText,
    required this.capturedImages,
  });

  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _analyzerController;

  bool _isStable = false;
  bool _isCaptureActionPending = false;
  bool _isStreamRunning = false;
  bool _isStartingStream = false;
  bool _isFrameProcessing = false;
  bool _liveAnalyzerAvailable = true;
  bool _autoCaptureEnabled = true;
  bool _autoCapturedSinceUnstable = false;

  int _frameTick = 0;
  int _stableFrameCount = 0;

  double _detectionConfidence = 0.0;
  String _liveStatus = 'Searching for document...';
  DateTime _lastAutoCaptureAt = DateTime.fromMillisecondsSinceEpoch(0);
  CameraController? _streamController;

  bool get _isBusy => _isCaptureActionPending || widget.isAnalyzing;

  @override
  void initState() {
    super.initState();
    _analyzerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_startLiveAnalyzerIfPossible());
    });
  }

  @override
  void didUpdateWidget(covariant ScannerPage oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.cameraController != oldWidget.cameraController ||
        (widget.isCameraInitialized && !oldWidget.isCameraInitialized)) {
      _resetLiveState();
      unawaited(_restartLiveAnalyzer());
    }

    if (!oldWidget.isAnalyzing && widget.isAnalyzing) {
      unawaited(_stopLiveAnalyzer());
    }
    if (oldWidget.isAnalyzing && !widget.isAnalyzing) {
      unawaited(_startLiveAnalyzerIfPossible());
    }

    if (widget.capturedImages.length > oldWidget.capturedImages.length) {
      _stableFrameCount = 0;
      _autoCapturedSinceUnstable = false;
      _isStable = false;
      _liveStatus = 'Searching for document...';
      _detectionConfidence = 0;
      if (mounted) {
        setState(() {});
      }
    }
  }

  @override
  void dispose() {
    unawaited(_stopLiveAnalyzer());
    _analyzerController.dispose();
    super.dispose();
  }

  void _resetLiveState() {
    _isStable = false;
    _stableFrameCount = 0;
    _frameTick = 0;
    _detectionConfidence = 0;
    _liveStatus = 'Searching for document...';
    _autoCapturedSinceUnstable = false;
  }

  Future<void> _restartLiveAnalyzer() async {
    await _stopLiveAnalyzer();
    await _startLiveAnalyzerIfPossible();
  }

  Future<void> _startLiveAnalyzerIfPossible() async {
    if (!mounted || _isBusy || _isStartingStream || _isStreamRunning) return;

    final controller = _activeController();
    if (controller == null) return;

    if (controller.value.isTakingPicture) return;

    _isStartingStream = true;
    try {
      if (controller.value.isStreamingImages) {
        _isStreamRunning = true;
      } else {
        await controller.startImageStream(_onCameraFrame);
        _isStreamRunning = true;
      }
      _streamController = controller;
      _liveAnalyzerAvailable = true;
    } catch (_) {
      _liveAnalyzerAvailable = false;
      _isStreamRunning = false;
      _isStable = true;
      _liveStatus = 'Live analyzer unavailable. Tap capture.';
      _detectionConfidence = 0.0;
      if (mounted) {
        setState(() {});
      }
    } finally {
      _isStartingStream = false;
    }
  }

  Future<void> _stopLiveAnalyzer() async {
    final controller = _streamController ?? widget.cameraController;
    if (controller == null || !_isStreamRunning) return;
    try {
      if (controller.value.isStreamingImages) {
        await controller.stopImageStream();
      }
    } catch (_) {
      // ignore stream stop failures when camera lifecycle is changing.
    } finally {
      _isStreamRunning = false;
      _isFrameProcessing = false;
      _streamController = null;
    }
  }

  CameraController? _activeController() {
    final controller = widget.cameraController;
    if (controller == null || !widget.isCameraInitialized) return null;
    try {
      final value = controller.value;
      if (!value.isInitialized || value.hasError) return null;
      return controller;
    } catch (_) {
      return null;
    }
  }

  void _onCameraFrame(CameraImage image) {
    if (!mounted || _isBusy || !_liveAnalyzerAvailable || _isFrameProcessing) {
      return;
    }

    _frameTick++;
    if (_frameTick % 2 != 0) return;

    _isFrameProcessing = true;
    try {
      final stats = _analyzeFrame(image);
      final confidence = stats.confidence.clamp(0.0, 1.0);
      final candidate = stats.candidate;

      final previousStable = _isStable;
      if (candidate && confidence > 0.42) {
        _stableFrameCount = math.min(_stableFrameCount + 1, 36);
      } else {
        _stableFrameCount = math.max(_stableFrameCount - 2, 0);
      }

      final stableNow = _stableFrameCount >= 8;
      if (!stableNow) {
        _autoCapturedSinceUnstable = false;
      }

      String status;
      if (stableNow) {
        status = 'Document locked';
      } else if (candidate) {
        status = 'Hold steady...';
      } else {
        status = 'Searching for document...';
      }

      final shouldRebuild = stableNow != previousStable || _frameTick % 6 == 0;
      if (shouldRebuild && mounted) {
        setState(() {
          _isStable = stableNow;
          _detectionConfidence = confidence;
          _liveStatus = status;
        });
      } else {
        _isStable = stableNow;
        _detectionConfidence = confidence;
        _liveStatus = status;
      }

      if (_autoCaptureEnabled &&
          stableNow &&
          !_autoCapturedSinceUnstable &&
          !_isBusy) {
        final now = DateTime.now();
        final elapsed = now.difference(_lastAutoCaptureAt).inMilliseconds;
        if (elapsed > 2400) {
          _autoCapturedSinceUnstable = true;
          _lastAutoCaptureAt = now;
          unawaited(_onCapture(autoTriggered: true));
        }
      }
    } catch (_) {
      // keep scanner responsive even if one frame fails.
    } finally {
      _isFrameProcessing = false;
    }
  }

  _FrameStats _analyzeFrame(CameraImage image) {
    if (image.planes.isEmpty || image.width < 8 || image.height < 8) {
      return const _FrameStats(confidence: 0, candidate: false);
    }

    final plane = image.planes.first;
    final bytes = plane.bytes;
    final rowStride = plane.bytesPerRow;
    final pixelStride = plane.bytesPerPixel ?? 1;

    if (bytes.isEmpty || rowStride <= 0 || pixelStride <= 0) {
      return const _FrameStats(confidence: 0, candidate: false);
    }

    final width = image.width;
    final height = image.height;

    final x0 = (width * 0.16).round();
    final x1 = (width * 0.84).round();
    final y0 = (height * 0.18).round();
    final y1 = (height * 0.84).round();

    final step = (width ~/ 96).clamp(2, 10);

    double edgeSum = 0;
    double lumaSum = 0;
    double lumaSqSum = 0;
    int samples = 0;

    for (int y = y0; y < y1 - step; y += step) {
      final row = y * rowStride;
      final rowDown = (y + step) * rowStride;

      for (int x = x0; x < x1 - step; x += step) {
        final i = row + x * pixelStride;
        final iRight = row + (x + step) * pixelStride;
        final iDown = rowDown + x * pixelStride;

        if (i >= bytes.length ||
            iRight >= bytes.length ||
            iDown >= bytes.length) {
          continue;
        }

        final v = bytes[i].toDouble();
        final vr = bytes[iRight].toDouble();
        final vd = bytes[iDown].toDouble();

        edgeSum += (v - vr).abs() + (v - vd).abs();
        lumaSum += v;
        lumaSqSum += v * v;
        samples++;
      }
    }

    if (samples == 0) {
      return const _FrameStats(confidence: 0, candidate: false);
    }

    final mean = lumaSum / samples;
    final variance = (lumaSqSum / samples) - (mean * mean);

    final brightnessNorm = (mean / 255.0).clamp(0.0, 1.0);
    final varianceNorm = (variance / (255.0 * 255.0)).clamp(0.0, 1.0);
    final edgeNorm = (edgeSum / (samples * 255.0 * 2.0)).clamp(0.0, 1.0);

    final brightnessScore = (1.0 - ((brightnessNorm - 0.62).abs() / 0.62))
        .clamp(0.0, 1.0);
    final confidence =
        (edgeNorm * 0.55 + varianceNorm * 0.30 + brightnessScore * 0.15).clamp(
          0.0,
          1.0,
        );

    final candidate =
        edgeNorm > 0.075 &&
        varianceNorm > 0.0055 &&
        brightnessNorm > 0.16 &&
        brightnessNorm < 0.97;

    return _FrameStats(confidence: confidence, candidate: candidate);
  }

  double _previewAspectRatio() {
    final controller = _activeController();
    if (controller == null) {
      return 3 / 4;
    }

    final controllerAspect = controller.value.aspectRatio;
    return (1 / controllerAspect).clamp(0.65, 1.6);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.scannerBg,
      child: Stack(
        children: [
          Column(
            children: [
              _buildHeader(),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final reservedControlsHeight =
                        widget.capturedImages.isNotEmpty ? 130.0 : 116.0;
                    final previewHeight =
                        (constraints.maxHeight - reservedControlsHeight).clamp(
                          170.0,
                          constraints.maxHeight,
                        );

                    return Column(
                      children: [
                        SizedBox(
                          height: previewHeight,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                            child: _buildCameraPreview(),
                          ),
                        ),
                        Expanded(
                          child: Align(
                            alignment: Alignment.bottomCenter,
                            child: _buildCaptureControls(),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
          if (_isBusy) _buildScanningOverlay(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _buildHeaderButton('✕ Cancel', widget.onCancel, !_isBusy),
          Text(
            widget.capturedImages.isEmpty
                ? 'Document Scanner'
                : '${widget.capturedImages.length} scanned',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          _buildHeaderButton('Done', widget.onDone, !_isBusy),
        ],
      ),
    );
  }

  Widget _buildHeaderButton(String text, VoidCallback onTap, bool enabled) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Opacity(
        opacity: enabled ? 1 : 0.45,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCameraPreview() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final ratio = _previewAspectRatio();
        final activeController = _activeController();
        var width = constraints.maxWidth;
        var height = width / ratio;
        if (height > constraints.maxHeight) {
          height = constraints.maxHeight;
          width = height * ratio;
        }

        return Center(
          child: Container(
            width: width,
            height: height,
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(16),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  activeController != null
                      ? CameraPreview(activeController)
                      : _buildCameraPlaceholder(),
                  _buildViewfinderOverlay(),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildCameraPlaceholder() {
    return Container(
      color: Colors.black,
      child: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.camera_alt_outlined, size: 64, color: Colors.white24),
            SizedBox(height: 16),
            Text(
              'Camera not available',
              style: TextStyle(color: Colors.white54, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildViewfinderOverlay() {
    final confidencePct = (_detectionConfidence * 100)
        .clamp(0, 100)
        .toStringAsFixed(0);

    return Stack(
      children: [
        Positioned(
          top: 16,
          left: 0,
          right: 0,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
              ),
              child: Text(
                _isStable ? 'Document detected • $confidencePct%' : _liveStatus,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _isStable ? AppColors.green : Colors.white,
                ),
              ),
            ),
          ),
        ),
        Center(
          child: FractionallySizedBox(
            widthFactor: 0.90,
            heightFactor: 0.86,
            child: AnimatedBuilder(
              animation: _analyzerController,
              builder: (context, child) {
                final frameColor = _isStable
                    ? AppColors.green
                    : Colors.white.withValues(alpha: 0.72);
                final pulse = 0.35 + (_analyzerController.value * 0.65);

                return Container(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.30),
                      width: 1.4,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: frameColor, width: 2),
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: [
                          BoxShadow(
                            color: frameColor.withValues(alpha: pulse * 0.35),
                            blurRadius: 10,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final maxY = constraints.maxHeight - 24;
                          final lineY = 12 + (maxY * _analyzerController.value);
                          return Stack(
                            children: [
                              Positioned(
                                top: -2,
                                left: -2,
                                child: _buildCorner(true, true, frameColor),
                              ),
                              Positioned(
                                top: -2,
                                right: -2,
                                child: _buildCorner(true, false, frameColor),
                              ),
                              Positioned(
                                bottom: -2,
                                left: -2,
                                child: _buildCorner(false, true, frameColor),
                              ),
                              Positioned(
                                bottom: -2,
                                right: -2,
                                child: _buildCorner(false, false, frameColor),
                              ),
                              Positioned(
                                left: 10,
                                right: 10,
                                top: lineY,
                                child: Container(
                                  height: 2,
                                  decoration: BoxDecoration(
                                    color: AppColors.green.withValues(
                                      alpha: 0.9,
                                    ),
                                    borderRadius: BorderRadius.circular(2),
                                    boxShadow: [
                                      BoxShadow(
                                        color: AppColors.green.withValues(
                                          alpha: 0.6,
                                        ),
                                        blurRadius: 8,
                                        spreadRadius: 1,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        Positioned(
          bottom: 14,
          left: 0,
          right: 0,
          child: Text(
            _isStable
                ? (_autoCaptureEnabled
                      ? 'Hold steady • auto-capture enabled'
                      : 'Hold steady and tap capture')
                : 'Align page inside frame',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: _isStable ? AppColors.green : Colors.white54,
              fontWeight: _isStable ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCorner(bool isTop, bool isLeft, Color color) {
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        border: Border(
          top: isTop ? BorderSide(color: color, width: 3) : BorderSide.none,
          bottom: !isTop ? BorderSide(color: color, width: 3) : BorderSide.none,
          left: isLeft ? BorderSide(color: color, width: 3) : BorderSide.none,
          right: !isLeft ? BorderSide(color: color, width: 3) : BorderSide.none,
        ),
        borderRadius: BorderRadius.only(
          topLeft: isTop && isLeft ? const Radius.circular(4) : Radius.zero,
          topRight: isTop && !isLeft ? const Radius.circular(4) : Radius.zero,
          bottomLeft: !isTop && isLeft ? const Radius.circular(4) : Radius.zero,
          bottomRight: !isTop && !isLeft
              ? const Radius.circular(4)
              : Radius.zero,
        ),
      ),
    );
  }

  Widget _buildCaptureControls() {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        32,
        8,
        32,
        bottomInset > 0 ? bottomInset - 4 : 12,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildCtrlButton(
                Icons.photo_library_outlined,
                _onAddFromGallery,
                !_isBusy,
              ),
              _buildCaptureButton(),
              _buildCtrlButton(
                _autoCaptureEnabled ? Icons.auto_mode : Icons.touch_app,
                _toggleAutoCapture,
                !_isBusy,
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (widget.capturedImages.isNotEmpty)
            Text(
              '${widget.capturedImages.length} page(s) ready',
              style: const TextStyle(fontSize: 12, color: Colors.white70),
            ),
        ],
      ),
    );
  }

  Widget _buildCtrlButton(IconData icon, VoidCallback onTap, bool enabled) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Opacity(
        opacity: enabled ? 1 : 0.5,
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
          ),
          child: Icon(icon, size: 22, color: Colors.white),
        ),
      ),
    );
  }

  Widget _buildCaptureButton() {
    return GestureDetector(
      onTap: _isBusy ? null : () => _onCapture(autoTriggered: false),
      child: Opacity(
        opacity: _isBusy ? 0.6 : 1,
        child: Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 4),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 10,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Container(
            margin: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.green, width: 3),
            ),
            child: Center(
              child: _isBusy
                  ? const SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(
                        color: AppColors.green,
                        strokeWidth: 3,
                      ),
                    )
                  : Container(
                      width: 24,
                      height: 24,
                      decoration: const BoxDecoration(
                        color: AppColors.green,
                        shape: BoxShape.circle,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }

  void _toggleAutoCapture() {
    setState(() {
      _autoCaptureEnabled = !_autoCaptureEnabled;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _autoCaptureEnabled
              ? 'Auto capture enabled'
              : 'Auto capture disabled',
        ),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  Future<void> _onCapture({required bool autoTriggered}) async {
    if (_isBusy) return;

    if (_liveAnalyzerAvailable && !_isStable && !autoTriggered) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No clear page detected. Try again.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    setState(() {
      _isCaptureActionPending = true;
      _isStable = false;
      _stableFrameCount = 0;
      _detectionConfidence = 0;
      _liveStatus = autoTriggered
          ? 'Auto capture in progress...'
          : 'Capturing image...';
    });

    await _stopLiveAnalyzer();

    try {
      await widget.onCapture();
    } finally {
      if (mounted) {
        setState(() {
          _isCaptureActionPending = false;
          _liveStatus = 'Searching for document...';
        });
        if (!widget.isAnalyzing) {
          unawaited(_startLiveAnalyzerIfPossible());
        }
      }
    }
  }

  Future<void> _onAddFromGallery() async {
    if (_isBusy) return;
    setState(() {
      _isCaptureActionPending = true;
      _isStable = false;
      _stableFrameCount = 0;
      _detectionConfidence = 0;
      _liveStatus = 'Adding image from gallery...';
    });

    await _stopLiveAnalyzer();

    try {
      await widget.onAddFromGallery();
    } finally {
      if (mounted) {
        setState(() {
          _isCaptureActionPending = false;
          _liveStatus = 'Searching for document...';
        });
        if (!widget.isAnalyzing) {
          unawaited(_startLiveAnalyzerIfPossible());
        }
      }
    }
  }

  Widget _buildScanningOverlay() {
    return Container(
      color: Colors.black.withValues(alpha: 0.64),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 120,
              height: 120,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 90,
                    height: 90,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      color: AppColors.green.withValues(alpha: 0.35),
                    ),
                  ),
                  const Icon(
                    Icons.document_scanner_outlined,
                    size: 48,
                    color: Colors.white,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Analyzing document...',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              widget.analysisStageText ?? 'Processing image',
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: 220,
              child: LinearProgressIndicator(
                backgroundColor: Colors.white24,
                valueColor: const AlwaysStoppedAnimation<Color>(
                  AppColors.green,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FrameStats {
  final double confidence;
  final bool candidate;

  const _FrameStats({required this.confidence, required this.candidate});
}
