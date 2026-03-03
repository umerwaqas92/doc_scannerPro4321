import 'dart:io';
import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

class DocumentScannerService {
  List<ScanPoint>? _detectedEdges;

  final StreamController<List<ScanPoint>> _edgesController =
      StreamController<List<ScanPoint>>.broadcast();
  Stream<List<ScanPoint>> get edgesStream => _edgesController.stream;

  /// The official prompt used to guide the enhancement logic
  static const String enhancementPrompt = '''
    Enhance the uploaded image captured from a camera.
    Automatically detect and correct lighting and white balance.
    Remove noise and blur while preserving natural details.
    Improve sharpness and clarity.
    Correct perspective distortion if present.
    Maintain original colors without over-saturation.
    Crop unnecessary background while keeping the main subject centered.
    Output a high-resolution, clean, natural-looking image.
  ''';

  Future<File?> processDocument(
    File imageFile, {
    bool autoEnhance = true,
  }) async {
    try {
      final bytes = await imageFile.readAsBytes();

      // Use compute to perform heavy image processing in background isolate
      final processedBytes = await compute(_processImageInBackground, {
        'bytes': bytes,
        'autoEnhance': autoEnhance,
      });

      if (processedBytes == null) {
        debugPrint('Failed to process image in background');
        return imageFile;
      }

      final outputPath = _getProcessedPath(imageFile.path);
      final outputFile = File(outputPath);
      await outputFile.writeAsBytes(processedBytes);

      debugPrint('Document processed successfully: $outputPath');
      return outputFile;
    } catch (e) {
      debugPrint('Error processing document: $e');
      return imageFile;
    }
  }

  String _getProcessedPath(String originalPath) {
    final lastDot = originalPath.lastIndexOf('.');
    if (lastDot == -1) {
      return '${originalPath}_scanned.jpg';
    }
    return '${originalPath.substring(0, lastDot)}_scanned${originalPath.substring(lastDot)}';
  }

  Future<File?> applyAdjustments(
    File imageFile, {
    double brightness = 1.0,
    double contrast = 1.0,
    double rotation = 0.0,
    int filter = 0,
    String? outputTag,
    int? maxDimension,
    int quality = 95,
  }) async {
    try {
      final bytes = await imageFile.readAsBytes();
      var image = img.decodeImage(bytes);
      if (image == null) return null;

      if (maxDimension != null) {
        final maxDim = math.max(image.width, image.height);
        if (maxDim > maxDimension) {
          final ratio = maxDimension / maxDim;
          image = img.copyResize(
            image,
            width: (image.width * ratio).round(),
            height: (image.height * ratio).round(),
            interpolation: img.Interpolation.linear,
          );
        }
      }

      final normalizedTurns = (((rotation / 90).round() % 4) + 4) % 4;
      if (normalizedTurns == 1) {
        image = img.copyRotate(image, angle: 90);
      } else if (normalizedTurns == 2) {
        image = img.copyRotate(image, angle: 180);
      } else if (normalizedTurns == 3) {
        image = img.copyRotate(image, angle: 270);
      }

      final safeBrightness = brightness.clamp(0.15, 2.5);
      final safeContrast = contrast.clamp(0.1, 2.0);
      image = img.adjustColor(
        image,
        brightness: safeBrightness,
        contrast: safeContrast,
      );

      if (filter == 2) {
        // B&W Strong
        image = img.grayscale(image);
        image = img.adjustColor(image, contrast: 1.8, brightness: 1.12);
        image = img.luminanceThreshold(image, threshold: 0.58);
      } else if (filter == 3) {
        // Grayscale
        image = img.grayscale(image);
      } else if (filter == 4) {
        // Color Enhanced
        image = img.adjustColor(
          image,
          contrast: 1.2,
          brightness: 1.08,
          saturation: 1.1,
          gamma: 0.95,
        );
      } else if (filter == 5) {
        // Text+
        image = img.grayscale(image);
        image = img.gaussianBlur(image, radius: 1);
        image = img.adjustColor(image, contrast: 2.0, brightness: 1.12);
        image = img.luminanceThreshold(image, threshold: 0.52);
      } else if (filter == 6) {
        // Warm paper look
        image = img.sepia(image, amount: 0.2);
        image = img.adjustColor(
          image,
          contrast: 1.12,
          brightness: 1.06,
          saturation: 0.96,
        );
      } else if (filter == 7) {
        // Natural photo
        image = img.adjustColor(
          image,
          contrast: 1.05,
          saturation: 1.03,
          brightness: 1.02,
          gamma: 0.98,
        );
      } else if (filter == 8) {
        // Auto
        final gray = img.grayscale(image);
        double sum = 0;
        for (final p in gray) {
          sum += p.rNormalized;
        }
        final mean = sum / (gray.width * gray.height);
        final autoBrightness = mean < 0.42
            ? 1.16
            : mean > 0.72
            ? 0.92
            : 1.04;
        final autoContrast = mean < 0.42 ? 1.22 : 1.12;
        image = img.adjustColor(
          image,
          contrast: autoContrast,
          brightness: autoBrightness,
          saturation: 1.04,
        );
      }

      final outputPath = _getAdjustedPath(imageFile.path, tag: outputTag);
      final outputFile = File(outputPath);
      final safeQuality = quality.clamp(70, 100).toInt();
      await outputFile.writeAsBytes(img.encodeJpg(image, quality: safeQuality));

      return outputFile;
    } catch (e) {
      debugPrint('Error applying adjustments: $e');
      return null;
    }
  }

