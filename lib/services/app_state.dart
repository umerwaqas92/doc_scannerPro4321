import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import '../models/scanned_document.dart';
import '../models/scan_pipeline_models.dart';
import 'storage_service.dart';
import 'camera_service.dart';
import 'image_picker_service.dart';
import 'pdf_service.dart';
import 'settings_service.dart';
import 'ocr_service.dart';
import 'scan_pipeline_service.dart';
import 'export_optimization_service.dart';
import 'export_service.dart';
import 'package:image/image.dart' as img;

class AppState extends ChangeNotifier {
  final StorageService _storageService = StorageService();
  final CameraService _cameraService = CameraService();
  final ImagePickerService _imagePickerService = ImagePickerService();
  final PdfService _pdfService = PdfService();
  final SettingsService _settingsService = SettingsService();
  final OcrService _ocrService = OcrService();
  final ScanPipelineService _scanPipelineService = ScanPipelineService();
  final ExportOptimizationService _exportOptimizationService =
      ExportOptimizationService();
  final ExportService _exportService = ExportService();

  List<ScannedDocument> _documents = [];
  List<File> _capturedImages = [];
  List<ScanPipelineResult?> _pipelineResults = [];
  List<OcrResult> _ocrResults = [];
  bool _batchActive = false;
  final List<File> _batchRawImages = [];
  final Map<int, String> _editedOcrTexts = {};
  ScannedDocument? _selectedDocument;
  bool _isLoading = false;
  bool _isProcessingOcr = false;
  bool _cameraInitialized = false;
  int _activeAnalysisCount = 0;
  String? _analysisStageText;
  DocumentFilterMode _captureFilterMode = DocumentFilterMode.original;

  // Settings
  bool _autoCrop = true;
  String _flashMode = 'Auto';
  String _defaultFormat = 'PDF';
  bool _cloudBackup = false;

  // Getters
  List<ScannedDocument> get documents => _documents;
  List<File> get capturedImages => _capturedImages;
  List<ScanPipelineResult?> get pipelineResults => _pipelineResults;
  List<OcrResult> get ocrResults => _ocrResults;
  bool get isBatchActive => _batchActive;
  List<File> get batchRawImages => List.unmodifiable(_batchRawImages);
  ScannedDocument? get selectedDocument => _selectedDocument;
  bool get isLoading => _isLoading;
  bool get isProcessingOcr => _isProcessingOcr;
  bool get cameraInitialized => _cameraInitialized;
  bool get isAnalyzing => _activeAnalysisCount > 0;
  String? get analysisStageText => _analysisStageText;
  DocumentFilterMode get captureFilterMode => _captureFilterMode;
  CameraService get cameraService => _cameraService;

  bool get autoCrop => _autoCrop;
  String get flashMode => _flashMode;
  String get defaultFormat => _defaultFormat;
  bool get cloudBackup => _cloudBackup;
  String getEditedOcrText(int pageIndex) => _editedOcrTexts[pageIndex] ?? '';

