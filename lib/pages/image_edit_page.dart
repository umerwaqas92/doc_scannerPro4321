import 'dart:io';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/document_scanner_service.dart';

class ImageEditPage extends StatefulWidget {
  final List<File> images;
  final Function(List<File>) onSave;

  const ImageEditPage({super.key, required this.images, required this.onSave});

  @override
  State<ImageEditPage> createState() => _ImageEditPageState();
}

class _ImageEditPageState extends State<ImageEditPage> {
  int _currentPage = 0;
  double _brightness = 1.0;
  double _contrast = 1.0;
  double _rotation = 0.0;
  int _selectedFilter = 0;
  bool _isProcessing = false;
  List<File> _editedImages = [];
  final DocumentScannerService _scannerService = DocumentScannerService();

  final List<String> _filters = ['Original', 'Enhanced', 'B&W', 'Grayscale'];

  @override
  void initState() {
    super.initState();
    _editedImages = List.from(widget.images);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.text),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Edit Image',
          style: TextStyle(color: AppColors.text),
        ),
        actions: [
          TextButton(
            onPressed: _saveChanges,
            child: const Text(
              'Save',
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
          _buildControls(),
        ],
      ),
    );
  }

  Widget _buildImagePreview() {
    if (_editedImages.isEmpty) {
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
              color: Colors.black.withOpacity(0.1),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: ColorFiltered(
            colorFilter: _getColorFilter(),
            child: Transform.rotate(
              angle: _rotation * 3.14159 / 180,
              child: Image.file(
                _editedImages[_currentPage],
                fit: BoxFit.contain,
              ),
            ),
          ),
        ),
      ),
    );
  }

  ColorFilter _getColorFilter() {
    switch (_selectedFilter) {
      case 2:
        return const ColorFilter.matrix(<double>[
          0.2126,
          0.7152,
          0.0722,
          0,
          0,
          0.2126,
          0.7152,
          0.0722,
          0,
          0,
          0.2126,
          0.7152,
          0.0722,
          0,
          0,
          0,
          0,
          0,
          1,
          0,
        ]);
      case 3:
        return const ColorFilter.matrix(<double>[
          0.333,
          0.333,
          0.333,
          0,
          0,
          0.333,
          0.333,
          0.333,
          0,
          0,
          0.333,
          0.333,
          0.333,
          0,
          0,
          0,
          0,
          0,
          1,
          0,
        ]);
      default:
        return const ColorFilter.mode(Colors.transparent, BlendMode.dst);
    }
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

  Widget _buildControls() {
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
            _buildSlider('Brightness', _brightness, 0.5, 1.5, (v) {
              setState(() => _brightness = v);
            }),
            _buildSlider('Contrast', _contrast, 0.5, 2.0, (v) {
              setState(() => _contrast = v);
            }),
            const SizedBox(height: 16),
            const Text(
              'Filters',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: List.generate(_filters.length, (index) {
                return ChoiceChip(
                  label: Text(_filters[index]),
                  selected: _selectedFilter == index,
                  onSelected: (selected) {
                    setState(() => _selectedFilter = index);
                  },
                );
              }),
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
                  setState(() => _rotation -= 90);
                }),
                _buildRotateBtn(Icons.rotate_right, 'Right', () {
                  setState(() => _rotation += 90);
                }),
                _buildRotateBtn(Icons.restore, 'Reset', () {
                  setState(() {
                    _brightness = 1.0;
                    _contrast = 1.0;
                    _rotation = 0.0;
                    _selectedFilter = 0;
                  });
                }),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isProcessing ? null : _applyAndSave,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.text,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: _isProcessing
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text('Apply Changes'),
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
    Function(double) onChanged,
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

  void _applyAndSave() async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);

    try {
      for (int i = 0; i < widget.images.length; i++) {
        final original = widget.images[i];
        var adjusted = await _scannerService.applyAdjustments(
          original,
          brightness: _brightness,
          contrast: _contrast,
          rotation: i == _currentPage ? _rotation : 0,
          filter: i == _currentPage ? _selectedFilter : 0,
        );
        if (adjusted != null) {
          _editedImages[i] = adjusted;
        }
      }
      widget.onSave(_editedImages);
    } catch (e) {
      debugPrint('Error applying changes: $e');
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  void _saveChanges() {
    widget.onSave(_editedImages);
  }
}
