import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import '../theme/app_theme.dart';

class ScannerPage extends StatefulWidget {
  final VoidCallback onCancel;
  final VoidCallback onDone;
  final VoidCallback onCapture;
  final VoidCallback onAddFromGallery;

  const ScannerPage({
    super.key,
    required this.onCancel,
    required this.onDone,
    required this.onCapture,
    required this.onAddFromGallery,
  });

  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage> {
  int _selectedFilter = 0;
  final List<String> _filters = ['Auto', 'B&W', 'Color', 'Grayscale', 'Photo'];
  List<File> _capturedImages = [];

  void addImage(File image) {
    setState(() {
      _capturedImages.add(image);
    });
  }

  void removeImage(int index) {
    setState(() {
      _capturedImages.removeAt(index);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.scannerBg,
      child: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  _buildViewfinder(),
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
            _capturedImages.isEmpty
                ? 'Scan Document'
                : '${_capturedImages.length} scanned',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          _buildHeaderButton(
            _capturedImages.isEmpty ? 'Skip' : 'Done',
            widget.onDone,
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

  Widget _buildViewfinder() {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      height: 380,
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Stack(
        children: [
          Center(
            child: Container(
              width: 220,
              height: 290,
              decoration: BoxDecoration(
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.85),
                  width: 2,
                ),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Stack(
                children: [
                  Positioned(
                    top: -1,
                    left: -1,
                    child: _buildCorner(true, true),
                  ),
                  Positioned(
                    top: -1,
                    right: -1,
                    child: _buildCorner(true, false),
                  ),
                  Positioned(
                    bottom: -1,
                    left: -1,
                    child: _buildCorner(false, true),
                  ),
                  Positioned(
                    bottom: -1,
                    right: -1,
                    child: _buildCorner(false, false),
                  ),
                  _buildScanLine(),
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
      ),
    );
  }

  Widget _buildCorner(bool isTop, bool isLeft) {
    return Container(
      width: 18,
      height: 18,
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
          topLeft: isTop && isLeft ? const Radius.circular(2) : Radius.zero,
          topRight: isTop && !isLeft ? const Radius.circular(2) : Radius.zero,
          bottomLeft: !isTop && isLeft ? const Radius.circular(2) : Radius.zero,
          bottomRight: !isTop && !isLeft
              ? const Radius.circular(2)
              : Radius.zero,
        ),
      ),
    );
  }

  Widget _buildScanLine() {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(seconds: 2),
      builder: (context, value, child) {
        return Positioned(
          top: 4 + (value * 276),
          left: 2,
          right: 2,
          child: Container(
            height: 2,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.transparent,
                  Colors.white.withValues(alpha: 0.9),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        );
      },
      onEnd: () => setState(() {}),
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
          _buildCtrlButton(Icons.bolt_outlined, widget.onAddFromGallery),
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
      onTap: widget.onCapture,
      child: Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.white.withValues(alpha: 0.2),
              blurRadius: 5,
              spreadRadius: 5,
            ),
          ],
        ),
        child: Center(
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.black, width: 3),
            ),
          ),
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
          ...List.generate(_capturedImages.length, (index) {
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _buildThumbItem(true, index),
            );
          }),
          _buildThumbAddButton(),
        ],
      ),
    );
  }

  Widget _buildThumbItem(bool hasContent, int index) {
    return GestureDetector(
      onTap: () => removeImage(index),
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
            if (_capturedImages[index].path.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.file(
                  _capturedImages[index],
                  width: 44,
                  height: 58,
                  fit: BoxFit.cover,
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
