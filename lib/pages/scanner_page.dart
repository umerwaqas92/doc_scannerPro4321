import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import '../theme/app_theme.dart';
import '../models/scanner_steps.dart';

class ScannerPage extends StatefulWidget {
  final VoidCallback onCancel;
  final VoidCallback onDone;
  final VoidCallback onCapture;
  final VoidCallback onAddFromGallery;
  final CameraController? cameraController;
  final bool isCameraInitialized;
  final List<File> capturedImages;
  final Function(int) onRemoveImage;

  final String? cameraErrorMessage;

  const ScannerPage({
    super.key,
    required this.onCancel,
    required this.onDone,
    required this.onCapture,
    required this.onAddFromGallery,
    required this.cameraController,
    required this.isCameraInitialized,
    required this.capturedImages,
    required this.onRemoveImage,
    this.cameraErrorMessage,
  });

  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage>
    with TickerProviderStateMixin {
  int _selectedFilter = 0;
  final List<String> _filters = ['Auto', 'B&W', 'Color', 'Grayscale', 'Photo'];

  bool _isScanning = false;
  ScannerStep _currentStep = ScannerStep.preScanPrep;
  bool _didReachScanningStep = false;

  late AnimationController _scanLineController;
  late AnimationController _captureFlashController;
  late Animation<double> _scanLineAnimation;
  late Animation<double> _flashAnimation;

  @override
  void initState() {
    super.initState();
    _currentStep = ScannerStep.initialization;

    _scanLineController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );

    _captureFlashController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    _scanLineAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _scanLineController, curve: Curves.easeInOut),
    );

    _flashAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _captureFlashController, curve: Curves.easeOut),
    );

    _scanLineController.repeat();
  }

  @override
  void didUpdateWidget(ScannerPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isCameraInitialized && !_didReachScanningStep) {
      _didReachScanningStep = true;
      setState(() => _currentStep = ScannerStep.scanning);
    }
  }

  @override
  void dispose() {
    _scanLineController.dispose();
    _captureFlashController.dispose();
    super.dispose();
  }

  void _onCapture() {
    debugPrint('Capture button pressed, isScanning: $_isScanning');
    if (_isScanning) return;

    setState(() {
      _isScanning = true;
      _currentStep = ScannerStep.adConversion;
    });

    _captureFlashController.forward(from: 0);
    debugPrint('Starting capture process...');

    Future.delayed(const Duration(milliseconds: 280), () {
      if (!mounted) return;
      setState(() => _currentStep = ScannerStep.imageProcessing);
    });
    Future.delayed(const Duration(milliseconds: 180), () {
      if (!mounted) return;
      widget.onCapture();
    });
    Future.delayed(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      setState(() => _currentStep = ScannerStep.imageFormation);
    });
    Future.delayed(const Duration(milliseconds: 600), () {
      if (!mounted) return;
      setState(() => _currentStep = ScannerStep.postScan);
      Future.delayed(const Duration(milliseconds: 700), () {
        if (!mounted) return;
        setState(() {
          _isScanning = false;
          _currentStep = ScannerStep.scanning;
        });
      });
    });
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
              _buildStepIndicator(),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      _buildCameraPreview(),
                      _buildFilterStrip(),
                      _buildCaptureControls(),
                      _buildThumbStrip(),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
            ],
          ),
          IgnorePointer(
            ignoring: true,
            child: AnimatedBuilder(
              animation: _flashAnimation,
              builder: (context, child) {
                return Container(
                  color: Colors.white.withValues(
                    alpha: _flashAnimation.value * 0.5,
                  ),
                );
              },
            ),
          ),
          if (_isScanning) _buildScanningOverlay(),
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
          _buildHeaderButton('✕ Cancel', widget.onCancel),
          Text(
            widget.capturedImages.isEmpty
                ? 'Scan Document'
                : '${widget.capturedImages.length} scanned',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          _buildHeaderButton('Done', widget.onDone),
        ],
      ),
    );
  }

  Widget _buildStepIndicator() {
    final isProcessingStep = _currentStep.stepNumber >= ScannerStep.adConversion.stepNumber &&
        _currentStep.stepNumber <= ScannerStep.imageFormation.stepNumber;
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: isProcessingStep ? 0.15 : 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.12),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              'Step ${_currentStep.stepNumber} of ${ScannerStep.totalSteps}',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _currentStep.title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: Colors.white.withValues(alpha: 0.9),
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderButton(String text, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
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
    );
  }

  Widget _buildCameraPreview() {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      height: 380,
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(16),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          fit: StackFit.expand,
          children: [
            widget.isCameraInitialized && widget.cameraController != null
                ? CameraPreview(widget.cameraController!)
                : _buildCameraPlaceholder(),
            _buildViewfinderOverlay(),
            _buildScanLine(),
          ],
        ),
      ),
    );
  }

  Widget _buildCameraPlaceholder() {
    final step1 = ScannerStep.preScanPrep;
    final errorMessage = widget.cameraErrorMessage;

    return Container(
      color: Colors.black,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              errorMessage != null ? Icons.error_outline : Icons.camera_alt_outlined,
              size: 64,
              color: errorMessage != null ? Colors.redAccent.withValues(alpha: 0.6) : Colors.white24,
            ),
            const SizedBox(height: 16),
            Text(
              errorMessage ?? 'Camera not available',
              style: TextStyle(
                color: errorMessage != null ? Colors.redAccent.withValues(alpha: 0.7) : Colors.white54,
                fontSize: 14,
                fontWeight: errorMessage != null ? FontWeight.w600 : FontWeight.normal,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                errorMessage != null
                    ? 'Check permissions or restart your device if this persists.'
                    : 'Please run on a physical device to use camera',
                style: const TextStyle(color: Colors.white38, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                '${step1.title}: ${step1.description}',
                style: const TextStyle(color: Colors.white38, fontSize: 11),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildViewfinderOverlay() {
    return Stack(
      children: [
        Center(
          child: Container(
            width: 220,
            height: 290,
            decoration: BoxDecoration(
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.7),
                width: 2,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Stack(
              children: [
                Positioned(top: -2, left: -2, child: _buildCorner(true, true)),
                Positioned(
                  top: -2,
                  right: -2,
                  child: _buildCorner(true, false),
                ),
                Positioned(
                  bottom: -2,
                  left: -2,
                  child: _buildCorner(false, true),
                ),
                Positioned(
                  bottom: -2,
                  right: -2,
                  child: _buildCorner(false, false),
                ),
              ],
            ),
          ),
        ),
        const Positioned(
          bottom: 14,
          left: 0,
          right: 0,
          child: Text(
            'Align document within frame',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Colors.white54),
          ),
        ),
      ],
    );
  }

  Widget _buildCorner(bool isTop, bool isLeft) {
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        border: Border(
          top: isTop
              ? BorderSide(color: Colors.white, width: 3)
              : BorderSide.none,
          bottom: !isTop
              ? BorderSide(color: Colors.white, width: 3)
              : BorderSide.none,
          left: isLeft
              ? BorderSide(color: Colors.white, width: 3)
              : BorderSide.none,
          right: !isLeft
              ? BorderSide(color: Colors.white, width: 3)
              : BorderSide.none,
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

  Widget _buildScanLine() {
    return AnimatedBuilder(
      animation: _scanLineAnimation,
      builder: (context, child) {
        return CustomPaint(
          painter: ScanLinePainter(progress: _scanLineAnimation.value),
          size: Size.infinite,
        );
      },
    );
  }

  Widget _buildFilterStrip() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Row(
        children: List.generate(_filters.length, (index) {
          final isSelected = _selectedFilter == index;
          return GestureDetector(
            onTap: () => setState(() => _selectedFilter = index),
            child: Container(
              margin: const EdgeInsets.only(right: 10),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: isSelected ? Colors.white : Colors.transparent,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: Colors.white.withValues(alpha: isSelected ? 1 : 0.18),
                ),
              ),
              child: Text(
                _filters[index],
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: isSelected
                      ? Colors.black
                      : Colors.white.withValues(alpha: 0.65),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildCaptureControls() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(40, 24, 40, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _buildCtrlButton(
            Icons.photo_library_outlined,
            widget.onAddFromGallery,
          ),
          _buildCaptureButton(),
          _buildCtrlButton(Icons.flip_outlined, () {}),
        ],
      ),
    );
  }

  Widget _buildCtrlButton(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
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
    );
  }

  Widget _buildCaptureButton() {
    return GestureDetector(
      onTap: _onCapture,
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
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: _isScanning
                  ? const SizedBox(
                      key: ValueKey('loading'),
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(
                        color: AppColors.green,
                        strokeWidth: 3,
                      ),
                    )
                  : Container(
                      key: const ValueKey('capture'),
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

  Widget _buildScanningOverlay() {
    final showStepDetail = _currentStep.stepNumber >= ScannerStep.adConversion.stepNumber &&
        _currentStep.stepNumber <= ScannerStep.imageFormation.stepNumber;
    return Container(
      color: Colors.black.withValues(alpha: 0.5),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 120,
                  height: 120,
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    strokeWidth: 4,
                  ),
                ),
                Icon(
                  _currentStep == ScannerStep.postScan
                      ? Icons.check_circle
                      : Icons.document_scanner,
                  size: 50,
                  color: Colors.white,
                ),
              ],
            ),
            const SizedBox(height: 24),
            Text(
              showStepDetail ? _currentStep.title : 'Scanning document...',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              showStepDetail
                  ? _currentStep.description
                  : 'Processing image',
              style: const TextStyle(color: Colors.white70, fontSize: 14),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThumbStrip() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Row(
        children: [
          ...List.generate(widget.capturedImages.length, (index) {
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _buildThumbItem(index),
            );
          }),
          _buildThumbAddButton(),
        ],
      ),
    );
  }

  Widget _buildThumbItem(int index) {
    final image = widget.capturedImages[index];
    return GestureDetector(
      onTap: () => widget.onRemoveImage(index),
      child: Container(
        width: 44,
        height: 58,
        decoration: BoxDecoration(
          color: const Color(0xFF2A2A28),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        ),
        child: Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.file(
                image,
                width: 44,
                height: 58,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return const Center(
                    child: Icon(Icons.image, color: Colors.white54, size: 20),
                  );
                },
              ),
            ),
            Positioned(
              bottom: 3,
              right: 3,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  '${index + 1}',
                  style: const TextStyle(
                    fontSize: 9,
                    color: Colors.white,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThumbAddButton() {
    return GestureDetector(
      onTap: widget.onAddFromGallery,
      child: Container(
        width: 44,
        height: 58,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.2),
            style: BorderStyle.solid,
          ),
        ),
        child: Center(
          child: Icon(
            Icons.add,
            size: 18,
            color: Colors.white.withValues(alpha: 0.3),
          ),
        ),
      ),
    );
  }
}

class ScanLinePainter extends CustomPainter {
  final double progress;

  ScanLinePainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.transparent,
          Colors.white.withValues(alpha: 0.8),
          Colors.white.withValues(alpha: 0.8),
          Colors.transparent,
        ],
        stops: const [0.0, 0.3, 0.7, 1.0],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    final y = size.height * progress;
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(20, y - 15, size.width - 40, 30),
      const Radius.circular(4),
    );
    canvas.drawRRect(rect, paint);

    final glowPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.3)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    canvas.drawRRect(rect, glowPaint);
  }

  @override
  bool shouldRepaint(ScanLinePainter oldDelegate) =>
      oldDelegate.progress != progress;
}
