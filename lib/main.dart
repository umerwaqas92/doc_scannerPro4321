import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'theme/app_theme.dart';
import 'widgets/status_bar.dart';
import 'widgets/bottom_nav.dart';
import 'pages/splash_screen.dart';
import 'pages/home_page.dart';
import 'pages/scanner_page.dart';
import 'pages/scan_result_page.dart';
import 'pages/image_edit_page.dart';
import 'pages/doc_view_page.dart';
import 'pages/gallery_page.dart';
import 'pages/settings_page.dart';
import 'services/app_state.dart';
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
  int _currentIndex = 0;
  bool _showScanner = false;
  bool _showEdit = false;
  bool _showResult = false;
  bool _showSplash = true;

  void _onNavTap(int index) {
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

  void _onDocTap(int docIndex) {
    final appState = context.read<AppState>();
    if (docIndex < appState.documents.length) {
      appState.selectDocument(appState.documents[docIndex]);
      setState(() {
        _currentIndex = 5;
      });
    }
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

    // Only show a soft warning for extremely weak detections; do not block.
    final extremelyWeak =
        pipeline.detectionConfidence < 0.05 && pipeline.usedFallback;
    if (extremelyWeak) {
      _showScannerError('Image may be unclear. You can adjust it in Edit.');
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
    await appState.saveDocument('Scan');

    setState(() {
      _showResult = false;
      _showEdit = false;
      _currentIndex = 0;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Document saved successfully!'),
          backgroundColor: AppColors.green,
        ),
      );
    }
  }

  void _onResultBack() {
    setState(() {
      _showResult = false;
      _showEdit = true;
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
                if (!_showScanner && !_showResult && !_showEdit)
                  const StatusBarWidget(),
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
        onTextChanged: (text) {},
      );
    }

    // Regular pages
    switch (_currentIndex) {
      case 0:
        return HomePage(
          documents: appState.documents,
          onScanTap: _onScanTap,
          onDocTap: (index) => _onDocTap(index),
          onSeeAllTap: _onSeeAllTap,
          onSearchTap: () {},
          onProfileTap: () {},
        );
      case 1:
        return GalleryPage(
          documents: appState.documents,
          onDocTap: (index) => _onDocTap(index),
          onMenuTap: () {},
        );
      case 2:
        return DocViewPage(
          document: appState.selectedDocument,
          onBack: _onDocViewBack,
          onMoreTap: () {},
          onSave: () {},
          onShare: () {},
          onOcr: () {},
          onEdit: () {},
          onDelete: () async {
            if (appState.selectedDocument != null) {
              await appState.deleteDocument(appState.selectedDocument!.id);
              _onDocViewBack();
            }
          },
        );
      case 3:
        return HomePage(
          documents: appState.documents,
          onScanTap: _onScanTap,
          onDocTap: (index) => _onDocTap(index),
          onSeeAllTap: _onSeeAllTap,
          onSearchTap: () {},
          onProfileTap: () {},
        );
      case 4:
        return SettingsPage(
          autoCrop: appState.autoCrop,
          flashMode: appState.flashMode,
          defaultFormat: appState.defaultFormat,
          cloudBackup: appState.cloudBackup,
          onAutoCropChanged: (value) => appState.setAutoCrop(value),
          onFlashModeChanged: (value) => appState.setFlashMode(value),
          onDefaultFormatChanged: (value) => appState.setDefaultFormat(value),
          onCloudBackupChanged: (value) => appState.setCloudBackup(value),
        );
      case 5:
        return DocViewPage(
          document: appState.selectedDocument,
          onBack: _onDocViewBack,
          onMoreTap: () {},
          onSave: () {},
          onShare: () {},
          onOcr: () {},
          onEdit: () {},
          onDelete: () async {
            if (appState.selectedDocument != null) {
              await appState.deleteDocument(appState.selectedDocument!.id);
              _onDocViewBack();
            }
          },
        );
      default:
        return HomePage(
          documents: appState.documents,
          onScanTap: _onScanTap,
          onDocTap: (index) => _onDocTap(index),
          onSeeAllTap: _onSeeAllTap,
          onSearchTap: () {},
          onProfileTap: () {},
        );
    }
  }
}
