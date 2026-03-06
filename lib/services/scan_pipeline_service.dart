import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
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
    // This method is used for single-threaded/foreground runs.
    // For batch/background, use runInBackground.
    final data = await runSerialized(input, options: options);
    if (data == null) return null;

    final variants = <DocumentFilterMode, File>{};
    final rawVariants = data['enhancedVariants'] as Map<String, dynamic>;
    rawVariants.forEach((key, value) {
      final mode = DocumentFilterMode.values.firstWhere(
        (m) => m.name == key,
        orElse: () => DocumentFilterMode.original,
      );
      variants[mode] = File(value as String);
    });

    final corners = _decodeCorners(data['corners'] as List<dynamic>);
    final ordered = _decodeCorners(data['orderedCorners'] as List<dynamic>);

    return ScanPipelineResult(
      originalFile: File(data['originalPath'] as String),
      preprocessedFile: File(data['preprocessedPath'] as String),
      perspectiveFile: File(data['perspectivePath'] as String),
      croppedFile: File(data['croppedPath'] as String),
      enhancedVariants: variants,
      corners: corners,
      orderedCorners: ordered,
      detectionConfidence: data['detectionConfidence'] as double,
      perspectiveConfidence: data['perspectiveConfidence'] as double,
      usedFallback: data['usedFallback'] as bool,
      perspectiveApplied: data['perspectiveApplied'] as bool,
      stageStatus: const {}, // Minimal for serialized
    );
  }

  Future<ScanPipelineResult?> runInBackground(
    File input, {
    ScanPipelineOptions options = const ScanPipelineOptions(),
    void Function(ScanStage stage, String message)? onStage,
  }) async {
    onStage?.call(ScanStage.preprocess, 'Processing image');
    final result = await compute(_runScanPipelineWorker, <String, dynamic>{
      'path': input.path,
      'maxDimension': options.maxDimension,
      'minConfidence': options.minConfidence,
    });
    if (result == null) return null;

    final variants = <DocumentFilterMode, File>{};
    final rawVariants = result['enhancedVariants'] as Map<String, dynamic>;
    rawVariants.forEach((key, value) {
      final mode = DocumentFilterMode.values.firstWhere(
        (m) => m.name == key,
        orElse: () => DocumentFilterMode.original,
      );
      variants[mode] = File(value as String);
    });

    final corners = _decodeCorners(result['corners'] as List<dynamic>);
    final ordered = _decodeCorners(result['orderedCorners'] as List<dynamic>);

    final stageStatus = <ScanStage, StageState>{
      ScanStage.capture: const StageState(
        completed: true,
        message: 'Image captured',
      ),
      ScanStage.preprocess: const StageState(
        completed: true,
        message: 'Pre-processing complete',
      ),
      ScanStage.detectEdges: const StageState(
        completed: true,
        message: 'Edges detected',
      ),
      ScanStage.perspectiveCorrection: const StageState(
        completed: true,
        message: 'Perspective correction complete',
      ),
      ScanStage.crop: const StageState(
        completed: true,
        message: 'Auto-crop complete',
      ),
      ScanStage.enhance: const StageState(
        completed: true,
        message: 'Enhancement complete',
      ),
    };

    onStage?.call(ScanStage.enhance, 'Enhancement complete');

    return ScanPipelineResult(
      originalFile: File(result['originalPath'] as String),
      preprocessedFile: File(result['preprocessedPath'] as String),
      perspectiveFile: File(result['perspectivePath'] as String),
      croppedFile: File(result['croppedPath'] as String),
      enhancedVariants: variants,
      corners: corners,
      orderedCorners: ordered,
      detectionConfidence: result['detectionConfidence'] as double,
      perspectiveConfidence: result['perspectiveConfidence'] as double,
      usedFallback: result['usedFallback'] as bool,
      perspectiveApplied: result['perspectiveApplied'] as bool,
      stageStatus: stageStatus,
    );
  }

  Future<Map<String, dynamic>?> runSerialized(
    File input, {
    ScanPipelineOptions options = const ScanPipelineOptions(),
  }) async {
    try {
      final bytes = await input.readAsBytes();
      var image = img.decodeImage(bytes);
      if (image == null) return null;

      // 1. Bake orientation once
      image = img.bakeOrientation(image);
      final normalizedPath = _buildDerivedPath(input.path, 'oriented');
      await File(normalizedPath).writeAsBytes(img.encodeJpg(image, quality: 96));
      final normalizedInput = File(normalizedPath);

      // 2. Pre-process for detection (in-memory)
      final preprocessedImage = _scannerService.preprocessImageForDetection(
        image,
        maxHeight: options.maxDimension,
      );
      final preprocessedPath = _buildDerivedPath(input.path, 'preprocessed');
      await File(preprocessedPath).writeAsBytes(
        img.encodeJpg(preprocessedImage, quality: 95),
      );

      // 3. Detect (in-memory)
      final detected = _analyzer.detectDocumentInImage(
        image,
        minConfidence: options.minConfidence,
      );
      final perspectiveConfidence = detected.confidence;
      final orderedCorners = List<ScanCorner>.from(
        detected.corners,
        growable: false,
      );

      // 4. Perspective (in-memory)
      img.Image perspectiveImage = image;
      bool perspectiveApplied = false;
      if (_isReliablePerspectiveCandidate(detected, options.minConfidence)) {
        final points = detected.corners
            .map((c) => ScanPoint(c.x, c.y))
            .toList(growable: false);
        final warped = _scannerService.applyPerspectiveToImage(
          image,
          points,
          useDefaultOnInvalid: false,
        );
        if (warped != null) {
          perspectiveImage = warped;
          perspectiveApplied = true;
        }
      }

      final perspectivePath = _buildDerivedPath(input.path, 'warped');
      await File(
        perspectivePath,
      ).writeAsBytes(img.encodeJpg(perspectiveImage, quality: 95));

      // 5. Crop/Clean (in-memory)
      img.Image croppedImage;
      if (perspectiveApplied) {
        croppedImage = _scannerService.cleanupDocumentBoundaries(
          perspectiveImage,
        );
      } else {
        // Fallback auto-crop logic (in-memory)
        croppedImage = await _autoCropDocumentInMemory(image);
      }

      final croppedPath = _buildDerivedPath(input.path, 'cropped');
      await File(
        croppedPath,
      ).writeAsBytes(img.encodeJpg(croppedImage, quality: 90));

      // 6. Enhancement Variants (in-memory)
      final variants = await _buildEnhancementVariantsFromImage(
        croppedImage,
        croppedPath,
      );

      final serializedVariants = <String, String>{};
      variants.forEach((key, value) {
        serializedVariants[key.name] = value.path;
      });

      return <String, dynamic>{
        'originalPath': normalizedInput.path,
        'preprocessedPath': preprocessedPath,
        'perspectivePath': perspectivePath,
        'croppedPath': croppedPath,
        'enhancedVariants': serializedVariants,
        'corners': _encodeCorners(detected.corners),
        'orderedCorners': _encodeCorners(orderedCorners),
        'detectionConfidence': detected.confidence,
        'perspectiveConfidence': perspectiveConfidence,
        'usedFallback': detected.isFallback,
        'perspectiveApplied': perspectiveApplied,
      };
    } catch (_) {
      return null;
    }
  }

  Future<img.Image> _autoCropDocumentInMemory(img.Image source) async {
    final maxAnalysisDim = 1000;
    final maxDim = math.max(source.width, source.height);
    img.Image analysis = source;
    if (maxDim > maxAnalysisDim) {
      final ratio = maxAnalysisDim / maxDim;
      analysis = img.copyResize(
        source,
        width: (source.width * ratio).round(),
        height: (source.height * ratio).round(),
        interpolation: img.Interpolation.linear,
      );
    }

    final gray = img.grayscale(analysis);
    final width = gray.width;
    final height = gray.height;

    double sum = 0;
    int samples = 0;
    final probeStep = (width ~/ 120).clamp(1, 8);
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

    final scaleX = source.width / width;
    final scaleY = source.height / height;
    int mappedLeft = (left * scaleX).round();
    int mappedRight = (right * scaleX).round();
    int mappedTop = (top * scaleY).round();
    int mappedBottom = (bottom * scaleY).round();

    final marginX = (source.width * 0.01).round();
    final marginY = (source.height * 0.01).round();
    mappedLeft = (mappedLeft - marginX).clamp(0, source.width - 1);
    mappedRight = (mappedRight + marginX).clamp(0, source.width - 1);
    mappedTop = (mappedTop - marginY).clamp(0, source.height - 1);
    mappedBottom = (mappedBottom + marginY).clamp(0, source.height - 1);

    final cropWidth = mappedRight - mappedLeft + 1;
    final cropHeight = mappedBottom - mappedTop + 1;
    final enoughArea =
        cropWidth > source.width * 0.45 && cropHeight > source.height * 0.45;

    final coarseCropped = enoughArea
        ? img.copyCrop(
            source,
            x: mappedLeft,
            y: mappedTop,
            width: cropWidth,
            height: cropHeight,
          )
        : source;
    return _scannerService.cleanupDocumentBoundaries(coarseCropped);
  }

  Future<Map<DocumentFilterMode, File>> _buildEnhancementVariantsFromImage(
    img.Image source,
    String sourcePath,
  ) async {
    final variants = <DocumentFilterMode, File>{};
    variants[DocumentFilterMode.original] = File(sourcePath);

    final maxVariantDim = 1100;
    final maxDim = math.max(source.width, source.height);
    img.Image working = source;
    if (maxDim > maxVariantDim) {
      final ratio = maxVariantDim / maxDim;
      working = img.copyResize(
        source,
        width: (source.width * ratio).round(),
        height: (source.height * ratio).round(),
        interpolation: img.Interpolation.linear,
      );
    }

    // 1. Grayscale
    final grayscale = img.grayscale(working);
    final grayscaleFile = File(_buildDerivedPath(sourcePath, 'grayscale'));
    await grayscaleFile.writeAsBytes(img.encodeJpg(grayscale, quality: 85));
    variants[DocumentFilterMode.grayscale] = grayscaleFile;

    // 2. B&W
    final bw = _toStrongBlackWhite(grayscale);
    final bwFile = File(_buildDerivedPath(sourcePath, 'bw'));
    await bwFile.writeAsBytes(img.encodeJpg(bw, quality: 90));
    variants[DocumentFilterMode.blackWhite] = bwFile;

    // 3. Color Enhanced (Perfect Result)
    final colorEnhanced = _enhanceColorDocument(working);
    final colorFile = File(_buildDerivedPath(sourcePath, 'color_plus'));
    await colorFile.writeAsBytes(img.encodeJpg(colorEnhanced, quality: 90));
    variants[DocumentFilterMode.colorEnhanced] = colorFile;

    // 4. Text+ (High Contrast)
    final textPlus = _highContrastText(working);
    final textPlusFile = File(_buildDerivedPath(sourcePath, 'text_plus'));
    await textPlusFile.writeAsBytes(img.encodeJpg(textPlus, quality: 90));
    variants[DocumentFilterMode.highContrastText] = textPlusFile;

    // 5. Warm
    final warm = _warmPaper(working);
    final warmFile = File(_buildDerivedPath(sourcePath, 'warm_paper'));
    await warmFile.writeAsBytes(img.encodeJpg(warm, quality: 85));
    variants[DocumentFilterMode.warmPaper] = warmFile;

    // 6. Photo
    final photo = _photoNatural(working);
    final photoFile = File(_buildDerivedPath(sourcePath, 'photo_natural'));
    await photoFile.writeAsBytes(img.encodeJpg(photo, quality: 85));
    variants[DocumentFilterMode.photoNatural] = photoFile;

    return variants;
  }

  bool _isReliablePerspectiveCandidate(
    DetectedDocument detected,
    double minConfidence,
  ) {
    final threshold = math.max(minConfidence, 0.45);
    return !detected.isFallback &&
        detected.corners.length == 4 &&
        detected.confidence >= threshold;
  }

  img.Image _toStrongBlackWhite(img.Image grayscale) {
    double sum = 0;
    final samples = 100;
    for (int i = 0; i < samples; i++) {
      final p = grayscale.getPixel(
        (i * 17) % grayscale.width,
        (i * 23) % grayscale.height,
      );
      sum += p.r;
    }
    final mean = sum / samples;
    // Adaptive threshold based on page brightness
    final threshold = (mean * 0.88).clamp(70.0, 190.0) / 255.0;

    // Increase contrast before thresholding to reduce shadows
    var result = img.adjustColor(grayscale, contrast: 1.8, brightness: 1.15);
    return img.luminanceThreshold(result, threshold: threshold);
  }

  img.Image _enhanceColorDocument(img.Image source) {
    // 3. Image Enhancement: Increasing contrast, reducing shadows, sharpening
    var enhanced = img.adjustColor(
      source,
      contrast: 1.45,
      brightness: 1.12,
      saturation: 1.18,
      gamma: 0.92,
    );
    // Stronger sharpening filter for "Perfect Result"
    return img.convolution(
      enhanced,
      filter: [0, -0.4, 0, -0.4, 2.6, -0.4, 0, -0.4, 0],
    );
  }

  img.Image _highContrastText(img.Image source) {
    final gray = img.grayscale(source);
    final bw = _toStrongBlackWhite(gray);
    // Extreme contrast for text clarity
    return img.adjustColor(bw, contrast: 1.75, brightness: 1.1);
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

Future<Map<String, dynamic>?> _runScanPipelineWorker(
  Map<String, dynamic> args,
) async {
  final path = args['path'] as String;
  final maxDimension = args['maxDimension'] as int;
  final minConfidence = args['minConfidence'] as double;
  final service = ScanPipelineService();
  return service.runSerialized(
    File(path),
    options: ScanPipelineOptions(
      maxDimension: maxDimension,
      minConfidence: minConfidence,
    ),
  );
}

List<Map<String, double>> _encodeCorners(List<ScanCorner> corners) {
  return corners
      .map((c) => <String, double>{'x': c.x, 'y': c.y})
      .toList(growable: false);
}

List<ScanCorner> _decodeCorners(List<dynamic> corners) {
  return corners.map((c) {
    final map = c as Map<String, dynamic>;
    return ScanCorner(
      (map['x'] as num).toDouble(),
      (map['y'] as num).toDouble(),
    );
  }).toList(growable: false);
}