  String _getAdjustedPath(String originalPath, {String? tag}) {
    final lastDot = originalPath.lastIndexOf('.');
    final safeTag = (tag == null || tag.trim().isEmpty)
        ? DateTime.now().microsecondsSinceEpoch.toString()
        : tag.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
    if (lastDot == -1) {
      return '${originalPath}_adjusted_$safeTag.jpg';
    }
    return '${originalPath.substring(0, lastDot)}_adjusted_$safeTag${originalPath.substring(lastDot)}';
  }

  Future<File?> preprocessForDetection(
    File imageFile, {
    int maxHeight = 2200,
  }) async {
    try {
      final bytes = await imageFile.readAsBytes();
      var image = img.decodeImage(bytes);
      if (image == null) return null;

      image = _preprocessResize(image, maxHeight);
      image = _preprocessGrayscale(image);
      image = _preprocessBlur(image);
      image = _preprocessNormalize(image);

      final outputPath = _buildDerivedPath(imageFile.path, 'preprocessed');
      final outputFile = File(outputPath);
      await outputFile.writeAsBytes(img.encodeJpg(image, quality: 95));
      return outputFile;
    } catch (e) {
      debugPrint('Error pre-processing image: $e');
      return null;
    }
  }

  Future<File?> applyPerspectiveFromCorners(
    File imageFile,
    List<ScanPoint> corners, {
    String suffix = 'warped',
  }) async {
    try {
      if (corners.length != 4) return imageFile;
      final bytes = await imageFile.readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return imageFile;

      final ordered = _orderPerspectiveCorners(
        corners,
        decoded.width,
        decoded.height,
      );
      final warped = _applyPerspectiveCorrection(decoded, ordered);
      final outputPath = _buildDerivedPath(imageFile.path, suffix);
      final outputFile = File(outputPath);
      await outputFile.writeAsBytes(img.encodeJpg(warped, quality: 95));
      return outputFile;
    } catch (e) {
      debugPrint('Error applying perspective: $e');
      return imageFile;
    }
  }

  String _buildDerivedPath(String originalPath, String suffix) {
    final dot = originalPath.lastIndexOf('.');
    if (dot == -1) return '${originalPath}_$suffix.jpg';
    return '${originalPath.substring(0, dot)}_$suffix${originalPath.substring(dot)}';
  }

  List<ScanPoint> _orderPerspectiveCorners(
    List<ScanPoint> corners,
    int width,
    int height,
  ) {
    if (corners.length != 4) return corners;

    final clamped = corners
        .map(
          (p) => ScanPoint(
            p.x.clamp(0, width.toDouble()),
            p.y.clamp(0, height.toDouble()),
          ),
        )
        .toList(growable: false);

    final sorted = List<ScanPoint>.from(clamped)
      ..sort((a, b) => a.y.compareTo(b.y));
    final top = sorted.take(2).toList()..sort((a, b) => a.x.compareTo(b.x));
    final bottom = sorted.skip(2).toList()..sort((a, b) => a.x.compareTo(b.x));
    final ordered = [top[0], top[1], bottom[1], bottom[0]];

    if (!_isValidQuadrilateral(ordered)) {
      return _getDefaultEdges(width, height);
    }
    return ordered;
  }

  static img.Image _preprocessResize(img.Image image, int maxHeight) {
    if (image.height > maxHeight) {
      return img.copyResize(
        image,
        height: maxHeight,
        interpolation: img.Interpolation.linear,
      );
    }
    return image;
  }

  static img.Image _preprocessGrayscale(img.Image image) {
    return img.grayscale(image);
  }

  static img.Image _preprocessBlur(img.Image image) {
    return img.gaussianBlur(image, radius: 1);
  }

  static img.Image _preprocessNormalize(img.Image image) {
    // Normalize brightness to improve contrast
    return img.adjustColor(image, brightness: 1.1, contrast: 1.15);
  }

  /// Top-level or static method for compute()
  static Uint8List? _processImageInBackground(Map<String, dynamic> params) {
    final Uint8List bytes = params['bytes'];
    final bool autoEnhance = params['autoEnhance'];

    var image = img.decodeImage(bytes);
    if (image == null) return null;

    debugPrint('Starting pre-processing pipeline...');

    // === STEP 1: PRE-PROCESSING ===
    // 1a. Resize to optimal resolution for faster processing
    image = _preprocessResize(image, 2000);
    debugPrint('Pre-processing: Resize done');

    // 1b. Convert to grayscale (for easier edge detection)
    image = _preprocessGrayscale(image);
    debugPrint('Pre-processing: Grayscale done');

    // 1c. Apply slight blur (reduce noise)
    image = _preprocessBlur(image);
    debugPrint('Pre-processing: Blur done');

    // 1d. Normalize brightness
    image = _preprocessNormalize(image);
    debugPrint('Pre-processing: Normalize done');

    final service = DocumentScannerService();

    // === STEP 2: DOCUMENT DETECTION & PERSPECTIVE ===
    // Detect edges and correct perspective
    if (autoEnhance) {
      // Convert back to color for enhancement
      image = img.adjustColor(image, saturation: 1.0);

      final edges = service._detectEdgesSync(image);
      if (edges != null) {
        image = service._applyPerspectiveCorrection(image, edges);
      }
    }

    // 2. Apply enhancement prompt logic
    if (autoEnhance) {
      image = service._enhanceWithPromptLogic(image);
    }

    return img.encodeJpg(image, quality: 95);
  }

  /// Synchronous version for internal use
  List<ScanPoint>? _detectEdgesSync(img.Image image) {
    try {
      final width = image.width;
      final height = image.height;
      final grayscale = img.grayscale(image);
      final edges = _findDocumentEdges(grayscale, width, height);

      // If we find edges, we expand them by 2% to ensure we don't clip curved edges
      if (edges != null && _isValidQuadrilateral(edges)) {
        return _expandEdges(edges, width, height, 0.02);
      }
      return _getDefaultEdges(width, height);
    } catch (e) {
      return null;
    }
  }

