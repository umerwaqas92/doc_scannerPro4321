import 'dart:io';
import 'package:flutter/material.dart';
import '../models/scanned_document.dart';
import '../models/scan_pipeline_models.dart';
import '../services/storage_service.dart';
import '../services/camera_service.dart';
import '../services/image_picker_service.dart';
import '../services/pdf_service.dart';
import '../services/settings_service.dart';
import '../services/ocr_service.dart';
import '../services/scan_pipeline_service.dart';
import '../services/export_optimization_service.dart';

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

  List<ScannedDocument> _documents = [];
  List<File> _capturedImages = [];
  List<ScanPipelineResult?> _pipelineResults = [];
  List<OcrResult> _ocrResults = [];
  ScannedDocument? _selectedDocument;
  bool _isLoading = false;
  bool _isProcessingOcr = false;
  bool _cameraInitialized = false;
  int _activeAnalysisCount = 0;

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
  ScannedDocument? get selectedDocument => _selectedDocument;
  bool get isLoading => _isLoading;
  bool get isProcessingOcr => _isProcessingOcr;
  bool get cameraInitialized => _cameraInitialized;
  bool get isAnalyzing => _activeAnalysisCount > 0;
  CameraService get cameraService => _cameraService;

  bool get autoCrop => _autoCrop;
  String get flashMode => _flashMode;
  String get defaultFormat => _defaultFormat;
  bool get cloudBackup => _cloudBackup;

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
    notifyListeners();
    return _cameraInitialized;
  }

  Future<File?> captureImage() async {
    final image = await _cameraService.captureImage();
    if (image == null) return null;
    await _addImageAndRunPipeline(image);
    return image;
  }

  Future<void> _addImageAndRunPipeline(File image) async {
    final originalPath = image.path;
    _capturedImages.add(image);
    _pipelineResults.add(null);
    notifyListeners();

    _activeAnalysisCount++;
    notifyListeners();

    try {
      final result = await _scanPipelineService.run(image);
      final index = _capturedImages.indexWhere((f) => f.path == originalPath);
      if (result != null &&
          index != -1 &&
          index < _capturedImages.length &&
          index < _pipelineResults.length) {
        _pipelineResults[index] = result;
        _capturedImages[index] = result.selectedOutputFile;
      }
    } catch (e) {
      debugPrint('Pipeline analysis failed for image ${image.path}: $e');
    } finally {
      _activeAnalysisCount = (_activeAnalysisCount - 1).clamp(0, 9999).toInt();
      notifyListeners();
    }
  }

  Future<void> addImageFromGallery() async {
    final image = await _imagePickerService.pickFromGallery();
    if (image != null) {
      await _addImageAndRunPipeline(image);
    }
  }

  Future<void> addMultipleFromGallery() async {
    final images = await _imagePickerService.pickMultipleFromGallery();
    if (images.isNotEmpty) {
      for (final image in images) {
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

  void clearCapturedImages() {
    _capturedImages.clear();
    _pipelineResults.clear();
    _ocrResults.clear();
    _activeAnalysisCount = 0;
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

    _ocrResults.clear();

    for (var image in _capturedImages) {
      final result = await _ocrService.processImage(image);
      _ocrResults.add(result);
    }

    _isProcessingOcr = false;
    notifyListeners();
  }

  String getAllOcrText() {
    return _ocrResults.map((r) => r.text).join('\n\n');
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
      _setLoading(false);
      notifyListeners();
      return document;
    } catch (e) {
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
    await _cameraService.dispose();
    _cameraInitialized = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _ocrService.dispose();
    super.dispose();
  }
}
