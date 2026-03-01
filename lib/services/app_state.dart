import 'dart:io';
import 'package:flutter/material.dart';
import '../models/scanned_document.dart';
import '../services/storage_service.dart';
import '../services/camera_service.dart';
import '../services/image_picker_service.dart';
import '../services/pdf_service.dart';
import '../services/settings_service.dart';
import '../services/ocr_service.dart';
import '../services/document_scanner_service.dart';

class AppState extends ChangeNotifier {
  final StorageService _storageService = StorageService();
  final CameraService _cameraService = CameraService();
  final ImagePickerService _imagePickerService = ImagePickerService();
  final PdfService _pdfService = PdfService();
  final SettingsService _settingsService = SettingsService();
  final OcrService _ocrService = OcrService();
  final DocumentScannerService _documentScannerService =
      DocumentScannerService();

  List<ScannedDocument> _documents = [];
  List<File> _capturedImages = [];
  List<OcrResult> _ocrResults = [];
  ScannedDocument? _selectedDocument;
  bool _isLoading = false;
  bool _isProcessingOcr = false;
  bool _cameraInitialized = false;

  // Settings
  bool _autoCrop = true;
  String _flashMode = 'Auto';
  String _defaultFormat = 'PDF';
  bool _cloudBackup = false;

  // Getters
  List<ScannedDocument> get documents => _documents;
  List<File> get capturedImages => _capturedImages;
  List<OcrResult> get ocrResults => _ocrResults;
  ScannedDocument? get selectedDocument => _selectedDocument;
  bool get isLoading => _isLoading;
  bool get isProcessingOcr => _isProcessingOcr;
  bool get cameraInitialized => _cameraInitialized;
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
    debugPrint('AppState: captureImage called');
    final image = await _cameraService.captureImage();
    debugPrint('AppState: image captured, processing...');
    if (image != null) {
      // Apply all scanner enhancements
      final processedImage = await _documentScannerService.processDocument(
        image,
        autoEnhance: true,
      );
      if (processedImage != null) {
        _capturedImages.add(processedImage);
        debugPrint('AppState: processed image added to capturedImages');
      } else {
        _capturedImages.add(image);
      }
      notifyListeners();
    }
    return image;
  }

  Future<void> addImageFromGallery() async {
    final image = await _imagePickerService.pickFromGallery();
    if (image != null) {
      // Apply the same high-quality enhancement for gallery photos
      final processedImage = await _documentScannerService.processDocument(
        image,
        autoEnhance: true,
      );
      if (processedImage != null) {
        _capturedImages.add(processedImage);
      } else {
        _capturedImages.add(image);
      }
      notifyListeners();
    }
  }

  Future<void> addMultipleFromGallery() async {
    final images = await _imagePickerService.pickMultipleFromGallery();
    if (images.isNotEmpty) {
      _capturedImages.addAll(images);
      notifyListeners();
    }
  }

  void removeCapturedImage(int index) {
    if (index >= 0 && index < _capturedImages.length) {
      _capturedImages.removeAt(index);
      if (index < _ocrResults.length) {
        _ocrResults.removeAt(index);
      }
      notifyListeners();
    }
  }

  void clearCapturedImages() {
    _capturedImages.clear();
    _ocrResults.clear();
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

      if (_defaultFormat == 'PDF' && _capturedImages.length > 1) {
        document = await _pdfService.createPdfFromImages(
          _capturedImages,
          fileName,
        );
      } else if (_capturedImages.length == 1) {
        document = await _pdfService.saveImageAsDocument(
          _capturedImages.first,
          fileName,
        );
      } else {
        document = await _pdfService.createPdfFromImages(
          _capturedImages,
          fileName,
        );
      }

      await _storageService.saveDocument(document);
      _documents.insert(0, document);
      _capturedImages.clear();
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