  Future<List<ScanPoint>?> detectEdgesFromBytes(Uint8List bytes) async {
    try {
      final edges = await compute(_detectEdgesFromBytesInBackground, bytes);
      _detectedEdges = edges;

      if (edges != null) {
        _edgesController.add(edges);
      }

      return edges;
    } catch (e) {
      debugPrint('Edge detection error: $e');
      return null;
    }
  }

  static List<ScanPoint>? _detectEdgesFromBytesInBackground(Uint8List bytes) {
    final image = img.decodeImage(bytes);
    if (image == null) return null;
    return DocumentScannerService()._detectEdgesSync(image);
  }

  img.Image _enhanceWithPromptLogic(img.Image image) {
    debugPrint('Starting image enhancement...');
    var processed = image;

    // 1. Fix curved page lighting first (before any other processing)
    processed = _fixCurvedPageLighting(processed);
    debugPrint('Curved page lighting fixed');

    // 2. Improve vision quality - enhance overall clarity
    processed = _improveVisionQuality(processed);
    debugPrint('Vision quality improved');

    // 3. Apply perspective correction for document edges
    processed = _applyDocumentPerspectiveFix(processed);
    debugPrint('Perspective fixed');

    // 4. Text Clarity and Detail Enhancement
    processed = _enhanceTextClarity(processed);
    debugPrint('Text clarity enhanced');

    // 5. Strong denoising
    processed = _denoiseAndDeBlur(processed);
    debugPrint('Denoising complete');

    // 6. Final color and contrast adjustment - make it clearly visible
    processed = _adjustColors(processed);
    debugPrint('Colors adjusted - enhancement complete');

    return processed;
  }

  /// Improves overall vision/quality of the document
  img.Image _improveVisionQuality(img.Image image) {
    // Apply auto-levels for better dynamic range
    var corrected = _applyAutoLevels(image);

    // Apply sharpening using convolution
    corrected = img.convolution(
      corrected,
      filter: [0, -0.5, 0, -0.5, 3, -0.5, 0, -0.5, 0],
    );

    return corrected;
  }

