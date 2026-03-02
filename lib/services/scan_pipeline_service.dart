import 'dart:io';
import 'package:image/image.dart' as img;
import '../models/scan_pipeline_models.dart';
import 'document_scanner_service.dart';
import 'open_cv_document_analyzer.dart';

class ScanPipelineService {
  final DocumentScannerService _scannerService;
  final OpenCvDocumentAnalyzer _analyzer;

  ScanPipelineService({
    DocumentScannerService? scannerService,
    OpenCvDocumentAnalyzer? analyzer,
  }) : _scannerService = scannerService ?? DocumentScannerService(),
       _analyzer = analyzer ?? OpenCvDocumentAnalyzer();

  Future<ScanPipelineResult?> run(
    File input, {
    ScanPipelineOptions options = const ScanPipelineOptions(),
    void Function(ScanStage stage, String message)? onStage,
  }) async {
    final stageStatus = <ScanStage, StageState>{};
    stageStatus[ScanStage.capture] = const StageState(
      completed: true,
      message: 'Image captured',
    );
    onStage?.call(ScanStage.capture, 'Image captured');

    File normalizedInput = input;
    File preprocessed = input;
    File perspective = input;
    File cropped = input;
    DetectedDocument? detected;

    try {
      stageStatus[ScanStage.preprocess] = const StageState(
        completed: false,
        message: 'Normalizing orientation',
      );
      onStage?.call(ScanStage.preprocess, 'Normalizing orientation');
      normalizedInput = await _normalizeOrientation(input);

      stageStatus[ScanStage.preprocess] = const StageState(
        completed: false,
        message: 'Pre-processing image',
      );
      onStage?.call(ScanStage.preprocess, 'Pre-processing image');
      preprocessed =
          await _scannerService.preprocessForDetection(
            normalizedInput,
            maxHeight: options.maxDimension,
          ) ??
          normalizedInput;
      stageStatus[ScanStage.preprocess] = const StageState(
        completed: true,
        message: 'Pre-processing complete',
      );
      onStage?.call(ScanStage.preprocess, 'Pre-processing complete');

      stageStatus[ScanStage.detectEdges] = const StageState(
        completed: false,
        message: 'Detecting document edges',
      );
      onStage?.call(ScanStage.detectEdges, 'Detecting document edges');
      detected = await _analyzer.detectDocument(
        normalizedInput,
        minConfidence: options.minConfidence,
      );
      stageStatus[ScanStage.detectEdges] = StageState(
        completed: true,
        message: detected.isFallback
            ? 'Detection fallback used'
            : 'Edges detected',
      );
      onStage?.call(
        ScanStage.detectEdges,
        detected.isFallback ? 'Detection fallback used' : 'Edges detected',
      );

      stageStatus[ScanStage.perspectiveCorrection] = const StageState(
        completed: false,
        message: 'Applying perspective correction',
      );
      onStage?.call(
        ScanStage.perspectiveCorrection,
        'Applying perspective correction',
      );
      final points = detected.corners
          .map((c) => ScanPoint(c.x, c.y))
          .toList(growable: false);
      perspective =
          await _scannerService.applyPerspectiveFromCorners(
            normalizedInput,
            points,
            suffix: 'warped',
          ) ??
          normalizedInput;
      stageStatus[ScanStage.perspectiveCorrection] = const StageState(
        completed: true,
        message: 'Perspective corrected',
      );
      onStage?.call(ScanStage.perspectiveCorrection, 'Perspective corrected');

      stageStatus[ScanStage.crop] = const StageState(
        completed: false,
        message: 'Auto-cropping document',
      );
      onStage?.call(ScanStage.crop, 'Auto-cropping document');
      cropped = await _autoCropDocument(perspective);
      stageStatus[ScanStage.crop] = const StageState(
        completed: true,
        message: 'Auto-crop complete',
      );
      onStage?.call(ScanStage.crop, 'Auto-crop complete');

      stageStatus[ScanStage.enhance] = const StageState(
        completed: false,
        message: 'Generating enhancement variants',
      );
      onStage?.call(ScanStage.enhance, 'Generating enhancement variants');
      final variants = await _buildEnhancementVariants(cropped);
      stageStatus[ScanStage.enhance] = const StageState(
        completed: true,
        message: 'Enhancement complete',
      );
      onStage?.call(ScanStage.enhance, 'Enhancement complete');

      return ScanPipelineResult(
        originalFile: normalizedInput,
        preprocessedFile: preprocessed,
        perspectiveFile: perspective,
        croppedFile: cropped,
        enhancedVariants: variants,
        corners: detected.corners,
        detectionConfidence: detected.confidence,
        usedFallback: detected.isFallback,
        stageStatus: stageStatus,
      );
    } catch (_) {
      return null;
    }
  }

