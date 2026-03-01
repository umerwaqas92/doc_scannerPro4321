import 'dart:io';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/ocr_service.dart';

class ScanResultPage extends StatefulWidget {
  final List<File> scannedImages;
  final List<OcrResult> ocrResults;
  final bool isProcessingOcr;
  final VoidCallback onRetry;
  final VoidCallback onSave;
  final VoidCallback onBack;
  final Function(int) onRemoveImage;
  final VoidCallback onAddMore;
  final VoidCallback onProcessOcr;
  final Function(String) onTextChanged;

  const ScanResultPage({
    super.key,
    required this.scannedImages,
    required this.ocrResults,
    required this.isProcessingOcr,
    required this.onRetry,
    required this.onSave,
    required this.onBack,
    required this.onRemoveImage,
    required this.onAddMore,
    required this.onProcessOcr,
    required this.onTextChanged,
  });

  @override
  State<ScanResultPage> createState() => _ScanResultPageState();
}

class _ScanResultPageState extends State<ScanResultPage>
    with SingleTickerProviderStateMixin {
  int _currentPage = 0;
  int _selectedTab = 0;
  final PageController _pageController = PageController();
  final TextEditingController _textController = TextEditingController();
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      setState(() {
        _selectedTab = _tabController.index;
      });
    });
    _updateTextController();
  }

  void _updateTextController() {
    if (widget.ocrResults.isNotEmpty &&
        _currentPage < widget.ocrResults.length) {
      _textController.text = widget.ocrResults[_currentPage].text;
    } else {
      _textController.text = '';
    }
  }

  @override
  void didUpdateWidget(ScanResultPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scannedImages != widget.scannedImages) {
      _updateTextController();
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    _tabController.dispose();
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            _buildTabBar(),
            Expanded(
              child: _selectedTab == 0 ? _buildImageView() : _buildTextView(),
            ),
            _buildBottomActions(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: Row(
        children: [
          GestureDetector(
            onTap: widget.onBack,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.surface,
                border: Border.all(color: AppColors.border),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.arrow_back_ios_new,
                size: 18,
                color: AppColors.text,
              ),
            ),
          ),
          const Expanded(
            child: Text(
              'Scan Result',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppColors.text,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(width: 40),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: TabBar(
        controller: _tabController,
        labelColor: Colors.white,
        unselectedLabelColor: AppColors.text2,
        indicatorSize: TabBarIndicatorSize.tab,
        indicator: BoxDecoration(
          color: AppColors.text,
          borderRadius: BorderRadius.circular(10),
        ),
        tabs: const [
          Tab(text: 'Image'),
          Tab(text: 'Text (OCR)'),
        ],
      ),
    );
  }

  Widget _buildImageView() {
    if (widget.scannedImages.isEmpty) {
      return _buildEmptyState();
    }

    return Column(
      children: [
        Expanded(
          child: PageView.builder(
            controller: _pageController,
            onPageChanged: (index) {
              setState(() {
                _currentPage = index;
                _updateTextController();
              });
            },
            itemCount: widget.scannedImages.length,
            itemBuilder: (context, index) {
              return _buildImagePreview(widget.scannedImages[index], index);
            },
          ),
        ),
        _buildPageIndicator(),
        _buildQualityInfo(),
      ],
    );
  }

  Widget _buildTextView() {
    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppColors.border),
              ),
              child: widget.isProcessingOcr
                  ? _buildProcessingState()
                  : _buildTextEditor(),
            ),
          ),
        ),
        if (widget.scannedImages.isNotEmpty) _buildOcrButton(),
      ],
    );
  }

  Widget _buildProcessingState() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: AppColors.text),
          SizedBox(height: 16),
          Text(
            'Processing OCR...',
            style: TextStyle(fontSize: 16, color: AppColors.text2),
          ),
          SizedBox(height: 8),
          Text(
            'Extracting text from images',
            style: TextStyle(fontSize: 14, color: AppColors.text3),
          ),
        ],
      ),
    );
  }

  Widget _buildTextEditor() {
    final hasText =
        widget.ocrResults.isNotEmpty &&
        _currentPage < widget.ocrResults.length &&
        widget.ocrResults[_currentPage].text.isNotEmpty;

    if (!hasText) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.text_fields, size: 64, color: AppColors.text3),
            const SizedBox(height: 16),
            const Text(
              'No text detected',
              style: TextStyle(fontSize: 16, color: AppColors.text2),
            ),
            const SizedBox(height: 8),
            const Text(
              'Tap "Extract Text" to scan for text',
              style: TextStyle(fontSize: 14, color: AppColors.text3),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.edit_note, size: 20, color: AppColors.text2),
              const SizedBox(width: 8),
              const Text(
                'Edit extracted text',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppColors.text2,
                ),
              ),
              const Spacer(),
              Text(
                'Page ${_currentPage + 1}',
                style: const TextStyle(fontSize: 12, color: AppColors.text3),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: TextField(
              controller: _textController,
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.text,
                height: 1.6,
              ),
              decoration: const InputDecoration(
                border: InputBorder.none,
                hintText: 'No text detected in this image',
                hintStyle: TextStyle(color: AppColors.text3),
              ),
              onChanged: widget.onTextChanged,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOcrButton() {
    final hasValidResults =
        widget.ocrResults.isNotEmpty &&
        widget.ocrResults.any((r) => r.text.isNotEmpty);

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Expanded(
            child: ElevatedButton.icon(
              onPressed: widget.isProcessingOcr ? null : widget.onProcessOcr,
              icon: widget.isProcessingOcr
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.text_snippet),
              label: Text(
                widget.isProcessingOcr
                    ? 'Processing...'
                    : hasValidResults
                    ? 'Refresh Text'
                    : 'Extract Text',
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.text,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.image_not_supported_outlined,
            size: 64,
            color: AppColors.text3,
          ),
          const SizedBox(height: 16),
          const Text(
            'No images scanned',
            style: TextStyle(fontSize: 16, color: AppColors.text2),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: widget.onRetry,
            icon: const Icon(Icons.camera_alt),
            label: const Text('Scan Again'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.text,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImagePreview(File image, int index) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Expanded(
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
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.file(
                      image,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) {
                        return _buildErrorWidget();
                      },
                    ),
                    Positioned(
                      top: 12,
                      right: 12,
                      child: GestureDetector(
                        onTap: () => widget.onRemoveImage(index),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.5),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.close,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQualityInfo() {
    if (widget.ocrResults.isEmpty || _currentPage >= widget.ocrResults.length) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: const Row(
            children: [
              Icon(Icons.info_outline, color: AppColors.text3, size: 20),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Tap "Text (OCR)" tab to extract and edit text',
                  style: TextStyle(fontSize: 13, color: AppColors.text3),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final result = widget.ocrResults[_currentPage];
    final hasText = result.text.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: hasText ? AppColors.greenBg : AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: hasText ? AppColors.green : AppColors.border,
          ),
        ),
        child: Row(
          children: [
            Icon(
              hasText ? Icons.check_circle : Icons.warning_amber,
              color: hasText ? AppColors.green : Colors.orange,
              size: 20,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                hasText
                    ? 'Text extracted successfully'
                    : 'No text detected. Try scanning again with better lighting.',
                style: TextStyle(
                  fontSize: 13,
                  color: hasText ? AppColors.green : Colors.orange,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorWidget() {
    return Container(
      color: AppColors.surface2,
      child: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.red),
            SizedBox(height: 16),
            Text(
              'Could not load image',
              style: TextStyle(fontSize: 16, color: AppColors.text2),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPageIndicator() {
    if (widget.scannedImages.length <= 1) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(
          widget.scannedImages.length,
          (index) => GestureDetector(
            onTap: () {
              _pageController.animateToPage(
                index,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
              );
            },
            child: Container(
              width: 8,
              height: 8,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _currentPage == index
                    ? AppColors.text
                    : AppColors.border,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomActions() {
    return Container(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: widget.onAddMore,
              icon: const Icon(Icons.add_photo_alternate),
              label: const Text('Add More'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.text,
                side: const BorderSide(color: AppColors.border),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: widget.scannedImages.isEmpty ? null : widget.onSave,
              icon: const Icon(Icons.check),
              label: const Text('Save'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.text,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
