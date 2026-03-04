import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'theme/app_theme.dart';
import 'widgets/bottom_nav.dart';
import 'pages/splash_screen.dart';
import 'pages/home_page.dart';
import 'pages/scanner_page.dart';
import 'pages/scan_result_page.dart';
import 'pages/image_edit_page.dart';
import 'pages/doc_view_page.dart';
import 'pages/gallery_page.dart';
import 'pages/settings_page.dart';
import 'pages/compressor_page.dart';
import 'pages/ocr_tool_input_page.dart';
import 'pages/ocr_tool_result_page.dart';
import 'pages/pdf_edit_page.dart';
import 'pages/pdf_maker_page.dart';
import 'pages/pdf_result_page.dart';
import 'pages/share_history_page.dart';
import 'services/app_state.dart';
import 'services/export_service.dart';
import 'services/ocr_tool_service.dart';
import 'models/scanned_document.dart';
import 'models/scan_pipeline_models.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const DocScanApp());
}

class DocScanApp extends StatelessWidget {
  const DocScanApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppState()..initialize(),
      child: MaterialApp(
        title: 'DocScan',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: AppColors.accent),
          useMaterial3: true,
        ),
        home: const MainScreen(),
      ),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  final ExportService _exportService = ExportService();
  int _currentIndex = 0;
  String _homeSearchQuery = '';
  bool _showScanner = false;
  bool _showEdit = false;
  bool _showResult = false;
  bool _showSplash = true;

  void _onNavTap(int index) {
    if (index == 3) {
      _openOcrTool();
      return;
    }
    setState(() {
      _currentIndex = index;
      _showScanner = false;
      _showEdit = false;
      _showResult = false;
    });
  }

  void _onScanTap() async {
    setState(() {
      _showScanner = true;
      _showEdit = false;
      _showResult = false;
    });

    final appState = context.read<AppState>();
    await appState.initializeCamera();
  }

  void _onDocTap(ScannedDocument document) {
    final appState = context.read<AppState>();
    appState.selectDocument(document);
    setState(() {
      _currentIndex = 5;
    });
  }

  void _onSeeAllTap() {
    setState(() {
      _currentIndex = 1;
    });
  }

  Future<void> _onScannerCapture() async {
    final appState = context.read<AppState>();
    final beforeCount = appState.capturedImages.length;
    final captured = await appState.captureImage();
    if (captured == null) {
      _showScannerError('No clear document detected. Try again.');
      return;
    }
    final isValid = _validateLastCapturedDocument(beforeCount);
    if (isValid) {
      await _openEditFromScanner();
    }
  }

  Future<void> _onScannerAddFromGallery() async {
    final appState = context.read<AppState>();
    final beforeCount = appState.capturedImages.length;
    await appState.addImageFromGallery();
    final isValid = _validateLastCapturedDocument(
      beforeCount,
      errorMessage: 'Selected image is not a clear document. Try again.',
    );
    if (isValid) {
      await _openEditFromScanner();
    }
  }

  bool _validateLastCapturedDocument(
    int previousCount, {
    String errorMessage = 'No clear document detected. Try again.',
  }) {
    final appState = context.read<AppState>();
    if (appState.capturedImages.length <= previousCount) return false;

    final index = appState.capturedImages.length - 1;
    final pipeline = index < appState.pipelineResults.length
        ? appState.pipelineResults[index]
        : null;

    // Keep capture flow permissive: users can manually scan any page and fix in edit.
    if (pipeline == null) return true;

    // Keep capture permissive, but warn when auto perspective is weak.
    final weakPerspective =
        !pipeline.perspectiveApplied ||
        pipeline.perspectiveConfidence < 0.42 ||
        pipeline.usedFallback;
    if (weakPerspective) {
      _showScannerError('Auto corners were weak. You can adjust in Edit.');
    }
    return true;
  }

  Future<void> _openEditFromScanner() async {
    if (!mounted) return;
    final appState = context.read<AppState>();
    setState(() {
      _showScanner = false;
      _showEdit = true;
      _showResult = false;
    });
    await appState.disposeCamera();
  }

  void _showScannerError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _onScannerDone() async {
    final appState = context.read<AppState>();
    if (appState.isAnalyzing) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please wait for analysis to complete')),
        );
      }
      return;
    }

    if (appState.capturedImages.isNotEmpty) {
      setState(() {
        _showScanner = false;
        _showEdit = true;
        _showResult = false;
      });
      await appState.disposeCamera();
      return;
    }

    setState(() {
      _showScanner = false;
      _showEdit = false;
      _showResult = false;
    });
    await appState.disposeCamera();
  }

  void _onScannerCancel() async {
    final appState = context.read<AppState>();
    appState.clearCapturedImages();

    setState(() {
      _showScanner = false;
      _showEdit = false;
      _showResult = false;
    });

    await appState.disposeCamera();
  }

  void _onResultRetry() async {
    final appState = context.read<AppState>();
    appState.clearCapturedImages();

    setState(() {
      _showResult = false;
      _showEdit = false;
      _showScanner = true;
    });

    await appState.initializeCamera();
  }

  void _onResultSave() async {
    final appState = context.read<AppState>();
    final result = await appState.saveAndExportCurrentScan();

    if (!mounted) return;

    if (!result.success) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Failed to save document')));
      return;
    }

    setState(() {
      _showResult = false;
      _showEdit = false;
      _currentIndex = 0;
    });

    final galleryNote = result.totalGalleryImages == 0
        ? 'No images to export'
        : 'Gallery: ${result.gallerySavedCount}/${result.totalGalleryImages}';
    final errorNote = result.exportErrors.isEmpty
        ? ''
        : ' (${result.exportErrors.first})';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Saved to history. $galleryNote$errorNote'),
        backgroundColor: AppColors.green,
      ),
    );
  }

  void _onResultBack() {
    context.read<AppState>().clearCapturedImages();
    setState(() {
      _showResult = false;
      _showEdit = false;
      _showScanner = false;
      _currentIndex = 0;
    });
  }

  void _onResultAddMore() async {
    final appState = context.read<AppState>();
    await appState.addImageFromGallery();
  }

  void _onResultRemoveImage(int index) {
    final appState = context.read<AppState>();
    appState.removeCapturedImage(index);
  }

  void _onEditContinue(List<EditSessionState> sessions) {
    final appState = context.read<AppState>();
    appState.applyEditSessions(sessions);

    setState(() {
      _showEdit = false;
      _showResult = true;
    });

    // Kick off OCR immediately so Result tab is ready without manual retry.
    appState.processOcrForAllImages();
  }

  void _onEditBack() async {
    final appState = context.read<AppState>();
    setState(() {
      _showEdit = false;
      _showScanner = true;
    });
    await appState.initializeCamera();
  }

  void _onDocViewBack() {
    context.read<AppState>().selectDocument(null);
    setState(() {
      _currentIndex = 0;
    });
  }

  Future<void> _onGalleryDeleteDoc(ScannedDocument document) async {
    final appState = context.read<AppState>();
    try {
      await appState.deleteDocument(document.id);
      if (appState.selectedDocument?.id == document.id) {
        appState.selectDocument(null);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Document deleted')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to delete document')),
      );
    }
  }

  Future<void> _onDocSave() async {
    final appState = context.read<AppState>();
    final doc = appState.selectedDocument;
    if (doc == null) return;
    final file = File(doc.filePath);
    if (!await file.exists()) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Document file missing')));
      return;
    }

    if (doc.isPdf) {
      final base = doc.name.replaceAll('.pdf', '').replaceAll('.PDF', '');
      final saved = await appState.importAnyFile(
        file,
        name: '${base}_saved',
        pageCount: doc.pageCount,
      );
      if (saved != null) {
        appState.selectDocument(saved);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            saved != null ? 'PDF saved successfully' : 'Failed to save PDF',
          ),
        ),
      );
      return;
    }

    final result = await _exportService.saveImagesToGallery([file]);
    if (!mounted) return;
    final ok = result.saved > 0;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? 'Image saved to gallery' : 'Failed to save image'),
      ),
    );
  }

  Future<void> _onDocShare() async {
    final doc = context.read<AppState>().selectedDocument;
    if (doc == null) return;
    final file = File(doc.filePath);
    if (!await file.exists()) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Document file missing')));
      return;
    }
    await Share.shareXFiles([XFile(file.path)], text: 'Shared from DocScan');
  }

  Future<void> _onDocOcr() async {
    final doc = context.read<AppState>().selectedDocument;
    if (doc == null) return;
    final file = File(doc.filePath);
    if (!await file.exists()) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Document file missing')));
      return;
    }
    final tool = OcrToolService();
    try {
      final result = doc.isPdf
          ? await tool.processPdf(file)
          : await tool.processImage(file);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => OcrToolResultPage(result: result)),
      );
      if (!mounted) return;
      setState(() => _currentIndex = 0);
    } finally {
      tool.dispose();
    }
  }

  Future<void> _onDocEdit() async {
    final appState = context.read<AppState>();
    final navigator = Navigator.of(context);
    final doc = appState.selectedDocument;
    if (doc == null) return;

    if (doc.isPdf) {
      final updated = await navigator.push<ScannedDocument>(
        MaterialPageRoute(builder: (_) => PdfEditPage(sourceDocument: doc)),
      );
      if (updated != null) {
        appState.selectDocument(updated);
      }
      return;
    }

    final image = File(doc.filePath);
    if (!await image.exists()) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Image file missing')));
      return;
    }

    final updated = await navigator.push<ScannedDocument>(
      MaterialPageRoute(
        builder: (pageContext) => ImageEditPage(
          images: [image],
          pipelineResults: <ScanPipelineResult?>[null],
          onBack: () => Navigator.of(pageContext).pop(),
          onContinue: (sessions) async {
            final output = sessions.isEmpty ? null : sessions.first.outputFile;
            if (output == null) {
              Navigator.of(pageContext).pop();
              return;
            }
            final saved = await appState.importAnyFile(
              output,
              name:
                  '${doc.name.replaceAll('.jpg', '').replaceAll('.jpeg', '')}_edited',
              pageCount: 1,
            );
            if (!pageContext.mounted) return;
            Navigator.of(pageContext).pop(saved);
          },
        ),
      ),
    );
    if (updated != null) {
      appState.selectDocument(updated);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Image edited successfully')),
      );
    }
  }

  Future<void> _openPdfMaker() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const PdfMakerPage()));
    if (!mounted) return;
    setState(() => _currentIndex = 0);
  }

  Future<void> _openOcrTool() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const OcrToolInputPage()));
    if (!mounted) return;
    setState(() => _currentIndex = 0);
  }

  Future<void> _openShareTool() async {
    final docs = context.read<AppState>().documents;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ShareHistoryPage(documents: docs)),
    );
  }

  Future<void> _openCompressorTool() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const CompressorPage()));
    if (!mounted) return;
    setState(() => _currentIndex = 0);
  }

  void _onHomeSearchChanged(String value) {
    setState(() => _homeSearchQuery = value);
  }

  List<ScannedDocument> _filteredHomeDocuments(AppState appState) {
    final query = _homeSearchQuery.trim().toLowerCase();
    if (query.isEmpty) return appState.documents;
    return appState.documents
        .where((doc) => doc.name.toLowerCase().contains(query))
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, appState, child) {
        if (appState.isLoading || _showSplash) {
          return SplashScreen(
            onComplete: () {
              if (mounted) {
                setState(() {
                  _showSplash = false;
                });
              }
            },
          );
        }

        return Scaffold(
          backgroundColor: AppColors.bg,
          body: SafeArea(
            child: Column(
              children: [
                Expanded(child: _buildCurrentPage(appState)),
                if (!_showScanner && !_showResult && !_showEdit)
                  BottomNavWidget(
                    currentIndex: _currentIndex > 4 ? 0 : _currentIndex,
                    onTap: _onNavTap,
                    onScanTap: _onScanTap,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCurrentPage(AppState appState) {
    // Scanner Page
    if (_showScanner) {
      return ScannerPage(
        cameraController: appState.cameraService.controller,
        isCameraInitialized: appState.cameraInitialized,
        isAnalyzing: appState.isAnalyzing,
        analysisStageText: appState.analysisStageText,
        capturedImages: appState.capturedImages,
        onCancel: _onScannerCancel,
        onDone: _onScannerDone,
        onCapture: _onScannerCapture,
        onAddFromGallery: _onScannerAddFromGallery,
      );
    }

    // Edit Page
    if (_showEdit) {
      return ImageEditPage(
        images: appState.capturedImages,
        pipelineResults: appState.pipelineResults,
        onBack: _onEditBack,
        onContinue: _onEditContinue,
      );
    }

    // Result Page
    if (_showResult) {
      return ScanResultPage(
        scannedImages: appState.capturedImages,
        ocrResults: appState.ocrResults,
        isProcessingOcr: appState.isProcessingOcr,
        onRetry: _onResultRetry,
        onSave: _onResultSave,
        onBack: _onResultBack,
        onRemoveImage: _onResultRemoveImage,
        onAddMore: _onResultAddMore,
        onProcessOcr: () => appState.processOcrForAllImages(),
        onTextChanged: (pageIndex, text) =>
            appState.updateOcrTextForPage(pageIndex, text),
      );
    }

    // Regular pages
    switch (_currentIndex) {
      case 0:
        return HomePage(
          documents: _filteredHomeDocuments(appState),
          onScanTap: _onScanTap,
          onDocTap: _onDocTap,
          onSeeAllTap: _onSeeAllTap,
          searchQuery: _homeSearchQuery,
          onSearchChanged: _onHomeSearchChanged,
          onPdfToolTap: _openPdfMaker,
          onOcrToolTap: _openOcrTool,
          onShareToolTap: _openShareTool,
          onCompressToolTap: _openCompressorTool,
        );
      case 1:
        return GalleryPage(
          documents: appState.documents,
          onDocTap: (index) {
            if (index < 0 || index >= appState.documents.length) return;
            _onDocTap(appState.documents[index]);
          },
          onDocDelete: (doc) {
            _onGalleryDeleteDoc(doc);
          },
        );
      case 2:
        final selected = appState.selectedDocument;
        if (selected != null && selected.isPdf) {
          return PdfResultPage(
            document: selected,
            onBack: _onDocViewBack,
            onDocumentChanged: (updated) => appState.selectDocument(updated),
          );
        }
        return DocViewPage(
          document: selected,
          onBack: _onDocViewBack,
          onMoreTap: () {},
          onSave: _onDocSave,
          onShare: _onDocShare,
          onOcr: _onDocOcr,
          onEdit: _onDocEdit,
          onDelete: () async {
            if (appState.selectedDocument != null) {
              await appState.deleteDocument(appState.selectedDocument!.id);
              _onDocViewBack();
            }
          },
        );
      case 3:
        return HomePage(
          documents: _filteredHomeDocuments(appState),
          onScanTap: _onScanTap,
          onDocTap: _onDocTap,
          onSeeAllTap: _onSeeAllTap,
          searchQuery: _homeSearchQuery,
          onSearchChanged: _onHomeSearchChanged,
          onPdfToolTap: _openPdfMaker,
          onOcrToolTap: _openOcrTool,
          onShareToolTap: _openShareTool,
          onCompressToolTap: _openCompressorTool,
        );
      case 4:
        return SettingsPage(
          autoCrop: appState.autoCrop,
          flashMode: appState.flashMode,
          onAutoCropChanged: (value) => appState.setAutoCrop(value),
          onFlashModeChanged: (value) => appState.setFlashMode(value),
        );
      case 5:
        final selected = appState.selectedDocument;
        if (selected != null && selected.isPdf) {
          return PdfResultPage(
            document: selected,
            onBack: _onDocViewBack,
            onDocumentChanged: (updated) => appState.selectDocument(updated),
          );
        }
        return DocViewPage(
          document: selected,
          onBack: _onDocViewBack,
          onMoreTap: () {},
          onSave: _onDocSave,
          onShare: _onDocShare,
          onOcr: _onDocOcr,
          onEdit: _onDocEdit,
          onDelete: () async {
            if (appState.selectedDocument != null) {
              await appState.deleteDocument(appState.selectedDocument!.id);
              _onDocViewBack();
            }
          },
        );
      default:
        return HomePage(
          documents: _filteredHomeDocuments(appState),
          onScanTap: _onScanTap,
          onDocTap: _onDocTap,
          onSeeAllTap: _onSeeAllTap,
          searchQuery: _homeSearchQuery,
          onSearchChanged: _onHomeSearchChanged,
          onPdfToolTap: _openPdfMaker,
          onOcrToolTap: _openOcrTool,
          onShareToolTap: _openShareTool,
          onCompressToolTap: _openCompressorTool,
        );
    }
  }
}
