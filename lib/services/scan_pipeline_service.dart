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
  }) async {
    final stageStatus = <ScanStage, StageState>{};
    stageStatus[ScanStage.capture] = const StageState(
      completed: true,
      message: 'Image captured',
    );

    File preprocessed = input;
    File perspective = input;
    File cropped = input;
    DetectedDocument? detected;

    try {
      stageStatus[ScanStage.preprocess] = const StageState(
        completed: false,
        message: 'Pre-processing image',
      );
      preprocessed =
          await _scannerService.preprocessForDetection(
            input,
            maxHeight: options.maxDimension,
          ) ??
          input;
      stageStatus[ScanStage.preprocess] = const StageState(
        completed: true,
        message: 'Pre-processing complete',
      );

      stageStatus[ScanStage.detectEdges] = const StageState(
        completed: false,
        message: 'Detecting document edges',
      );
      detected = await _analyzer.detectDocument(
        input,
        minConfidence: options.minConfidence,
      );
      stageStatus[ScanStage.detectEdges] = StageState(
        completed: true,
        message: detected.isFallback
            ? 'Detection fallback used'
            : 'Edges detected',
      );

      stageStatus[ScanStage.perspectiveCorrection] = const StageState(
        completed: false,
        message: 'Applying perspective correction',
      );
      final points = detected.corners
          .map((c) => ScanPoint(c.x, c.y))
          .toList(growable: false);
      perspective =
          await _scannerService.applyPerspectiveFromCorners(
            input,
            points,
            suffix: 'warped',
          ) ??
          input;
      stageStatus[ScanStage.perspectiveCorrection] = const StageState(
        completed: true,
        message: 'Perspective corrected',
      );

      stageStatus[ScanStage.crop] = const StageState(
        completed: false,
        message: 'Auto-cropping document',
      );
      cropped = await _autoCropDocument(perspective);
      stageStatus[ScanStage.crop] = const StageState(
        completed: true,
        message: 'Auto-crop complete',
      );

      stageStatus[ScanStage.enhance] = const StageState(
        completed: false,
        message: 'Generating enhancement variants',
      );
      final variants = await _buildEnhancementVariants(cropped);
      stageStatus[ScanStage.enhance] = const StageState(
        completed: true,
        message: 'Enhancement complete',
      );

      return ScanPipelineResult(
        originalFile: input,
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

  String _buildDerivedPath(String originalPath, String suffix) {
    final dot = originalPath.lastIndexOf('.');
    if (dot == -1) return '${originalPath}_$suffix.jpg';
    return '${originalPath.substring(0, dot)}_$suffix${originalPath.substring(dot)}';
  }
}