  Future<void> initialize() async {
    _setLoading(true);
    await loadDocuments();
    await loadSettings();
    _setLoading(false);
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  // Document methods
  Future<void> loadDocuments() async {
    _documents = await _storageService.getDocuments();
    notifyListeners();
  }

  Future<bool> initializeCamera() async {
    _cameraInitialized = await _cameraService.initializeCamera();
    if (_cameraInitialized) {
      await _cameraService.setFlashMode(_mapFlashMode(_flashMode));
    }
    notifyListeners();
    return _cameraInitialized;
  }

  Future<File?> captureImage() async {
    final image = await _cameraService.captureImage();
    if (image == null) return null;
    if (!await _isUsableCaptureImage(image)) {
      debugPrint('Captured image rejected (invalid/black): ${image.path}');
      return null;
    }
    final accepted = await _addImageAndRunPipeline(image);
    if (!accepted) {
      debugPrint('Capture rejected after pipeline checks: ${image.path}');
      return null;
    }
    return image;
  }

  Future<File?> captureImageForBatch() async {
    final image = await _cameraService.captureImage();
    if (image == null) return null;
    if (!await _isUsableCaptureImage(image)) return null;
    _batchRawImages.add(image);
    notifyListeners();
    return image;
  }

  Future<bool> _addImageAndRunPipeline(File image) async {
    final originalPath = image.path;
    _capturedImages.add(image);
    _pipelineResults.add(null);
    notifyListeners();
    var captureAccepted = true;

    _activeAnalysisCount++;
    _analysisStageText = 'Analyzing document...';
    notifyListeners();

    debugPrint('Running pipeline for ${image.path}');

    try {
      final result = await _scanPipelineService.runInBackground(
        image,
        options: const ScanPipelineOptions(
          maxDimension: 1300,
          minConfidence: 0.40,
        ),
        onStage: (stage, message) {
          _analysisStageText = message;
          notifyListeners();
        },
      );
      final index = _capturedImages.indexWhere((f) => f.path == originalPath);
      final hasValidIndex =
          index != -1 &&
          index < _capturedImages.length &&
          index < _pipelineResults.length;
      if (!hasValidIndex) {
        return false;
      }

      if (result != null) {
        final selectedByCapture =
            result.enhancedVariants[_captureFilterMode] ??
            result.selectedOutputFile;
        final output = await _selectPreferredOutput(
          preferred: selectedByCapture,
          fallback: image,
        );
        if (output == null) {
          _dropCaptureAt(index);
          captureAccepted = false;
        } else {
          _pipelineResults[index] = result.copyWith(
            selectedFilter: _captureFilterMode,
          );
          _capturedImages[index] = output;
        }
      } else if (!await _isUsableCaptureImage(image)) {
        _dropCaptureAt(index);
        captureAccepted = false;
      }
    } catch (e) {
      debugPrint('Pipeline analysis failed for image ${image.path}: $e');
      final index = _capturedImages.indexWhere((f) => f.path == originalPath);
      final hasValidIndex =
          index != -1 &&
          index < _capturedImages.length &&
          index < _pipelineResults.length;
      if (hasValidIndex && !await _isUsableCaptureImage(image)) {
        _dropCaptureAt(index);
        captureAccepted = false;
      }
    } finally {
      _activeAnalysisCount = (_activeAnalysisCount - 1).clamp(0, 9999).toInt();
      if (_activeAnalysisCount == 0) {
        _analysisStageText = null;
      }
      notifyListeners();
    }
    return captureAccepted;
  }

  Future<void> addImageFromGallery() async {
    final image = await _imagePickerService.pickFromGallery();
    if (image != null) {
      if (!await image.exists()) return;
      if (await image.length() == 0) return;
      await _addImageAndRunPipeline(image);
    }
  }

  Future<void> addBatchImageFromGallery() async {
    final image = await _imagePickerService.pickFromGallery();
    if (image == null) return;
    if (!await image.exists()) return;
    if (await image.length() == 0) return;
    _batchRawImages.add(image);
    notifyListeners();
  }

  Future<void> addMultipleFromGallery() async {
    final images = await _imagePickerService.pickMultipleFromGallery();
    if (images.isNotEmpty) {
      for (final image in images) {
        if (!await image.exists()) continue;
        if (await image.length() == 0) continue;
        await _addImageAndRunPipeline(image);
      }
    }
  }

  void removeCapturedImage(int index) {
    if (index >= 0 && index < _capturedImages.length) {
      _capturedImages.removeAt(index);
      if (index < _pipelineResults.length) {
        _pipelineResults.removeAt(index);
      }
      if (index < _ocrResults.length) {
        _ocrResults.removeAt(index);
      }
      notifyListeners();
    }
  }

  void startBatchSession() {
    _batchActive = true;
    _batchRawImages.clear();
    notifyListeners();
  }

  void endBatchSession({bool clear = true}) {
    _batchActive = false;
    if (clear) {
      _batchRawImages.clear();
    }
    notifyListeners();
  }

  Future<ScannedDocument?> finalizeBatchSession({String name = 'Batch'}) async {
    if (_batchRawImages.isEmpty) return null;
    try {
      final results = <ScanPipelineResult?>[];
      final outputs = <File>[];
      for (final image in _batchRawImages) {
        final result = await _scanPipelineService.run(
          image,
          options: const ScanPipelineOptions(
            maxDimension: 1000,
            minConfidence: 0.40,
          ),
          onStage: (stage, message) {
            _analysisStageText = message;
            notifyListeners();
          },
        );
        if (result != null) {
          results.add(result.copyWith(selectedFilter: _captureFilterMode));
          final candidate =
              result.enhancedVariants[_captureFilterMode] ??
              result.selectedOutputFile;
          final selected = await _selectPreferredOutput(
            preferred: candidate,
            fallback: image,
          );
          outputs.add(selected ?? image);
        } else {
          outputs.add(image);
          results.add(null);
        }
      }

      final finalOutputs = <File>[];
      for (var i = 0; i < outputs.length; i++) {
        final candidate = outputs[i];
        if (await _isUsableCaptureImage(candidate)) {
          finalOutputs.add(candidate);
        } else if (i < _batchRawImages.length &&
            await _isUsableCaptureImage(_batchRawImages[i])) {
          finalOutputs.add(_batchRawImages[i]);
        }
      }
      if (finalOutputs.isEmpty) return null;

      final optimized = await _exportOptimizationService.compressBatch(
        finalOutputs,
        quality: ExportQualityPreset.medium,
      );
      final optimizedOutputs = optimized.isNotEmpty ? optimized : finalOutputs;

      // Double check that all files in optimizedOutputs actually exist and are not empty
      final finalVerifiedOutputs = <File>[];
      for (final f in optimizedOutputs) {
        if (await f.exists() && await f.length() > 0) {
          finalVerifiedOutputs.add(f);
        }
      }

      if (finalVerifiedOutputs.isEmpty) return null;

      _capturedImages = List<File>.from(finalVerifiedOutputs);
      _pipelineResults = List<ScanPipelineResult?>.from(results);
      _ocrResults.clear();
      _editedOcrTexts.clear();

      final safeName = _sanitizeFileName(name);
      final fileName = '${safeName}_${DateTime.now().millisecondsSinceEpoch}';
      final doc = await _pdfService.createPdfFromImages(
        finalVerifiedOutputs,
        fileName,
      );
      await _storageService.saveDocument(doc);
      _documents.insert(0, doc);

      _batchRawImages.clear();
      _batchActive = false;
      notifyListeners();
      return doc;
    } catch (e) {
      notifyListeners();
      return null;
    }
  }

  void clearCapturedImages() {
    _capturedImages.clear();
    _pipelineResults.clear();
    _ocrResults.clear();
    _editedOcrTexts.clear();
    _activeAnalysisCount = 0;
    _analysisStageText = null;
    _batchRawImages.clear();
    _batchActive = false;
    notifyListeners();
  }

  void setCaptureFilterMode(DocumentFilterMode mode) {
    _captureFilterMode = mode;
    notifyListeners();
  }

  void applyEditSessions(List<EditSessionState> sessions) {
    for (final session in sessions) {
      if (session.pageIndex < 0 ||
          session.pageIndex >= _capturedImages.length) {
        continue;
      }

      if (session.outputFile != null) {
        _capturedImages[session.pageIndex] = session.outputFile!;
      } else if (session.pageIndex < _pipelineResults.length &&
          _pipelineResults[session.pageIndex] != null) {
        final pipeline = _pipelineResults[session.pageIndex]!;
        _capturedImages[session.pageIndex] =
            pipeline.enhancedVariants[session.filterMode] ??
            pipeline.selectedOutputFile;
      }

      if (session.pageIndex < _pipelineResults.length &&
          _pipelineResults[session.pageIndex] != null) {
        final pipeline = _pipelineResults[session.pageIndex]!;
        final variants = Map<DocumentFilterMode, File>.from(
          pipeline.enhancedVariants,
        );
        if (session.outputFile != null) {
          variants[session.filterMode] = session.outputFile!;
        }
        _pipelineResults[session.pageIndex] = pipeline.copyWith(
          enhancedVariants: variants,
          selectedFilter: session.filterMode,
        );
      }
    }

    notifyListeners();
  }

  Future<void> processOcrForAllImages() async {
    if (_capturedImages.isEmpty) return;

    _isProcessingOcr = true;
    notifyListeners();

    // Initialize with placeholders to avoid index out of bounds during partial updates
    _ocrResults = List.generate(
      _capturedImages.length,
      (_) => OcrResult(success: false, text: '', confidence: 0),
    );
    _editedOcrTexts.clear();
    notifyListeners();

    for (var i = 0; i < _capturedImages.length; i++) {
      final variants = <File>[];
      final pipeline = i < _pipelineResults.length ? _pipelineResults[i] : null;

      if (pipeline != null) {
        variants.addAll(pipeline.enhancedVariants.values);
      }

      variants.add(_capturedImages[i]);

      final seen = <String>{};
      final deduped = <File>[];
      for (final file in variants) {
        if (seen.add(file.path)) {
          deduped.add(file);
        }
      }

      final result = await _ocrService.processImageWithVariants(deduped);
      if (i < _ocrResults.length) {
        _ocrResults[i] = result;
        notifyListeners(); // Notify after each page for better responsiveness
      }
    }

    _isProcessingOcr = false;
    notifyListeners();
  }

  String getAllOcrText() {
    final lines = <String>[];
    for (var i = 0; i < _ocrResults.length; i++) {
      final edited = _editedOcrTexts[i];
      final text =
          (edited != null && edited.trim().isNotEmpty)
              ? edited
              : _ocrResults[i].text;
      if (text.trim().isNotEmpty) {
        lines.add(text.trim());
      }
    }
    return lines.join('\n\n');
  }

  void updateOcrTextForPage(int pageIndex, String text) {
    if (pageIndex < 0) return;
    if (text.trim().isEmpty) {
      _editedOcrTexts.remove(pageIndex);
    } else {
      _editedOcrTexts[pageIndex] = text;
    }
    if (pageIndex < _ocrResults.length) {
      _ocrResults[pageIndex] = _ocrResults[pageIndex].copyWith(text: text);
    }
    notifyListeners();
  }

  Future<ScannedDocument?> saveDocument(String name) async {
    if (_capturedImages.isEmpty) return null;

    _setLoading(true);

    try {
      ScannedDocument document;
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = '${name}_$timestamp';
      final optimizedImages = await _exportOptimizationService.compressBatch(
        _capturedImages,
        quality: ExportQualityPreset.medium,
      );

      if (_defaultFormat == 'PDF' && optimizedImages.length > 1) {
        document = await _pdfService.createPdfFromImages(
          optimizedImages,
          fileName,
        );
      } else if (optimizedImages.length == 1) {
        document = await _pdfService.saveImageAsDocument(
          optimizedImages.first,
          fileName,
        );
      } else {
        document = await _pdfService.createPdfFromImages(
          optimizedImages,
          fileName,
        );
      }

      await _storageService.saveDocument(document);
      _documents.insert(0, document);
      _capturedImages.clear();
      _pipelineResults.clear();
      _ocrResults.clear();
      _editedOcrTexts.clear();
      _setLoading(false);
      notifyListeners();
      return document;
    } catch (e) {
      _setLoading(false);
      notifyListeners();
      return null;
    }
  }

  Future<ScannedDocument?> createPdfFromImagesTool(
    List<File> images, {
    String name = 'PDF',
  }) async {
    if (images.isEmpty) return null;
    _setLoading(true);
    try {
      final optimized = await _exportOptimizationService.compressBatch(
        images,
        quality: ExportQualityPreset.medium,
      );
      var validImages = await _filterValidImages(optimized);
      if (validImages.isEmpty) {
        validImages = await _filterValidImages(images);
      }
      if (validImages.isEmpty) {
        _setLoading(false);
        notifyListeners();
        return null;
      }

      final safeName = _sanitizeFileName(name);
      final fileName = '${safeName}_${DateTime.now().millisecondsSinceEpoch}';
      final doc = await _pdfService.createPdfFromImages(validImages, fileName);
      await _storageService.saveDocument(doc);
      _documents.insert(0, doc);
      _setLoading(false);
      notifyListeners();
      return doc;
    } catch (_) {
      _setLoading(false);
      notifyListeners();
      return null;
    }
  }

  Future<ScannedDocument?> importPdfFile(File pdfFile, {String? name}) async {
    if (!await pdfFile.exists()) return null;
    _setLoading(true);
    try {
      final docsPath = await _storageService.getDocumentsDirectory();
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final baseName =
          (name == null || name.trim().isEmpty) ? 'Imported_$stamp' : name;
      final targetPath = '$docsPath/$baseName.pdf';
      final copied = await pdfFile.copy(targetPath);
      final doc = ScannedDocument(
        id: stamp.toString(),
        name: '$baseName.pdf',
        filePath: copied.path,
        createdAt: DateTime.now(),
        pageCount: 1,
        fileSize: await copied.length(),
        isPdf: true,
      );
      await _storageService.saveDocument(doc);
      _documents.insert(0, doc);
      _setLoading(false);
      notifyListeners();
      return doc;
    } catch (_) {
      _setLoading(false);
      notifyListeners();
      return null;
    }
  }

  Future<ScannedDocument?> importAnyFile(
    File file, {
    String? name,
    int pageCount = 1,
  }) async {
    if (!await file.exists()) return null;
    _setLoading(true);
    try {
      final docsPath = await _storageService.getDocumentsDirectory();
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final ext = _safeExtension(file.path);
      final baseName =
          (name == null || name.trim().isEmpty) ? 'Imported_$stamp' : name;
      final targetPath = '$docsPath/$baseName$ext';
      final copied = await file.copy(targetPath);
      final isPdf = ext.toLowerCase() == '.pdf';
      final doc = ScannedDocument(
        id: stamp.toString(),
        name: '$baseName$ext',
        filePath: copied.path,
        createdAt: DateTime.now(),
        pageCount: pageCount,
        fileSize: await copied.length(),
        isPdf: isPdf,
      );
      await _storageService.saveDocument(doc);
      _documents.insert(0, doc);
      _setLoading(false);
      notifyListeners();
      return doc;
    } catch (_) {
      _setLoading(false);
      notifyListeners();
      return null;
    }
  }

  Future<void> deleteDocument(String id) async {
    await _storageService.deleteDocument(id);
    _documents.removeWhere((d) => d.id == id);
    notifyListeners();
  }

  void selectDocument(ScannedDocument? doc) {
    _selectedDocument = doc;
    notifyListeners();
  }

  // Settings methods
  Future<void> loadSettings() async {
    _autoCrop = await _settingsService.getAutoCrop();
    _flashMode = await _settingsService.getFlashMode();
    _defaultFormat = await _settingsService.getDefaultFormat();
    _cloudBackup = await _settingsService.getCloudBackup();
    notifyListeners();
  }

  Future<void> setAutoCrop(bool value) async {
    _autoCrop = value;
    await _settingsService.setAutoCrop(value);
    notifyListeners();
  }

  Future<void> setFlashMode(String value) async {
    _flashMode = value;
    await _settingsService.setFlashMode(value);
    await _cameraService.setFlashMode(_mapFlashMode(value));
    notifyListeners();
  }

  Future<void> setDefaultFormat(String value) async {
    _defaultFormat = value;
    await _settingsService.setDefaultFormat(value);
    notifyListeners();
  }

  Future<void> setCloudBackup(bool value) async {
    _cloudBackup = value;
    await _settingsService.setCloudBackup(value);
    notifyListeners();
  }

  Future<void> disposeCamera() async {
    _cameraInitialized = false;
    notifyListeners();
    await _cameraService.dispose();
    notifyListeners();
  }

  FlashMode _mapFlashMode(String value) {
    switch (value.trim().toLowerCase()) {
      case 'on':
        return FlashMode.always;
      case 'off':
        return FlashMode.off;
      default:
        return FlashMode.auto;
    }
  }

  @override
  void dispose() {
    _ocrService.dispose();
    super.dispose();
  }

  Future<SaveAndExportResult> saveAndExportCurrentScan() async {
    final imagesForGallery = List<File>.from(_capturedImages);
    final document = await saveDocument('Scan');
    if (document == null) {
      return const SaveAndExportResult(
        success: false,
        appSaved: false,
        gallerySavedCount: 0,
        totalGalleryImages: 0,
      );
    }

    final galleryResult = await _exportService.saveImagesToGallery(
      imagesForGallery,
    );
    return SaveAndExportResult(
      success: true,
      appSaved: true,
      document: document,
      gallerySavedCount: galleryResult.saved,
      totalGalleryImages: galleryResult.total,
      exportErrors: galleryResult.errors,
    );
  }

  String _safeExtension(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.pdf')) return '.pdf';
    if (lower.endsWith('.png')) return '.png';
    if (lower.endsWith('.jpeg')) return '.jpeg';
    if (lower.endsWith('.jpg')) return '.jpg';
    if (lower.endsWith('.webp')) return '.webp';
    return '.jpg';
  }

  Future<List<File>> _filterValidImages(List<File> sources) async {
    final valid = <File>[];
    for (final file in sources) {
      if (await _isValidImageFile(file)) {
        valid.add(file);
      }
    }
    return valid;
  }

  String _sanitizeFileName(String input) {
    final cleaned = input
        .trim()
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .replaceAll(RegExp(r'\s+'), '_');
    return cleaned.isEmpty ? 'PDF' : cleaned;
  }

  Future<bool> _isValidImageFile(File file) async {
    try {
      if (!await file.exists()) return false;
      if (await file.length() == 0) return false;
      final bytes = await file.readAsBytes();
      final decoded = img.decodeImage(bytes);
      return decoded != null;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _isUsableCaptureImage(File file) async {
    if (!await _isValidImageFile(file)) return false;
    return !await _isLikelyBlackFrame(file);
  }

  Future<bool> _isLikelyBlackFrame(File file) async {
    final luminance = await _sampleMeanLuminance(file);
    if (luminance == null) return true;
    return luminance < 8.0;
  }

  Future<double?> _sampleMeanLuminance(File file, {int samples = 120}) async {
    try {
      final bytes = await file.readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null || decoded.width == 0 || decoded.height == 0) {
        return null;
      }
      double sum = 0;
      for (int i = 0; i < samples; i++) {
        final p = decoded.getPixel(
          (i * 13) % decoded.width,
          (i * 17) % decoded.height,
        );
        sum += p.luminance;
      }
      return sum / samples;
    } catch (_) {
      return null;
    }
  }

  Future<File?> _selectPreferredOutput({
    required File preferred,
    required File fallback,
  }) async {
    if (await _isUsableCaptureImage(preferred)) {
      return preferred;
    }
    if (await _isUsableCaptureImage(fallback)) {
      return fallback;
    }
    return null;
  }

  void _dropCaptureAt(int index) {
    if (index < 0 || index >= _capturedImages.length) return;
    _capturedImages.removeAt(index);
    if (index < _pipelineResults.length) {
      _pipelineResults.removeAt(index);
    }
    if (index < _ocrResults.length) {
      _ocrResults.removeAt(index);
    }
  }
}

class SaveAndExportResult {
  final bool success;
  final bool appSaved;
  final ScannedDocument? document;
  final int gallerySavedCount;
  final int totalGalleryImages;
  final List<String> exportErrors;

  const SaveAndExportResult({
    required this.success,
    required this.appSaved,
    required this.gallerySavedCount,
    required this.totalGalleryImages,
    this.document,
    this.exportErrors = const [],
  });
}
