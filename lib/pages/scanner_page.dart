import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class ScannerPage extends StatefulWidget {
  final VoidCallback onCancel;
  final VoidCallback onDone;
  final Future<bool> Function() onCapture;
  final Future<bool> Function() onAddFromGallery;
  final ValueChanged<bool> onBatchModeChanged;
  final CameraController? cameraController;
  final bool isCameraInitialized;
  final bool isAnalyzing;
  final String? analysisStageText;
  final List<File> capturedImages;
  final List<File> batchImages;
  final String flashMode;
  final ValueChanged<String> onFlashModeChanged;

  const ScannerPage({
    super.key,
    required this.onCancel,
    required this.onDone,
    required this.onCapture,
    required this.onAddFromGallery,
    required this.onBatchModeChanged,
    required this.cameraController,
    required this.isCameraInitialized,
    required this.isAnalyzing,
    required this.analysisStageText,
    required this.capturedImages,
    required this.batchImages,
    required this.flashMode,
    required this.onFlashModeChanged,
  });

  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

enum _FlashSetting { auto, on, off }
enum _AutoCaptureMode { standard, turnPage }
enum _ScannerPhase {
  detecting,
  ready,
  capturing,
  analyzingLocked,
  cooldown,
  awaitPageMove,
}

class _ScannerPageState extends State<ScannerPage>
    with TickerProviderStateMixin {
  bool _isStable = false;
  bool _isCaptureActionPending = false;
  bool _isStreamRunning = false;
  bool _isStartingStream = false;
  bool _isFrameProcessing = false;
  bool _liveAnalyzerAvailable = true;
  bool _autoCaptureEnabled = false;
  bool _autoCapturedSinceUnstable = false;
  bool _awaitingDocumentMoveAfterAutoCapture = false;
  bool _isAdjustingFocus = false;
  bool _batchMode = false;
  _FlashSetting _flashSetting = _FlashSetting.auto;
  _AutoCaptureMode _autoCaptureMode = _AutoCaptureMode.standard;
  _ScannerPhase _scannerPhase = _ScannerPhase.detecting;

  late final AnimationController _openController;
  late final Animation<double> _cameraFade;
  late final Animation<Offset> _cameraSlide;
  late final Animation<double> _overlayFade;
  late final Animation<double> _focusScale;
  late final Animation<double> _focusOpacity;
  late final AnimationController _flashController;
  late final Animation<double> _flashOpacity;
  late final AnimationController _thumbController;

  int _frameTick = 0;
  int _stableFrameCount = 0;
  int _missingDocumentFrames = 0;

  double _detectionConfidence = 0.0;
  String _liveStatus = 'Searching for document...';
  DateTime _lastAutoCaptureAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastFocusAdjustAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime? _stableSince;
  DateTime _cooldownUntil = DateTime.fromMillisecondsSinceEpoch(0);
  bool _turnPageMotionDetected = false;
  DateTime? _turnPageSettledSince;
  CameraController? _streamController;
  List<int>? _lastMotionSamples;
  File? _lastCapturedImage;
  Offset? _thumbStart;
  Offset? _thumbEnd;

  bool get _isBusy => _isCaptureActionPending || widget.isAnalyzing;
  bool get _isInCooldown => DateTime.now().isBefore(_cooldownUntil);
  List<File> get _activeImages =>
      _batchMode ? widget.batchImages : widget.capturedImages;

  @override
  void initState() {
    super.initState();
    _openController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    );
    _cameraFade = CurvedAnimation(
      parent: _openController,
      curve: const Interval(0.0, 0.7, curve: Curves.easeOut),
    );
    _cameraSlide = Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero)
        .animate(
          CurvedAnimation(
            parent: _openController,
            curve: const Interval(0.0, 0.7, curve: Curves.easeOutCubic),
          ),
        );
    _overlayFade = CurvedAnimation(
      parent: _openController,
      curve: const Interval(0.25, 1.0, curve: Curves.easeOut),
    );
    _focusScale = Tween<double>(begin: 0.85, end: 1.1).animate(
      CurvedAnimation(
        parent: _openController,
        curve: const Interval(0.35, 0.85, curve: Curves.easeOutBack),
      ),
    );
    _focusOpacity = CurvedAnimation(
      parent: _openController,
      curve: const Interval(0.35, 0.75, curve: Curves.easeOut),
    );
    _flashController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
    );
    _flashOpacity = Tween<double>(
      begin: 0.0,
      end: 0.95,
    ).animate(CurvedAnimation(parent: _flashController, curve: Curves.easeOut));
    _thumbController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
    _flashSetting = _flashSettingFromString(widget.flashMode);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_startLiveAnalyzerIfPossible());
      _openController.forward(from: 0);
    });
  }

  @override
  void didUpdateWidget(covariant ScannerPage oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.cameraController != oldWidget.cameraController ||
        (widget.isCameraInitialized && !oldWidget.isCameraInitialized)) {
      _resetLiveState();
      unawaited(_restartLiveAnalyzer());
      if (mounted) {
        _openController.forward(from: 0);
      }
    }
    if (widget.flashMode != oldWidget.flashMode) {
      _flashSetting = _flashSettingFromString(widget.flashMode);
      _applyFlashMode();
    }

    if (!oldWidget.isAnalyzing && widget.isAnalyzing) {
      _scannerPhase = _ScannerPhase.analyzingLocked;
      unawaited(_stopLiveAnalyzer());
    }
    if (oldWidget.isAnalyzing && !widget.isAnalyzing) {
      if (mounted) {
        setState(() {
          _scannerPhase = _ScannerPhase.detecting;
          _cooldownUntil = DateTime.now().add(const Duration(milliseconds: 550));
        });
      } else {
        _scannerPhase = _ScannerPhase.detecting;
      }
      unawaited(_startLiveAnalyzerIfPossible());
    }

    final previousCount = _batchMode
        ? oldWidget.batchImages.length
        : oldWidget.capturedImages.length;
    final newCount = _batchMode
        ? widget.batchImages.length
        : widget.capturedImages.length;
    if (newCount > previousCount) {
      _stableFrameCount = 0;
      _autoCapturedSinceUnstable = false;
      _isStable = false;
      _liveStatus = 'Searching for document...';
      _detectionConfidence = 0;
      _missingDocumentFrames = 0;
      if (mounted) {
        setState(() {});
      }
    }
  }

  @override
  void dispose() {
    unawaited(_stopLiveAnalyzer());
    _openController.dispose();
    _flashController.dispose();
    _thumbController.dispose();
    super.dispose();
  }

  void _resetLiveState() {
    _isStable = false;
    _stableFrameCount = 0;
    _frameTick = 0;
    _detectionConfidence = 0;
    _liveStatus = 'Searching for document...';
    _autoCapturedSinceUnstable = false;
    _awaitingDocumentMoveAfterAutoCapture = false;
    _missingDocumentFrames = 0;
    _lastMotionSamples = null;
    _lastCapturedImage = null;
    _stableSince = null;
    _scannerPhase = _ScannerPhase.detecting;
    _cooldownUntil = DateTime.fromMillisecondsSinceEpoch(0);
    _turnPageMotionDetected = false;
    _turnPageSettledSince = null;
  }

  Future<void> _restartLiveAnalyzer() async {
    await _stopLiveAnalyzer();
    await _startLiveAnalyzerIfPossible();
  }

  void _setCooldown([int ms = 900]) {
    _cooldownUntil = DateTime.now().add(Duration(milliseconds: ms));
    _scannerPhase = _ScannerPhase.cooldown;
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
      _applyFlashMode();
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
      if (stats.occluded) {
        _stableFrameCount = 0;
        _isStable = false;
        _detectionConfidence = 0;
        _liveStatus = 'Camera blocked. Try again.';
        _autoCapturedSinceUnstable = false;
        _awaitingDocumentMoveAfterAutoCapture = false;
        _missingDocumentFrames++;
        if (mounted && _frameTick % 6 == 0) {
          setState(() {});
        }
        return;
      }

      final confidence = stats.confidence.clamp(0.0, 1.0);
      final motionScore = stats.motionScore.clamp(0.0, 1.0);
      final candidate = stats.candidate;
      if (candidate) {
        _missingDocumentFrames = 0;
      } else {
        _missingDocumentFrames = math.min(_missingDocumentFrames + 1, 1000);
      }

      final previousStable = _isStable;
      if (candidate && confidence > 0.44 && motionScore < 0.11) {
        _stableFrameCount = math.min(_stableFrameCount + 1, 36);
      } else {
        _stableFrameCount = math.max(_stableFrameCount - 2, 0);
      }

      final stableNow = _stableFrameCount >= 6;

      // Require document movement after an auto-capture before next auto shot.
      if (_awaitingDocumentMoveAfterAutoCapture &&
          _missingDocumentFrames >= 8) {
        _awaitingDocumentMoveAfterAutoCapture = false;
        _autoCapturedSinceUnstable = false;
        _turnPageMotionDetected = false;
        _turnPageSettledSince = null;
      }
      if (!stableNow && !_awaitingDocumentMoveAfterAutoCapture) {
        _autoCapturedSinceUnstable = false;
      }

      if (!stableNow || !candidate) {
        _stableSince = null;
      }
      _stableSince ??= stableNow && candidate ? DateTime.now() : null;

      String status;
      if (_awaitingDocumentMoveAfterAutoCapture) {
        _scannerPhase = _ScannerPhase.awaitPageMove;
        status = 'Move to next page for auto capture';
      } else if (_isInCooldown) {
        _scannerPhase = _ScannerPhase.cooldown;
        status = 'Hold for next capture...';
      } else if (stableNow) {
        _scannerPhase = _ScannerPhase.ready;
        if (_autoCaptureEnabled) {
          status = 'Perfect shot ready';
        } else {
          status = 'Document locked';
        }
      } else if (candidate) {
        _scannerPhase = _ScannerPhase.detecting;
        if (_autoCaptureEnabled) {
          status = motionScore < 0.12
              ? 'Focusing... hold steady'
              : 'Hold steady';
        } else {
          status = motionScore < 0.12 ? 'Hold steady...' : 'Stabilizing...';
        }
      } else {
        _scannerPhase = _ScannerPhase.detecting;
        status = 'Searching for document...';
      }

      if (_autoCaptureEnabled &&
          candidate &&
          confidence >= 0.50 &&
          _frameTick % 8 == 0) {
        unawaited(_maybeRefocusCenter());
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
          !_isInCooldown &&
          !_autoCapturedSinceUnstable &&
          !_awaitingDocumentMoveAfterAutoCapture &&
          !_isBusy) {
        final shouldCapture = _autoCaptureMode == _AutoCaptureMode.standard
            ? _shouldAutoCaptureStandard(
                stableNow: stableNow,
                confidence: confidence,
                motionScore: motionScore,
              )
            : _shouldAutoCaptureTurnPage(
                candidate: candidate,
                stableNow: stableNow,
                confidence: confidence,
                motionScore: motionScore,
              );
        if (shouldCapture) {
          _autoCapturedSinceUnstable = true;
          _awaitingDocumentMoveAfterAutoCapture = true;
          final now = DateTime.now();
          _lastAutoCaptureAt = now;
          _setCooldown(900);
          _scannerPhase = _ScannerPhase.capturing;
          unawaited(_onCapture(autoTriggered: true));
        }
      }
    } catch (_) {
      // keep scanner responsive even if one frame fails.
    } finally {
      _isFrameProcessing = false;
    }
  }

  bool _shouldAutoCaptureStandard({
    required bool stableNow,
    required double confidence,
    required double motionScore,
  }) {
    if (!stableNow || _stableSince == null) return false;
    if (confidence < 0.50 || motionScore >= 0.12) return false;
    final now = DateTime.now();
    final stableElapsed = now.difference(_stableSince!).inMilliseconds;
    final elapsed = now.difference(_lastAutoCaptureAt).inMilliseconds;
    return stableElapsed >= 450 && elapsed > 900;
  }

  bool _shouldAutoCaptureTurnPage({
    required bool candidate,
    required bool stableNow,
    required double confidence,
    required double motionScore,
  }) {
    final now = DateTime.now();

    // Turn-page mode waits for motion burst (page movement), then settle.
    if (motionScore > 0.22 || !candidate) {
      _turnPageMotionDetected = true;
      _turnPageSettledSince = null;
      return false;
    }

    if (!_turnPageMotionDetected) return false;
    if (!stableNow || confidence < 0.47 || motionScore > 0.09) {
      _turnPageSettledSince = null;
      return false;
    }

    _turnPageSettledSince ??= now;
    final settleElapsed = now.difference(_turnPageSettledSince!).inMilliseconds;
    final elapsed = now.difference(_lastAutoCaptureAt).inMilliseconds;
    if (settleElapsed >= 300 && elapsed > 900) {
      _turnPageMotionDetected = false;
      _turnPageSettledSince = null;
      return true;
    }
    return false;
  }

  Future<void> _maybeRefocusCenter() async {
    if (_isAdjustingFocus || !_autoCaptureEnabled || _isBusy) return;
    final now = DateTime.now();
    if (now.difference(_lastFocusAdjustAt).inMilliseconds < 900) return;
    final controller = _activeController();
    if (controller == null) return;

    _isAdjustingFocus = true;
    _lastFocusAdjustAt = now;
    try {
      await controller.setFocusMode(FocusMode.auto);
      await controller.setExposureMode(ExposureMode.auto);
      await controller.setFocusPoint(const Offset(0.5, 0.5));
      await controller.setExposurePoint(const Offset(0.5, 0.5));
    } catch (_) {
      // Ignore focus point failures on unsupported devices.
    } finally {
      _isAdjustingFocus = false;
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

    final motionSamples = <int>[];
    const motionGrid = 4;
    final motionSpanX = math.max(1, x1 - x0);
    final motionSpanY = math.max(1, y1 - y0);
    for (int gy = 0; gy < motionGrid; gy++) {
      final y = y0 + ((motionSpanY * gy) / (motionGrid - 1)).round();
      final row = y * rowStride;
      for (int gx = 0; gx < motionGrid; gx++) {
        final x = x0 + ((motionSpanX * gx) / (motionGrid - 1)).round();
        final i = row + x * pixelStride;
        if (i >= 0 && i < bytes.length) {
          motionSamples.add(bytes[i]);
        }
      }
    }

    final step = (width ~/ 72).clamp(3, 12);

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
      return const _FrameStats(confidence: 0, candidate: false, motionScore: 1);
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

    final occluded =
        brightnessNorm < 0.09 ||
        brightnessNorm > 0.985 ||
        (varianceNorm < 0.0012 && edgeNorm < 0.04);

    if (occluded) {
      return const _FrameStats(confidence: 0, candidate: false, occluded: true);
    }

    final candidate =
        edgeNorm > 0.095 &&
        varianceNorm > 0.008 &&
        brightnessNorm > 0.20 &&
        brightnessNorm < 0.95;

    double motionScore = 0.0;
    if (_lastMotionSamples != null &&
        _lastMotionSamples!.length == motionSamples.length &&
        motionSamples.isNotEmpty) {
      var deltaSum = 0;
      for (var i = 0; i < motionSamples.length; i++) {
        deltaSum += (motionSamples[i] - _lastMotionSamples![i]).abs();
      }
      motionScore = (deltaSum / (motionSamples.length * 255.0)).clamp(0.0, 1.0);
    }
    _lastMotionSamples = motionSamples;

    return _FrameStats(
      confidence: confidence,
      candidate: candidate,
      motionScore: motionScore,
      occluded: false,
    );
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
      color: Colors.black,
      child: Stack(
        children: [
          Positioned.fill(
            child: FadeTransition(
              opacity: _cameraFade,
              child: SlideTransition(
                position: _cameraSlide,
                child: _buildCameraPreview(),
              ),
            ),
          ),
          Positioned.fill(
            child: FadeTransition(
              opacity: _overlayFade,
              child: _buildOverlayStack(),
            ),
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 16,
            right: 16,
            child: _buildTopBar(),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 24 + MediaQuery.of(context).padding.bottom,
            child: _buildBottomControls(),
          ),
          if (_lastCapturedImage != null && _batchMode)
            _buildThumbnailFlight(context),
          Positioned.fill(child: _buildFlashOverlay()),
          if (_isBusy) _buildScanningOverlay(),
        ],
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
          child: SizedBox(
            width: width,
            height: height,
            child: _isBusy
                ? _buildCameraBlockedPreview()
                : activeController != null
                ? CameraPreview(activeController)
                : _buildCameraPlaceholder(),
          ),
        );
      },
    );
  }

  Widget _buildCameraBlockedPreview() {
    return Container(
      color: Colors.black,
      alignment: Alignment.center,
      child: Text(
        widget.isAnalyzing ? 'Analyzing capture...' : 'Capturing...',
        style: const TextStyle(
          color: Colors.white70,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
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

  Widget _buildOverlayStack() {
    final confidencePct = (_detectionConfidence * 100)
        .clamp(0, 100)
        .toStringAsFixed(0);
    final phaseColor = switch (_scannerPhase) {
      _ScannerPhase.ready => AppColors.green,
      _ScannerPhase.awaitPageMove => Colors.amberAccent,
      _ScannerPhase.cooldown => Colors.white70,
      _ => Colors.white,
    };
    final guidance = switch (_scannerPhase) {
      _ScannerPhase.awaitPageMove => 'Move document to capture next page',
      _ScannerPhase.cooldown => 'Preparing next capture...',
      _ => _isStable
          ? (_autoCaptureEnabled
                ? 'Hold steady • auto-capture enabled'
                : 'Hold steady and tap capture')
          : (_autoCaptureEnabled
                ? _autoCaptureMode == _AutoCaptureMode.turnPage
                    ? 'Turn page, then hold after motion stops'
                    : 'Align page for perfect auto shot'
                : 'Tap capture anytime'),
    };

    return Stack(
      children: [
        Positioned(
          top: 88,
          left: 24,
          right: 24,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
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
                  color: phaseColor,
                ),
              ),
            ),
          ),
        ),
        Positioned(
          bottom: 160,
          left: 24,
          right: 24,
          child: Text(
            guidance,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: _scannerPhase == _ScannerPhase.ready
                  ? AppColors.green
                  : _scannerPhase == _ScannerPhase.awaitPageMove
                  ? Colors.amberAccent
                  : Colors.white54,
              fontWeight: _scannerPhase == _ScannerPhase.detecting
                  ? FontWeight.normal
                  : FontWeight.w600,
            ),
          ),
        ),
        if (_batchMode && _activeImages.isNotEmpty)
          Positioned(left: 16, bottom: 120, child: _buildBatchCounter()),
        // Live analyzing chip removed per request.
        Positioned.fill(
          child: IgnorePointer(
            child: Center(
              child: FadeTransition(
                opacity: _focusOpacity,
                child: ScaleTransition(
                  scale: _focusScale,
                  child: Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.5),
                        width: 1.4,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTopBar() {
    return Row(
      children: [
        _buildTopIcon(Icons.close, widget.onCancel, tooltip: 'Close'),
        const Spacer(),
        _buildFlashToggle(),
        if (_batchMode && _activeImages.isNotEmpty) ...[
          const SizedBox(width: 10),
          _buildDoneButton(),
        ],
      ],
    );
  }

  Widget _buildTopIcon(IconData icon, VoidCallback onTap, {String? tooltip}) {
    return GestureDetector(
      onTap: _isBusy ? null : onTap,
      child: Opacity(
        opacity: _isBusy ? 0.5 : 1,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          ),
          child: Icon(icon, size: 18, color: Colors.white),
        ),
      ),
    );
  }

  Widget _buildDoneButton() {
    return GestureDetector(
      onTap: _isBusy ? null : widget.onDone,
      child: Opacity(
        opacity: _isBusy ? 0.5 : 1,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.green,
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Text(
            'Done',
            style: TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFlashToggle() {
    IconData icon;
    String label;
    switch (_flashSetting) {
      case _FlashSetting.on:
        icon = Icons.flash_on;
        label = 'On';
      case _FlashSetting.off:
        icon = Icons.flash_off;
        label = 'Off';
      case _FlashSetting.auto:
        icon = Icons.flash_auto;
        label = 'Auto';
    }
    return GestureDetector(
      onTap: _isBusy ? null : _cycleFlashMode,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: Colors.white),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomControls() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildModeToggle(),
        if (_autoCaptureEnabled) ...[
          const SizedBox(height: 8),
          _buildAutoCaptureModeToggle(),
        ],
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _buildBottomIcon(Icons.photo_library, _onAddFromGallery),
            _buildCaptureButton(),
            _buildBottomIcon(
              _autoCaptureEnabled ? Icons.auto_mode : Icons.touch_app,
              _toggleAutoCapture,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAutoCaptureModeToggle() {
    return Container(
      height: 30,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildModeChip(
            'Standard',
            _autoCaptureMode == _AutoCaptureMode.standard,
            () => setState(() => _autoCaptureMode = _AutoCaptureMode.standard),
          ),
          _buildModeChip(
            'Turn Page',
            _autoCaptureMode == _AutoCaptureMode.turnPage,
            () => setState(() => _autoCaptureMode = _AutoCaptureMode.turnPage),
          ),
        ],
      ),
    );
  }

  Widget _buildBatchCounter() {
    final count = _activeImages.length;
    final latest = _activeImages.last;
    final scale = 1.0 + (_thumbController.value * 0.05);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Image.file(
              latest,
              width: 36,
              height: 50,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return Container(
                  width: 36,
                  height: 50,
                  color: Colors.white10,
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.image_not_supported,
                    size: 16,
                    color: Colors.white54,
                  ),
                );
              },
            ),
          ),
          const SizedBox(width: 10),
          Transform.scale(
            scale: scale,
            child: Text(
              'Pages: $count',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFlashOverlay() {
    return IgnorePointer(
      child: FadeTransition(
        opacity: _flashOpacity,
        child: Container(color: Colors.white),
      ),
    );
  }

  Widget _buildThumbnailFlight(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final start =
            _thumbStart ??
            Offset(
              constraints.maxWidth / 2 - 80,
              constraints.maxHeight / 2 - 110,
            );
        final end =
            _thumbEnd ??
            Offset(
              26,
              constraints.maxHeight -
                  24 -
                  MediaQuery.of(context).padding.bottom -
                  160,
            );
        _thumbStart = start;
        _thumbEnd = end;

        final position = Tween<Offset>(begin: start, end: end).animate(
          CurvedAnimation(parent: _thumbController, curve: Curves.easeOutCubic),
        );
        final scale = Tween<double>(begin: 1.0, end: 0.3).animate(
          CurvedAnimation(parent: _thumbController, curve: Curves.easeOut),
        );
        final opacity = Tween<double>(begin: 0.0, end: 1.0).animate(
          CurvedAnimation(parent: _thumbController, curve: Curves.easeIn),
        );

        return AnimatedBuilder(
          animation: _thumbController,
          builder: (context, child) {
            return Positioned(
              left: position.value.dx,
              top: position.value.dy,
              child: Opacity(
                opacity: opacity.value,
                child: Transform.scale(scale: scale.value, child: child),
              ),
            );
          },
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.file(
              _lastCapturedImage!,
              width: 160,
              height: 220,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return Container(
                  width: 160,
                  height: 220,
                  color: Colors.white10,
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.image_not_supported,
                    color: Colors.white54,
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildBottomIcon(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: _isBusy ? null : onTap,
      child: Opacity(
        opacity: _isBusy ? 0.5 : 1,
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.35),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
          ),
          child: Icon(icon, size: 22, color: Colors.white),
        ),
      ),
    );
  }

  Widget _buildModeToggle() {
    return Container(
      height: 34,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildModeChip('Single', !_batchMode, () {
            setState(() => _batchMode = false);
            widget.onBatchModeChanged(false);
          }),
          _buildModeChip('Batch', _batchMode, () {
            setState(() => _batchMode = true);
            widget.onBatchModeChanged(true);
          }),
        ],
      ),
    );
  }

  Widget _buildModeChip(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: _isBusy ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.black : Colors.white70,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
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

  // Menu removed per design.

  void _cycleFlashMode() {
    setState(() {
      _flashSetting = switch (_flashSetting) {
        _FlashSetting.auto => _FlashSetting.on,
        _FlashSetting.on => _FlashSetting.off,
        _FlashSetting.off => _FlashSetting.auto,
      };
    });
    widget.onFlashModeChanged(_flashSettingLabel(_flashSetting));
    _applyFlashMode();
  }

  void _applyFlashMode() {
    final controller = _activeController();
    if (controller == null) return;
    try {
      final mode = switch (_flashSetting) {
        _FlashSetting.auto => FlashMode.auto,
        _FlashSetting.on => FlashMode.always,
        _FlashSetting.off => FlashMode.off,
      };
      unawaited(controller.setFlashMode(mode));
    } catch (_) {
      // Ignore flash errors on unsupported devices.
    }
  }

  void _toggleAutoCapture() {
    setState(() {
      _autoCaptureEnabled = !_autoCaptureEnabled;
      _awaitingDocumentMoveAfterAutoCapture = false;
      _autoCapturedSinceUnstable = false;
      _missingDocumentFrames = 0;
      _turnPageMotionDetected = false;
      _turnPageSettledSince = null;
      _scannerPhase = _ScannerPhase.detecting;
    });
  }

  Future<void> _onCapture({required bool autoTriggered}) async {
    if (_isBusy) return;
    final beforeCount = _activeImages.length;

    final manualAutoModeBlocked =
        _autoCaptureEnabled &&
        _liveAnalyzerAvailable &&
        !_isStable &&
        !autoTriggered;
    if (manualAutoModeBlocked) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Auto mode: wait for perfect shot or disable Auto'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    setState(() {
      _isCaptureActionPending = true;
      _scannerPhase = _ScannerPhase.capturing;
      _isStable = false;
      _stableFrameCount = 0;
      _detectionConfidence = 0;
      _liveStatus = autoTriggered
          ? 'Auto capture in progress...'
          : 'Capturing image...';
    });

    await _stopLiveAnalyzer();

    var capturedAdded = false;
    try {
      await widget.onCapture();
    } finally {
      if (mounted) {
        capturedAdded = _activeImages.length > beforeCount;
        setState(() {
          _isCaptureActionPending = false;
          if (widget.isAnalyzing) {
            _scannerPhase = _ScannerPhase.analyzingLocked;
          } else {
            _setCooldown();
          }
          _liveStatus = capturedAdded && _batchMode
              ? 'Page ${_activeImages.length} added'
              : 'Searching for document...';
          if (autoTriggered && capturedAdded) {
            _autoCapturedSinceUnstable = true;
          }
        });
      }
    }
    if (!mounted) return;
    if (capturedAdded && !_batchMode) {
      _triggerCaptureFeedback();
      widget.onDone();
      return;
    }
    if (capturedAdded && _batchMode) {
      _triggerCaptureFeedback();
    }
    if (!widget.isAnalyzing) {
      unawaited(_startLiveAnalyzerIfPossible());
    }
    if (autoTriggered && capturedAdded) {
      _awaitingDocumentMoveAfterAutoCapture = true;
    }
  }

  Future<void> _onAddFromGallery() async {
    if (_isBusy) return;
    final beforeCount = _activeImages.length;
    setState(() {
      _isCaptureActionPending = true;
      _scannerPhase = _ScannerPhase.capturing;
      _isStable = false;
      _stableFrameCount = 0;
      _detectionConfidence = 0;
      _liveStatus = 'Adding image from gallery...';
    });

    await _stopLiveAnalyzer();

    var capturedAdded = false;
    try {
      await widget.onAddFromGallery();
    } finally {
      if (mounted) {
        capturedAdded = _activeImages.length > beforeCount;
        setState(() {
          _isCaptureActionPending = false;
          if (widget.isAnalyzing) {
            _scannerPhase = _ScannerPhase.analyzingLocked;
          } else {
            _setCooldown();
          }
          _liveStatus = capturedAdded && _batchMode
              ? 'Page ${_activeImages.length} added'
              : 'Searching for document...';
        });
      }
    }
    if (!mounted) return;
    if (capturedAdded && !_batchMode) {
      widget.onDone();
      return;
    }
    if (capturedAdded && _batchMode) {
      _triggerCaptureFeedback();
    }
    if (!widget.isAnalyzing) {
      unawaited(_startLiveAnalyzerIfPossible());
    }
  }

  void _triggerCaptureFeedback() {
    if (!mounted) return;
    _flashController.forward(from: 0).then((_) {
      if (mounted) {
        _flashController.reverse();
      }
    });
    if (_activeImages.isEmpty) return;
    _lastCapturedImage = _activeImages.last;
    _thumbStart = null;
    _thumbEnd = null;
    if (_batchMode) {
      _thumbController.forward(from: 0);
    }
  }

  _FlashSetting _flashSettingFromString(String value) {
    switch (value.trim().toLowerCase()) {
      case 'on':
        return _FlashSetting.on;
      case 'off':
        return _FlashSetting.off;
      default:
        return _FlashSetting.auto;
    }
  }

  String _flashSettingLabel(_FlashSetting setting) {
    switch (setting) {
      case _FlashSetting.on:
        return 'On';
      case _FlashSetting.off:
        return 'Off';
      case _FlashSetting.auto:
        return 'Auto';
    }
  }

  Widget _buildScanningOverlay() {
    return Container(
      color: Colors.black.withValues(alpha: 0.64),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              widget.isAnalyzing ? 'Analyzing document...' : 'Capturing image...',
              style: const TextStyle(
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
          ],
        ),
      ),
    );
  }
}

class _FrameStats {
  final double confidence;
  final bool candidate;
  final bool occluded;
  final double motionScore;

  const _FrameStats({
    required this.confidence,
    required this.candidate,
    this.motionScore = 0.0,
    this.occluded = false,
  });
}