  Future<File> _normalizeOrientation(File source) async {
    try {
      final bytes = await source.readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return source;

      final oriented = img.bakeOrientation(decoded);
      final output = File(_buildDerivedPath(source.path, 'oriented'));
      await output.writeAsBytes(img.encodeJpg(oriented, quality: 96));
      return output;
    } catch (_) {
      return source;
    }
  }

  Future<File> _autoCropDocument(File file) async {
    final bytes = await file.readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return file;

    final gray = img.grayscale(decoded);
    final width = gray.width;
    final height = gray.height;
    final minPixels = (height * 0.08).round().clamp(1, height);

    int left = 0;
    int right = width - 1;
    int top = 0;
    int bottom = height - 1;

    bool hasInkInColumn(int x) {
      int count = 0;
      for (int y = 0; y < height; y++) {
        if (gray.getPixel(x, y).r < 242) count++;
      }
      return count >= minPixels;
    }

    bool hasInkInRow(int y) {
      int count = 0;
      for (int x = 0; x < width; x++) {
        if (gray.getPixel(x, y).r < 242) count++;
      }
      return count >= (width * 0.08).round().clamp(1, width);
    }

    while (left < right && !hasInkInColumn(left)) {
      left++;
    }
    while (right > left && !hasInkInColumn(right)) {
      right--;
    }
    while (top < bottom && !hasInkInRow(top)) {
      top++;
    }
    while (bottom > top && !hasInkInRow(bottom)) {
      bottom--;
    }

    // Keep a small safety margin so auto-crop does not clip text near edges.
    left = (left - (width * 0.015).round()).clamp(0, width - 1);
    right = (right + (width * 0.015).round()).clamp(0, width - 1);
    top = (top - (height * 0.015).round()).clamp(0, height - 1);
    bottom = (bottom + (height * 0.015).round()).clamp(0, height - 1);

    final cropWidth = right - left + 1;
    final cropHeight = bottom - top + 1;
    final enoughArea = cropWidth > width * 0.6 && cropHeight > height * 0.6;

    final result = enoughArea
        ? img.copyCrop(
            decoded,
            x: left,
            y: top,
            width: cropWidth,
            height: cropHeight,
          )
        : decoded;

    final output = File(_buildDerivedPath(file.path, 'cropped'));
    await output.writeAsBytes(img.encodeJpg(result, quality: 95));
    return output;
  }

  Future<Map<DocumentFilterMode, File>> _buildEnhancementVariants(
    File source,
  ) async {
    final bytes = await source.readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      return {DocumentFilterMode.original: source};
    }

    final variants = <DocumentFilterMode, File>{};
    variants[DocumentFilterMode.original] = source;

    final grayscale = img.grayscale(decoded);
    final grayscaleFile = File(_buildDerivedPath(source.path, 'grayscale'));
    await grayscaleFile.writeAsBytes(img.encodeJpg(grayscale, quality: 95));
    variants[DocumentFilterMode.grayscale] = grayscaleFile;

    final bw = _toStrongBlackWhite(grayscale);
    final bwFile = File(_buildDerivedPath(source.path, 'bw'));
    await bwFile.writeAsBytes(img.encodeJpg(bw, quality: 95));
    variants[DocumentFilterMode.blackWhite] = bwFile;

