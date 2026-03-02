import 'dart:io';
import 'dart:math' as math;
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

    // Analyze on a downscaled image for much faster auto-crop.
    final maxAnalysisDim = 1200;
    final maxDim = math.max(decoded.width, decoded.height);
    img.Image analysis = decoded;
    if (maxDim > maxAnalysisDim) {
      final ratio = maxAnalysisDim / maxDim;
      analysis = img.copyResize(
        decoded,
        width: (decoded.width * ratio).round(),
        height: (decoded.height * ratio).round(),
        interpolation: img.Interpolation.linear,
      );
    }

    final gray = img.grayscale(analysis);
    final width = gray.width;
    final height = gray.height;

    double sum = 0;
    int samples = 0;
    final probeStep = (width ~/ 140).clamp(1, 8);
    for (int y = 0; y < height; y += probeStep) {
      for (int x = 0; x < width; x += probeStep) {
        sum += gray.getPixel(x, y).r;
        samples++;
      }
    }
    final mean = samples == 0 ? 220.0 : sum / samples;
    final contentThreshold = (mean - 18).clamp(165.0, 238.0);

    final minColPixels = (height * 0.04).round().clamp(2, height);
    final minRowPixels = (width * 0.04).round().clamp(2, width);

    int left = 0;
    int right = width - 1;
    int top = 0;
    int bottom = height - 1;

    bool hasContentInColumn(int x) {
      int count = 0;
      for (int y = 0; y < height; y++) {
        final value = gray.getPixel(x, y).r;
        if (value < contentThreshold && value > 8) {
          count++;
          if (count >= minColPixels) return true;
        }
      }
      return false;
    }

    bool hasContentInRow(int y) {
      int count = 0;
      for (int x = 0; x < width; x++) {
        final value = gray.getPixel(x, y).r;
        if (value < contentThreshold && value > 8) {
          count++;
          if (count >= minRowPixels) return true;
        }
      }
      return false;
    }

    while (left < right && !hasContentInColumn(left)) {
      left++;
    }
    while (right > left && !hasContentInColumn(right)) {
      right--;
    }
    while (top < bottom && !hasContentInRow(top)) {
      top++;
    }
    while (bottom > top && !hasContentInRow(bottom)) {
      bottom--;
    }

    final scaleX = decoded.width / width;
    final scaleY = decoded.height / height;
    int mappedLeft = (left * scaleX).round();
    int mappedRight = (right * scaleX).round();
    int mappedTop = (top * scaleY).round();
    int mappedBottom = (bottom * scaleY).round();

    // Keep a safety margin so auto-crop does not trim text near edges.
    final marginX = (decoded.width * 0.02).round();
    final marginY = (decoded.height * 0.02).round();
    mappedLeft = (mappedLeft - marginX).clamp(0, decoded.width - 1);
    mappedRight = (mappedRight + marginX).clamp(0, decoded.width - 1);
    mappedTop = (mappedTop - marginY).clamp(0, decoded.height - 1);
    mappedBottom = (mappedBottom + marginY).clamp(0, decoded.height - 1);

    final cropWidth = mappedRight - mappedLeft + 1;
    final cropHeight = mappedBottom - mappedTop + 1;
    final enoughArea =
        cropWidth > decoded.width * 0.62 && cropHeight > decoded.height * 0.62;

    final result = enoughArea
        ? img.copyCrop(
            decoded,
            x: mappedLeft,
            y: mappedTop,
            width: cropWidth,
            height: cropHeight,
          )
        : decoded;

    final output = File(_buildDerivedPath(file.path, 'cropped'));
    await output.writeAsBytes(img.encodeJpg(result, quality: 90));
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

    // Build enhancement variants from a resized working copy for speed.
    img.Image working = decoded;
    final maxVariantDim = 1500;
    final maxDim = math.max(decoded.width, decoded.height);
    if (maxDim > maxVariantDim) {
      final ratio = maxVariantDim / maxDim;
      working = img.copyResize(
        decoded,
        width: (decoded.width * ratio).round(),
        height: (decoded.height * ratio).round(),
        interpolation: img.Interpolation.linear,
      );
    }

    final grayscale = img.grayscale(working);
    final grayscaleFile = File(_buildDerivedPath(source.path, 'grayscale'));
    await grayscaleFile.writeAsBytes(img.encodeJpg(grayscale, quality: 88));
    variants[DocumentFilterMode.grayscale] = grayscaleFile;

    final bw = _toStrongBlackWhite(grayscale);
    final bwFile = File(_buildDerivedPath(source.path, 'bw'));
    await bwFile.writeAsBytes(img.encodeJpg(bw, quality: 88));
    variants[DocumentFilterMode.blackWhite] = bwFile;

    final colorEnhanced = _enhanceColorDocument(working);
    final colorFile = File(_buildDerivedPath(source.path, 'color_plus'));
    await colorFile.writeAsBytes(img.encodeJpg(colorEnhanced, quality: 88));
    variants[DocumentFilterMode.colorEnhanced] = colorFile;

    final textPlus = _highContrastText(working);
    final textPlusFile = File(_buildDerivedPath(source.path, 'text_plus'));
    await textPlusFile.writeAsBytes(img.encodeJpg(textPlus, quality: 88));
    variants[DocumentFilterMode.highContrastText] = textPlusFile;

    final warm = _warmPaper(working);
    final warmFile = File(_buildDerivedPath(source.path, 'warm_paper'));
    await warmFile.writeAsBytes(img.encodeJpg(warm, quality: 88));
    variants[DocumentFilterMode.warmPaper] = warmFile;

    final photo = _photoNatural(working);
    final photoFile = File(_buildDerivedPath(source.path, 'photo_natural'));
    await photoFile.writeAsBytes(img.encodeJpg(photo, quality: 88));
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