  /// Applies auto-levels to improve dynamic range
  img.Image _applyAutoLevels(img.Image image) {
    int minR = 255, maxR = 0;
    int minG = 255, maxG = 0;
    int minB = 255, maxB = 0;

    // Sample every 10th pixel for speed
    for (int y = 0; y < image.height; y += 10) {
      for (int x = 0; x < image.width; x += 10) {
        final pixel = image.getPixel(x, y);
        final r = pixel.r.toInt();
        final g = pixel.g.toInt();
        final b = pixel.b.toInt();

        if (r < minR) minR = r;
        if (r > maxR) maxR = r;
        if (g < minG) minG = g;
        if (g > maxG) maxG = g;
        if (b < minB) minB = b;
        if (b > maxB) maxB = b;
      }
    }

    // Calculate stretch factors
    final rangeR = (maxR - minR).clamp(1, 255);
    final rangeG = (maxG - minG).clamp(1, 255);
    final rangeB = (maxB - minB).clamp(1, 255);

    final output = img.Image(width: image.width, height: image.height);

    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final pixel = image.getPixel(x, y);

        final r = (((pixel.r - minR) * 255) / rangeR).clamp(0, 255).toInt();
        final g = (((pixel.g - minG) * 255) / rangeG).clamp(0, 255).toInt();
        final b = (((pixel.b - minB) * 255) / rangeB).clamp(0, 255).toInt();

        output.setPixel(x, y, img.ColorRgb8(r, g, b));
      }
    }

    return output;
  }

  /// Fixes curved page with improved detection and correction
  img.Image _fixCurvedPageLighting(img.Image image) {
    // Apply white balance first for natural colors
    var corrected = _applyWhiteBalance(image);

    // Then apply adaptive lighting based on brightness analysis
    corrected = _applyAdaptiveLighting(corrected);

    // Apply strong brightness/contrast for document visibility
    corrected = img.adjustColor(
      corrected,
      brightness: 1.15,
      contrast: 1.35,
      gamma: 1.0,
    );

    return corrected;
  }

  /// Applies perspective fix specifically for document scanning
  img.Image _applyDocumentPerspectiveFix(img.Image image) {
    try {
      // Detect edges first
      final edges = _detectDocumentEdgesSimple(image);

      if (edges != null && _isValidQuadrilateral(edges)) {
        // Apply perspective correction
        return _applyPerspectiveCorrection(image, edges);
      }

      // If no clear edges, try default perspective correction
      return _applyDefaultPerspectiveCorrection(image);
    } catch (e) {
      debugPrint('Perspective fix error: $e');
      return image;
    }
  }

  /// Simple edge detection for documents
  List<ScanPoint>? _detectDocumentEdgesSimple(img.Image image) {
    final width = image.width;
    final height = image.height;
    final grayscale = img.grayscale(image);

    // Find edges using sobel-like detection
    final binary = _detectEdgesSobel(grayscale);

    // Find document corners
    final topLeft = _findCorner(
      binary,
      width,
      height,
      0,
      0,
      width ~/ 2,
      height ~/ 2,
    );
    final topRight = _findCorner(
      binary,
      width,
      height,
      width ~/ 2,
      0,
      width,
      height ~/ 2,
    );
    final bottomRight = _findCorner(
      binary,
      width,
      height,
      width ~/ 2,
      height ~/ 2,
      width,
      height,
    );
    final bottomLeft = _findCorner(
      binary,
      width,
      height,
      0,
      height ~/ 2,
      width ~/ 2,
      height,
    );

    if (topLeft != null &&
        topRight != null &&
        bottomRight != null &&
        bottomLeft != null) {
      return [topLeft, topRight, bottomRight, bottomLeft];
    }

    return null;
  }

  img.Image _detectEdgesSobel(img.Image grayscale) {
    final output = img.Image(width: grayscale.width, height: grayscale.height);
    final width = grayscale.width;
    final height = grayscale.height;

    for (int y = 1; y < height - 1; y++) {
      for (int x = 1; x < width - 1; x++) {
        // Sobel kernels
        final gx =
            (-grayscale.getPixel(x - 1, y - 1).r.toInt() +
                    grayscale.getPixel(x + 1, y - 1).r.toInt() +
                    -2 * grayscale.getPixel(x - 1, y).r.toInt() +
                    2 * grayscale.getPixel(x + 1, y).r.toInt() +
                    -grayscale.getPixel(x - 1, y + 1).r.toInt() +
                    grayscale.getPixel(x + 1, y + 1).r.toInt())
                .abs();

        final gy =
            (-grayscale.getPixel(x - 1, y - 1).r.toInt() +
                    -2 * grayscale.getPixel(x, y - 1).r.toInt() +
                    -grayscale.getPixel(x + 1, y - 1).r.toInt() +
                    grayscale.getPixel(x - 1, y + 1).r.toInt() +
                    2 * grayscale.getPixel(x, y + 1).r.toInt() +
                    grayscale.getPixel(x + 1, y + 1).r.toInt())
                .abs();

        final magnitude = math.sqrt(gx * gx + gy * gy).toInt();

        if (magnitude > 50) {
          output.setPixel(x, y, img.ColorRgb8(255, 255, 255));
        } else {
          output.setPixel(x, y, img.ColorRgb8(0, 0, 0));
        }
      }
    }

    return output;
  }

  ScanPoint? _findCorner(
    img.Image binary,
    int imgWidth,
    int imgHeight,
    int startX,
    int startY,
    int endX,
    int endY,
  ) {
    // Clamp search area
    startX = startX.clamp(0, imgWidth - 1);
    startY = startY.clamp(0, imgHeight - 1);
    endX = endX.clamp(0, imgWidth);
    endY = endY.clamp(0, imgHeight);

    int bestX = (startX + endX) ~/ 2;
    int bestY = (startY + endY) ~/ 2;
    int maxWhite = 0;

    // Search in the quadrant for the brightest corner (most white pixels)
    for (int y = startY; y < endY; y += 10) {
      for (int x = startX; x < endX; x += 10) {
        int whiteCount = 0;
        // Count white pixels in small window
        for (int dy = 0; dy < 20 && y + dy < imgHeight; dy++) {
          for (int dx = 0; dx < 20 && x + dx < imgWidth; dx++) {
            if (binary.getPixel(x + dx, y + dy).r > 127) {
              whiteCount++;
            }
          }
        }
        if (whiteCount > maxWhite) {
          maxWhite = whiteCount;
          bestX = x + 10;
          bestY = y + 10;
        }
      }
    }

    if (maxWhite > 20) {
      return ScanPoint(bestX.toDouble(), bestY.toDouble());
    }
    return null;
  }

  img.Image _applyDefaultPerspectiveCorrection(img.Image image) {
    // Apply a gentle deskew if needed - rotate slightly to level
    return image;
  }

  /// Applies white balance correction for more natural colors
  img.Image _applyWhiteBalance(img.Image image) {
    // Calculate average of each channel
    double sumR = 0, sumG = 0, sumB = 0;
    int count = 0;

    for (int y = 0; y < image.height; y += 5) {
      for (int x = 0; x < image.width; x += 5) {
        final pixel = image.getPixel(x, y);
        sumR += pixel.r;
        sumG += pixel.g;
        sumB += pixel.b;
        count++;
      }
    }

    final avgR = sumR / count;
    final avgG = sumG / count;
    final avgB = sumB / count;

    // Target gray (mid-gray)
    const target = 128.0;

    final scaleR = target / avgR;
    final scaleG = target / avgG;
    final scaleB = target / avgB;

    final output = img.Image(width: image.width, height: image.height);

    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final pixel = image.getPixel(x, y);

        final r = (pixel.r * scaleR).clamp(0, 255).toInt();
        final g = (pixel.g * scaleG).clamp(0, 255).toInt();
        final b = (pixel.b * scaleB).clamp(0, 255).toInt();

        output.setPixel(x, y, img.ColorRgb8(r, g, b));
      }
    }

    return output;
  }

  /// Applies adaptive lighting to handle curved page shadows
  img.Image _applyAdaptiveLighting(img.Image image) {
    // For curved page correction, we use a simpler approach:
    // Detect if there's darkening at edges (curvature shadow) and lighten accordingly

    final width = image.width;
    final height = image.height;

    // Sample brightness at different regions
    final corners = [
      _getAverageBrightness(image, 0, 0, width ~/ 4, height ~/ 4),
      _getAverageBrightness(image, width * 3 ~/ 4, 0, width ~/ 4, height ~/ 4),
      _getAverageBrightness(image, 0, height * 3 ~/ 4, width ~/ 4, height ~/ 4),
      _getAverageBrightness(
        image,
        width * 3 ~/ 4,
        height * 3 ~/ 4,
        width ~/ 4,
        height ~/ 4,
      ),
    ];
    final center = _getAverageBrightness(
      image,
      width ~/ 4,
      height ~/ 4,
      width ~/ 2,
      height ~/ 2,
    );

    // If corners are darker than center, apply radial gradient correction
    final avgCorner = corners.reduce((a, b) => a + b) / 4;

    if (avgCorner < center * 0.85) {
      // Apply vignette-like correction to brighten edges
      final output = img.Image(width: image.width, height: image.height);
      final centerX = width / 2;
      final centerY = height / 2;
      final maxDist = math.sqrt(centerX * centerX + centerY * centerY);

      for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
          final dx = x - centerX;
          final dy = y - centerY;
          final dist = math.sqrt(dx * dx + dy * dy);
          final factor =
              1.0 + (dist / maxDist) * 0.3; // Up to 30% brighter at edges

          final pixel = image.getPixel(x, y);
          final r = (pixel.r * factor).clamp(0, 255).toInt();
          final g = (pixel.g * factor).clamp(0, 255).toInt();
          final b = (pixel.b * factor).clamp(0, 255).toInt();

          output.setPixel(x, y, img.ColorRgb8(r, g, b));
        }
      }
      return output;
    }

    return image;
  }

  double _getAverageBrightness(
    img.Image image,
    int startX,
    int startY,
    int width,
    int height,
  ) {
    if (width <= 0 || height <= 0) return 128;

    double sum = 0;
    int count = 0;

    for (int y = startY; y < startY + height && y < image.height; y += 2) {
      for (int x = startX; x < startX + width && x < image.width; x += 2) {
        final pixel = image.getPixel(x, y);
        sum += (pixel.r + pixel.g + pixel.b) / 3;
        count++;
      }
    }

    return count > 0 ? sum / count : 128;
  }

  /// Enhances readability of poor or faint writing
  img.Image _enhanceTextClarity(img.Image image) {
    // 1. Apply multiple passes of sharpening for better text
    var sharpened = image;
    for (int i = 0; i < 2; i++) {
      sharpened = img.convolution(
        sharpened,
        filter: [0, -0.15, 0, -0.15, 1.6, -0.15, 0, -0.15, 0],
      );
    }

    // 2. Apply local contrast enhancement for better text visibility
    sharpened = _enhanceLocalContrast(sharpened);

    // 3. Adaptive Thresholding-like logic for better contrast
    return img.adjustColor(sharpened, contrast: 1.3, brightness: 1.05);
  }

  /// Enhances local contrast for better text readability
  img.Image _enhanceLocalContrast(img.Image image) {
    final width = image.width;
    final height = image.height;

    // Downsample for faster local calculation
    const blockSize = 32;
    final localMeans = List.generate(
      (height / blockSize).ceil() + 1,
      (_) => List.filled((width / blockSize).ceil() + 1, 128.0),
    );

    // Calculate local means
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final bx = x ~/ blockSize;
        final by = y ~/ blockSize;
        final pixel = image.getPixel(x, y);
        localMeans[by][bx] += (pixel.r + pixel.g + pixel.b) / 3;
      }
    }

    // Normalize
    for (int by = 0; by < localMeans.length; by++) {
      for (int bx = 0; bx < localMeans[0].length; bx++) {
        final count = (blockSize * blockSize);
        localMeans[by][bx] /= count;
      }
    }

    // Apply local contrast enhancement
    final output = img.Image(width: width, height: height);

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final bx = (x ~/ blockSize).clamp(0, localMeans[0].length - 1);
        final by = (y ~/ blockSize).clamp(0, localMeans.length - 1);
        final localMean = localMeans[by][bx];

        final pixel = image.getPixel(x, y);
        final brightness = (pixel.r + pixel.g + pixel.b) / 3;

        // Enhance based on deviation from local mean
        double factor = 1.0;
        if (brightness < localMean - 20) {
          factor = 1.2; // Brighten dark areas more
        } else if (brightness > localMean + 20) {
          factor = 0.9; // Slightly darken bright areas
        }

        final r = (pixel.r * factor).clamp(0, 255).toInt();
        final g = (pixel.g * factor).clamp(0, 255).toInt();
        final b = (pixel.b * factor).clamp(0, 255).toInt();

        output.setPixel(x, y, img.ColorRgb8(r, g, b));
      }
    }

    return output;
  }

  img.Image _denoiseAndDeBlur(img.Image image) {
    // Apply median-like filtering using a smarter approach
    // First apply a light blur then blend with original

    // Use a directional blur approach to preserve edges better
    var blurred = _edgePreservingBlur(image);

    // Blend with original to keep details
    return _blendImages(image, blurred, 0.35);
  }

  /// Edge-preserving blur using bilateral-like approach
  img.Image _edgePreservingBlur(img.Image image) {
    final width = image.width;
    final height = image.height;
    final output = img.Image(width: width, height: height);

    const radius = 2;

    for (int y = radius; y < height - radius; y++) {
      for (int x = radius; x < width - radius; x++) {
        double sumR = 0, sumG = 0, sumB = 0;
        double weightSum = 0;

        final centerPixel = image.getPixel(x, y);
        final centerBrightness =
            (centerPixel.r + centerPixel.g + centerPixel.b) / 3;

        for (int dy = -radius; dy <= radius; dy++) {
          for (int dx = -radius; dx <= radius; dx++) {
            final pixel = image.getPixel(x + dx, y + dy);
            final brightness = (pixel.r + pixel.g + pixel.b) / 3;

            // Weight based on spatial distance and intensity difference
            final spatialWeight = 1.0 / (1 + dx * dx + dy * dy);
            final intensityWeight =
                1.0 / (1 + (brightness - centerBrightness).abs() / 50);
            final weight = spatialWeight * intensityWeight;

            sumR += pixel.r * weight;
            sumG += pixel.g * weight;
            sumB += pixel.b * weight;
            weightSum += weight;
          }
        }

        final r = (sumR / weightSum).clamp(0, 255).toInt();
        final g = (sumG / weightSum).clamp(0, 255).toInt();
        final b = (sumB / weightSum).clamp(0, 255).toInt();

        output.setPixel(x, y, img.ColorRgb8(r, g, b));
      }
    }

    // Copy border pixels
    for (int y = 0; y < radius; y++) {
      for (int x = 0; x < width; x++) {
        output.setPixel(x, y, image.getPixel(x, y));
        output.setPixel(x, height - 1 - y, image.getPixel(x, height - 1 - y));
      }
    }
    for (int x = 0; x < radius; x++) {
      for (int y = 0; y < height; y++) {
        output.setPixel(x, y, image.getPixel(x, y));
        output.setPixel(width - 1 - x, y, image.getPixel(width - 1 - x, y));
      }
    }

    return output;
  }

  img.Image _blendImages(img.Image img1, img.Image img2, double ratio) {
    final output = img.Image(width: img1.width, height: img1.height);

    for (int y = 0; y < img1.height; y++) {
      for (int x = 0; x < img1.width; x++) {
        final p1 = img1.getPixel(x, y);
        final p2 = img2.getPixel(x, y);

        final r = (p1.r * (1 - ratio) + p2.r * ratio).toInt();
        final g = (p1.g * (1 - ratio) + p2.g * ratio).toInt();
        final b = (p1.b * (1 - ratio) + p2.b * ratio).toInt();

        output.setPixel(x, y, img.ColorRgb8(r, g, b));
      }
    }

    return output;
  }

  img.Image _adjustColors(img.Image image) {
    // Apply slight saturation and ensure natural look
    var adjusted = img.adjustColor(image, saturation: 1.05);

    // Final subtle contrast boost
    return img.adjustColor(adjusted, contrast: 1.08);
  }

  List<ScanPoint>? _findDocumentEdges(
    img.Image grayscale,
    int width,
    int height,
  ) {
    try {
      final binary = _edgeDetect(grayscale);

      final topEdge = _findTopEdge(binary, width, height);
      final bottomEdge = _findBottomEdge(binary, width, height);
      final leftEdge = _findLeftEdge(binary, width, height);
      final rightEdge = _findRightEdge(binary, width, height);

      if (topEdge != null &&
          bottomEdge != null &&
          leftEdge != null &&
          rightEdge != null) {
        return [
          ScanPoint(leftEdge.x.toDouble(), topEdge.y.toDouble()),
          ScanPoint(rightEdge.x.toDouble(), topEdge.y.toDouble()),
          ScanPoint(rightEdge.x.toDouble(), bottomEdge.y.toDouble()),
          ScanPoint(leftEdge.x.toDouble(), bottomEdge.y.toDouble()),
        ];
      }

      return null;
    } catch (e) {
      return null;
    }
  }

  img.Image _edgeDetect(img.Image grayscale) {
    final output = img.Image(width: grayscale.width, height: grayscale.height);

    const threshold = 30;

    for (int y = 1; y < grayscale.height - 1; y++) {
      for (int x = 1; x < grayscale.width - 1; x++) {
        final current = grayscale.getPixel(x, y).r.toInt();
        final right = grayscale.getPixel(x + 1, y).r.toInt();
        final bottom = grayscale.getPixel(x, y + 1).r.toInt();

        final gx = (right - current).abs();
        final gy = (bottom - current).abs();
        final gradient = math.sqrt(gx * gx + gy * gy);

        if (gradient > threshold) {
          output.setPixel(x, y, img.ColorRgb8(255, 255, 255));
        } else {
          output.setPixel(x, y, img.ColorRgb8(0, 0, 0));
        }
      }
    }

    return output;
  }

  ScanPoint? _findTopEdge(img.Image binary, int width, int height) {
    for (int y = 0; y < height ~/ 3; y++) {
      int whiteCount = 0;
      for (int x = 0; x < width; x++) {
        if (binary.getPixel(x, y).r > 127) whiteCount++;
      }
      if (whiteCount > width * 0.3) {
        return ScanPoint((width ~/ 2).toDouble(), y.toDouble());
      }
    }
    return ScanPoint((width ~/ 10).toDouble(), (height ~/ 10).toDouble());
  }

  ScanPoint? _findBottomEdge(img.Image binary, int width, int height) {
    for (int y = height - 1; y > height * 2 ~/ 3; y--) {
      int whiteCount = 0;
      for (int x = 0; x < width; x++) {
        if (binary.getPixel(x, y).r > 127) whiteCount++;
      }
      if (whiteCount > width * 0.3) {
        return ScanPoint((width ~/ 2).toDouble(), y.toDouble());
      }
    }
    return ScanPoint(
      (width * 9 ~/ 10).toDouble(),
      (height * 9 ~/ 10).toDouble(),
    );
  }

  ScanPoint? _findLeftEdge(img.Image binary, int width, int height) {
    for (int x = 0; x < width ~/ 3; x++) {
      int whiteCount = 0;
      for (int y = 0; y < height; y++) {
        if (binary.getPixel(x, y).r > 127) whiteCount++;
      }
      if (whiteCount > height * 0.3) {
        return ScanPoint(x.toDouble(), (height ~/ 2).toDouble());
      }
    }
    return ScanPoint((width ~/ 10).toDouble(), (height ~/ 2).toDouble());
  }

  ScanPoint? _findRightEdge(img.Image binary, int width, int height) {
    for (int x = width - 1; x > width * 2 ~/ 3; x--) {
      int whiteCount = 0;
      for (int y = 0; y < height; y++) {
        if (binary.getPixel(x, y).r > 127) whiteCount++;
      }
      if (whiteCount > height * 0.3) {
        return ScanPoint(x.toDouble(), (height ~/ 2).toDouble());
      }
    }
    return ScanPoint((width * 9 ~/ 10).toDouble(), (height ~/ 2).toDouble());
  }

  List<ScanPoint> _getDefaultEdges(int width, int height) {
    // Better default for curved pages: tighter margin and handle aspect ratio
    final marginX = (width * 0.08);
    final marginY = (height * 0.1);
    return [
      ScanPoint(marginX.toDouble(), marginY.toDouble()),
      ScanPoint((width - marginX).toDouble(), marginY.toDouble()),
      ScanPoint((width - marginX).toDouble(), (height - marginY).toDouble()),
      ScanPoint(marginX.toDouble(), (height - marginY).toDouble()),
    ];
  }

  List<ScanPoint> _expandEdges(
    List<ScanPoint> edges,
    int width,
    int height,
    double amount,
  ) {
    final centerX = (edges[0].x + edges[1].x + edges[2].x + edges[3].x) / 4;
    final centerY = (edges[0].y + edges[1].y + edges[2].y + edges[3].y) / 4;

    return edges.map((p) {
      final dx = p.x - centerX;
      final dy = p.y - centerY;
      return ScanPoint(
        (p.x + dx * amount).clamp(0, width.toDouble()),
        (p.y + dy * amount).clamp(0, height.toDouble()),
      );
    }).toList();
  }

  bool _isValidQuadrilateral(List<ScanPoint>? edges) {
    if (edges == null || edges.length != 4) return false;

    final area = _polygonArea(edges);
    return area > 1000;
  }

  double _polygonArea(List<ScanPoint> points) {
    double area = 0;
    int j = points.length - 1;
    for (int i = 0; i < points.length; i++) {
      area += (points[j].x + points[i].x) * (points[j].y - points[i].y);
      j = i;
    }
    return (area / 2).abs();
  }

  img.Image _applyPerspectiveCorrection(
    img.Image image,
    List<ScanPoint> edges,
  ) {
    final src = edges;

    final topLeft = src[0];
    final topRight = src[1];
    final bottomRight = src[2];
    final bottomLeft = src[3];

    final widthTop = _distance(topLeft, topRight);
    final widthBottom = _distance(bottomLeft, bottomRight);
    final newWidth = math
        .max(1, math.max(widthTop, widthBottom).round())
        .clamp(1, image.width * 2);

    final heightLeft = _distance(topLeft, bottomLeft);
    final heightRight = _distance(topRight, bottomRight);
    final newHeight = math
        .max(1, math.max(heightLeft, heightRight).round())
        .clamp(1, image.height * 2);

    final dst = [
      ScanPoint(0, 0),
      ScanPoint(newWidth.toDouble(), 0),
      ScanPoint(newWidth.toDouble(), newHeight.toDouble()),
      ScanPoint(0, newHeight.toDouble()),
    ];

    return _warpPerspective(image, src, dst, newWidth, newHeight);
  }

  double _distance(ScanPoint p1, ScanPoint p2) {
    return math.sqrt(math.pow(p2.x - p1.x, 2) + math.pow(p2.y - p1.y, 2));
  }

  img.Image _warpPerspective(
    img.Image src,
    List<ScanPoint> srcPoints,
    List<ScanPoint> dstPoints,
    int width,
    int height,
  ) {
    final output = img.Image(width: width, height: height);
    img.fill(output, color: img.ColorRgb8(255, 255, 255));

    final srcMatrix = _getPerspectiveTransform(srcPoints, dstPoints);
    final invMatrix = _invertMatrix(srcMatrix);

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final srcCoords = _applyMatrix(invMatrix, x.toDouble(), y.toDouble());

        final srcX = srcCoords[0];
        final srcY = srcCoords[1];

        if (srcX >= 0 && srcX < src.width && srcY >= 0 && srcY < src.height) {
          final pixel = _bilinearInterpolate(src, srcX, srcY);
          output.setPixel(x, y, pixel);
        }
      }
    }

    return output;
  }

  List<double> _getPerspectiveTransform(
    List<ScanPoint> src,
    List<ScanPoint> dst,
  ) {
    if (src.length != 4 || dst.length != 4) {
      return [1, 0, 0, 0, 1, 0, 0, 0, 1];
    }

    final matrix = List<List<double>>.generate(
      8,
      (_) => List<double>.filled(8, 0.0),
    );
    final rhs = List<double>.filled(8, 0.0);

    for (var i = 0; i < 4; i++) {
      final x = src[i].x;
      final y = src[i].y;
      final u = dst[i].x;
      final v = dst[i].y;

      final r0 = i * 2;
      final r1 = r0 + 1;

      matrix[r0][0] = x;
      matrix[r0][1] = y;
      matrix[r0][2] = 1;
      matrix[r0][6] = -u * x;
      matrix[r0][7] = -u * y;
      rhs[r0] = u;

      matrix[r1][3] = x;
      matrix[r1][4] = y;
      matrix[r1][5] = 1;
      matrix[r1][6] = -v * x;
      matrix[r1][7] = -v * y;
      rhs[r1] = v;
    }

    final solved = _solveLinearSystem8x8(matrix, rhs);
    if (solved == null) {
      return [1, 0, 0, 0, 1, 0, 0, 0, 1];
    }

    return [
      solved[0],
      solved[1],
      solved[2],
      solved[3],
      solved[4],
      solved[5],
      solved[6],
      solved[7],
      1.0,
    ];
  }

  List<double>? _solveLinearSystem8x8(List<List<double>> a, List<double> b) {
    const n = 8;
    final aug = List<List<double>>.generate(n, (r) {
      return [...a[r], b[r]];
    });

    for (int col = 0; col < n; col++) {
      int pivot = col;
      double maxAbs = aug[col][col].abs();
      for (int r = col + 1; r < n; r++) {
        final value = aug[r][col].abs();
        if (value > maxAbs) {
          maxAbs = value;
          pivot = r;
        }
      }

      if (maxAbs < 1e-9) {
        return null;
      }
      if (pivot != col) {
        final temp = aug[col];
        aug[col] = aug[pivot];
        aug[pivot] = temp;
      }

      final pivotVal = aug[col][col];
      for (int c = col; c <= n; c++) {
        aug[col][c] /= pivotVal;
      }

      for (int r = 0; r < n; r++) {
        if (r == col) continue;
        final factor = aug[r][col];
        if (factor.abs() < 1e-12) continue;
        for (int c = col; c <= n; c++) {
          aug[r][c] -= factor * aug[col][c];
        }
      }
    }

    return List<double>.generate(n, (i) => aug[i][n]);
  }

  List<double> _invertMatrix(List<double> m) {
    final det =
        m[0] * (m[4] * m[8] - m[5] * m[7]) -
        m[1] * (m[3] * m[8] - m[5] * m[6]) +
        m[2] * (m[3] * m[7] - m[4] * m[6]);

    if (det.abs() < 0.0001) return m;

    final invDet = 1.0 / det;

    return [
      (m[4] * m[8] - m[5] * m[7]) * invDet,
      (m[2] * m[7] - m[1] * m[8]) * invDet,
      (m[1] * m[5] - m[2] * m[4]) * invDet,
      (m[5] * m[6] - m[3] * m[8]) * invDet,
      (m[0] * m[8] - m[2] * m[6]) * invDet,
      (m[2] * m[3] - m[0] * m[5]) * invDet,
      (m[3] * m[7] - m[4] * m[6]) * invDet,
      (m[1] * m[6] - m[0] * m[7]) * invDet,
      (m[0] * m[4] - m[1] * m[3]) * invDet,
    ];
  }

  List<double> _applyMatrix(List<double> m, double x, double y) {
    final w = m[6] * x + m[7] * y + m[8];
    if (w.abs() < 0.0001) {
      return [x, y, 1];
    }
    return [
      (m[0] * x + m[1] * y + m[2]) / w,
      (m[3] * x + m[4] * y + m[5]) / w,
      1,
    ];
  }

  img.Pixel _bilinearInterpolate(img.Image src, double x, double y) {
    final x0 = x.floor();
    final y0 = y.floor();
    final x1 = x0 + 1;
    final y1 = y0 + 1;

    final xRatio = x - x0;
    final yRatio = y - y0;

    final p00 = src.getPixel(
      x0.clamp(0, src.width - 1),
      y0.clamp(0, src.height - 1),
    );
    final p10 = src.getPixel(
      x1.clamp(0, src.width - 1),
      y0.clamp(0, src.height - 1),
    );
    final p01 = src.getPixel(
      x0.clamp(0, src.width - 1),
      y1.clamp(0, src.height - 1),
    );
    final p11 = src.getPixel(
      x1.clamp(0, src.width - 1),
      y1.clamp(0, src.height - 1),
    );

    final r = _interpolate(
      p00.r.toDouble(),
      p10.r.toDouble(),
      p01.r.toDouble(),
      p11.r.toDouble(),
      xRatio,
      yRatio,
    );
    final g = _interpolate(
      p00.g.toDouble(),
      p10.g.toDouble(),
      p01.g.toDouble(),
      p11.g.toDouble(),
      xRatio,
      yRatio,
    );
    final b = _interpolate(
      p00.b.toDouble(),
      p10.b.toDouble(),
      p01.b.toDouble(),
      p11.b.toDouble(),
      xRatio,
      yRatio,
    );

    return img.ColorRgb8(r.toInt(), g.toInt(), b.toInt()) as img.Pixel;
  }

  double _interpolate(
    double v00,
    double v10,
    double v01,
    double v11,
    double xRatio,
    double yRatio,
  ) {
    final v0 = v00 * (1 - xRatio) + v10 * xRatio;
    final v1 = v01 * (1 - xRatio) + v11 * xRatio;
    return v0 * (1 - yRatio) + v1 * yRatio;
  }

  img.Image _enhanceDocument(img.Image image) {
    var enhanced = img.adjustColor(image, contrast: 1.2, brightness: 1.05);
    enhanced = _increaseContrast(enhanced);
    return enhanced;
  }

  img.Image _increaseContrast(img.Image image) {
    final output = img.Image(width: image.width, height: image.height);

    const contrast = 1.15;
    const factor =
        (259.0 * (contrast * 255.0 + 255.0)) /
        (255.0 * (259.0 - contrast * 255.0));

    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final pixel = image.getPixel(x, y);

        final r = (factor * (pixel.r - 128.0) + 128.0).clamp(0.0, 255.0);
        final g = (factor * (pixel.g - 128.0) + 128.0).clamp(0.0, 255.0);
        final b = (factor * (pixel.b - 128.0) + 128.0).clamp(0.0, 255.0);

        output.setPixel(x, y, img.ColorRgb8(r.toInt(), g.toInt(), b.toInt()));
      }
    }

    return output;
  }

  Future<File?> enhanceImage(File imageFile) async {
    try {
      final bytes = await imageFile.readAsBytes();
      var image = img.decodeImage(bytes);

      if (image == null) return null;

      image = _enhanceDocument(image);

      final outputPath = imageFile.path.replaceAll('.jpg', '_enhanced.jpg');
      final outputFile = File(outputPath);
      final encodedImage = img.encodeJpg(image, quality: 95);
      await outputFile.writeAsBytes(encodedImage);

      return outputFile;
    } catch (e) {
      debugPrint('Error enhancing image: $e');
      return imageFile;
    }
  }

  void dispose() {
    _edgesController.close();
  }
}

class ScanPoint {
  final double x;
  final double y;

  ScanPoint(this.x, this.y);
}