    final colorEnhanced = _enhanceColorDocument(decoded);
    final colorFile = File(_buildDerivedPath(source.path, 'color_plus'));
    await colorFile.writeAsBytes(img.encodeJpg(colorEnhanced, quality: 95));
    variants[DocumentFilterMode.colorEnhanced] = colorFile;

    final textPlus = _highContrastText(decoded);
    final textPlusFile = File(_buildDerivedPath(source.path, 'text_plus'));
    await textPlusFile.writeAsBytes(img.encodeJpg(textPlus, quality: 95));
    variants[DocumentFilterMode.highContrastText] = textPlusFile;

    final warm = _warmPaper(decoded);
    final warmFile = File(_buildDerivedPath(source.path, 'warm_paper'));
    await warmFile.writeAsBytes(img.encodeJpg(warm, quality: 95));
    variants[DocumentFilterMode.warmPaper] = warmFile;

    final photo = _photoNatural(decoded);
    final photoFile = File(_buildDerivedPath(source.path, 'photo_natural'));
    await photoFile.writeAsBytes(img.encodeJpg(photo, quality: 95));
    variants[DocumentFilterMode.photoNatural] = photoFile;

    return variants;
  }

  img.Image _toStrongBlackWhite(img.Image grayscale) {
    final output = img.Image(width: grayscale.width, height: grayscale.height);

    double sum = 0;
    for (int y = 0; y < grayscale.height; y++) {
      for (int x = 0; x < grayscale.width; x++) {
        sum += grayscale.getPixel(x, y).r;
      }
    }
    final mean = sum / (grayscale.width * grayscale.height);
    final threshold = (mean * 0.95).clamp(70.0, 190.0);

    for (int y = 0; y < grayscale.height; y++) {
      for (int x = 0; x < grayscale.width; x++) {
        final luma = grayscale.getPixel(x, y).r.toDouble();
        final value = luma > threshold ? 255 : 0;
        output.setPixel(x, y, img.ColorRgb8(value, value, value));
      }
    }
    return output;
  }

  img.Image _enhanceColorDocument(img.Image source) {
    var enhanced = img.adjustColor(
      source,
      contrast: 1.18,
      brightness: 1.06,
      saturation: 1.04,
    );

    final shadowMap = img.gaussianBlur(img.grayscale(enhanced), radius: 10);
    final output = img.Image(width: enhanced.width, height: enhanced.height);
    for (int y = 0; y < enhanced.height; y++) {
      for (int x = 0; x < enhanced.width; x++) {
        final p = enhanced.getPixel(x, y);
        final shadow = shadowMap.getPixel(x, y).r.toDouble();
        final lift = ((128.0 - shadow) * 0.35);
        final r = (p.r + lift).clamp(0.0, 255.0).toInt();
        final g = (p.g + lift).clamp(0.0, 255.0).toInt();
        final b = (p.b + lift).clamp(0.0, 255.0).toInt();
        output.setPixel(x, y, img.ColorRgb8(r, g, b));
      }
    }
    enhanced = img.gaussianBlur(output, radius: 1);
    return img.adjustColor(enhanced, contrast: 1.08);
  }

  img.Image _highContrastText(img.Image source) {
    final gray = img.grayscale(source);
    final bw = _toStrongBlackWhite(gray);
    return img.adjustColor(bw, contrast: 1.55, brightness: 1.07);
  }

  img.Image _warmPaper(img.Image source) {
    final sepia = img.sepia(source, amount: 0.2);
    return img.adjustColor(sepia, contrast: 1.08, brightness: 1.03);
  }

  img.Image _photoNatural(img.Image source) {
    return img.adjustColor(
      source,
      contrast: 1.08,
      saturation: 1.04,
      brightness: 1.02,
    );
  }

  String _buildDerivedPath(String originalPath, String suffix) {
    final dot = originalPath.lastIndexOf('.');
    if (dot == -1) return '${originalPath}_$suffix.jpg';
    return '${originalPath.substring(0, dot)}_$suffix${originalPath.substring(dot)}';
  }
}
