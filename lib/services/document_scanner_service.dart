import 'dart:io';
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

class DocumentScannerService {
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
    bool useDefaultOnInvalid = true,
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
        useDefaultOnInvalid: useDefaultOnInvalid,
      );
      if (ordered == null) return imageFile;
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

  Future<File?> postProcessWarpedDocument(
    File imageFile, {
    String suffix = 'crop_clean',
    int quality = 94,
  }) async {
    try {
      final bytes = await imageFile.readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return imageFile;

      final cleaned = cleanupDocumentBoundaries(decoded);
      final outputPath = _buildDerivedPath(imageFile.path, suffix);
      final outputFile = File(outputPath);
      await outputFile.writeAsBytes(img.encodeJpg(cleaned, quality: quality));
      return outputFile;
    } catch (e) {
      debugPrint('Error cleaning warped document: $e');
      return imageFile;
    }
  }

  img.Image cleanupDocumentBoundaries(img.Image source) {
    if (source.width < 32 || source.height < 32) return source;

    final whiteTrimmed = _trimNearWhiteBorder(source);
    final colorTrimmed = _trimColorfulBorders(whiteTrimmed);

    img.Image cropped = colorTrimmed;
    final bounds = _detectDocumentBounds(colorTrimmed);
    if (bounds != null) {
      final candidate = _cropFromBounds(colorTrimmed, bounds);
      if (_isCropReasonable(
        colorTrimmed,
        candidate,
        minAreaRatio: 0.24,
        minWidthRatio: 0.45,
        minHeightRatio: 0.45,
      )) {
        cropped = candidate;
      }
    }

    final ringTrimmed = _trimNoisyOuterRing(cropped);
    final changedSize =
        ringTrimmed.width != cropped.width ||
        ringTrimmed.height != cropped.height;
    if (changedSize &&
        _isCropReasonable(
          cropped,
          ringTrimmed,
          minAreaRatio: 0.72,
          minWidthRatio: 0.82,
          minHeightRatio: 0.82,
        )) {
      return ringTrimmed;
    }
    return cropped;
  }

  String _buildDerivedPath(String originalPath, String suffix) {
    final dot = originalPath.lastIndexOf('.');
    if (dot == -1) return '${originalPath}_$suffix.jpg';
    return '${originalPath.substring(0, dot)}_$suffix${originalPath.substring(dot)}';
  }

  img.Image _trimNearWhiteBorder(img.Image source) {
    final width = source.width;
    final height = source.height;
    if (width < 30 || height < 30) return source;

    final maxTrimX = (width * 0.14).round();
    final maxTrimY = (height * 0.14).round();
    final minDarkInCol = (height * 0.01).round().clamp(2, height);
    final minDarkInRow = (width * 0.01).round().clamp(2, width);

    bool looksWhiteColumn(int x) {
      int dark = 0;
      for (int y = 0; y < height; y++) {
        final luma = source.getPixel(x, y).luminance;
        if (luma < 236) {
          dark++;
          if (dark >= minDarkInCol) return false;
        }
      }
      return true;
    }

    bool looksWhiteRow(int y) {
      int dark = 0;
      for (int x = 0; x < width; x++) {
        final luma = source.getPixel(x, y).luminance;
        if (luma < 236) {
          dark++;
          if (dark >= minDarkInRow) return false;
        }
      }
      return true;
    }

    int left = 0;
    int right = width - 1;
    int top = 0;
    int bottom = height - 1;

    while (left < right && left < maxTrimX && looksWhiteColumn(left)) {
      left++;
    }
    while (right > left &&
        (width - 1 - right) < maxTrimX &&
        looksWhiteColumn(right)) {
      right--;
    }
    while (top < bottom && top < maxTrimY && looksWhiteRow(top)) {
      top++;
    }
    while (bottom > top &&
        (height - 1 - bottom) < maxTrimY &&
        looksWhiteRow(bottom)) {
      bottom--;
    }

    final trimmedWidth = right - left + 1;
    final trimmedHeight = bottom - top + 1;
    if (trimmedWidth <= width * 0.6 || trimmedHeight <= height * 0.6) {
      return source;
    }

    return img.copyCrop(
      source,
      x: left,
      y: top,
      width: trimmedWidth,
      height: trimmedHeight,
    );
  }

  img.Image _trimColorfulBorders(img.Image source) {
    final width = source.width;
    final height = source.height;
    if (width < 36 || height < 36) return source;

    final maxTrimX = (width * 0.28).round();
    final maxTrimY = (height * 0.28).round();
    final sampleStep = (math.min(width, height) ~/ 300).clamp(1, 4);

    bool looksColorfulColumn(int x) {
      int total = 0;
      int colorful = 0;
      for (int y = 0; y < height; y += sampleStep) {
        final p = source.getPixel(x, y);
        final maxRgb = math.max(p.r, math.max(p.g, p.b));
        final minRgb = math.min(p.r, math.min(p.g, p.b));
        final sat = maxRgb <= 0 ? 0.0 : (maxRgb - minRgb) / maxRgb;
        final luma = p.luminance;
        if (luma > 24 && sat > 0.16) {
          colorful++;
        }
        total++;
      }
      if (total == 0) return false;
      return (colorful / total) > 0.11;
    }

    bool looksColorfulRow(int y) {
      int total = 0;
      int colorful = 0;
      for (int x = 0; x < width; x += sampleStep) {
        final p = source.getPixel(x, y);
        final maxRgb = math.max(p.r, math.max(p.g, p.b));
        final minRgb = math.min(p.r, math.min(p.g, p.b));
        final sat = maxRgb <= 0 ? 0.0 : (maxRgb - minRgb) / maxRgb;
        final luma = p.luminance;
        if (luma > 24 && sat > 0.16) {
          colorful++;
        }
        total++;
      }
      if (total == 0) return false;
      return (colorful / total) > 0.11;
    }

    int left = 0;
    int right = width - 1;
    int top = 0;
    int bottom = height - 1;

    while (left < right && left < maxTrimX && looksColorfulColumn(left)) {
      left++;
    }
    while (right > left &&
        (width - 1 - right) < maxTrimX &&
        looksColorfulColumn(right)) {
      right--;
    }
    while (top < bottom && top < maxTrimY && looksColorfulRow(top)) {
      top++;
    }
    while (bottom > top &&
        (height - 1 - bottom) < maxTrimY &&
        looksColorfulRow(bottom)) {
      bottom--;
    }

    final cropWidth = right - left + 1;
    final cropHeight = bottom - top + 1;
    if (cropWidth <= width * 0.58 || cropHeight <= height * 0.58) {
      return source;
    }

    return img.copyCrop(
      source,
      x: left,
      y: top,
      width: cropWidth,
      height: cropHeight,
    );
  }

  _CropBounds? _detectDocumentBounds(img.Image source) {
    final srcW = source.width;
    final srcH = source.height;
    if (srcW < 40 || srcH < 40) return null;

    final maxAnalysisDim = 1000;
    final maxDim = math.max(srcW, srcH);
    img.Image analysis = source;
    if (maxDim > maxAnalysisDim) {
      final ratio = maxAnalysisDim / maxDim;
      analysis = img.copyResize(
        source,
        width: (srcW * ratio).round(),
        height: (srcH * ratio).round(),
        interpolation: img.Interpolation.linear,
      );
    }

    final width = analysis.width;
    final height = analysis.height;
    final total = width * height;
    if (total < 1) return null;

    final luminance = Uint8List(total);
    final saturation = Float64List(total);
    int idx = 0;
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final p = analysis.getPixel(x, y);
        final maxRgb = math.max(p.r, math.max(p.g, p.b));
        final minRgb = math.min(p.r, math.min(p.g, p.b));
        saturation[idx] = maxRgb <= 0 ? 0.0 : (maxRgb - minRgb) / maxRgb;
        luminance[idx] = p.luminance.toInt().clamp(0, 255);
        idx++;
      }
    }

    var mask = _buildAdaptivePaperMask(luminance, saturation, width, height);
    mask = _dilateMask(mask, width, height, iterations: 1, minNeighbors: 2);
    mask = _erodeMask(mask, width, height, iterations: 1, minNeighbors: 5);
    mask = _erodeMask(mask, width, height, iterations: 1, minNeighbors: 4);
    mask = _dilateMask(mask, width, height, iterations: 1, minNeighbors: 2);

    final candidate = _findBestPaperComponent(
      mask,
      luminance,
      saturation,
      width,
      height,
    );
    if (candidate == null) return null;
    if (candidate.score < 0.34) return null;

    final scaleX = srcW / width;
    final scaleY = srcH / height;
    int left = (candidate.left * scaleX).floor();
    int top = (candidate.top * scaleY).floor();
    int right = ((candidate.right + 1) * scaleX).ceil() - 1;
    int bottom = ((candidate.bottom + 1) * scaleY).ceil() - 1;

    final padX = math.max(1, (srcW * 0.004).round());
    final padY = math.max(1, (srcH * 0.004).round());
    left = (left - padX).clamp(0, srcW - 1);
    top = (top - padY).clamp(0, srcH - 1);
    right = (right + padX).clamp(0, srcW - 1);
    bottom = (bottom + padY).clamp(0, srcH - 1);

    return _CropBounds(
      left: left,
      top: top,
      right: right,
      bottom: bottom,
      score: candidate.score,
    );
  }

  Uint8List _buildAdaptivePaperMask(
    Uint8List luminance,
    Float64List saturation,
    int width,
    int height,
  ) {
    final integral = Float64List((width + 1) * (height + 1));
    for (int y = 1; y <= height; y++) {
      double rowSum = 0;
      for (int x = 1; x <= width; x++) {
        final idx = (y - 1) * width + (x - 1);
        rowSum += luminance[idx];
        integral[y * (width + 1) + x] =
            integral[(y - 1) * (width + 1) + x] + rowSum;
      }
    }

    final radius = (math.min(width, height) / 18).round().clamp(14, 44);
    final mask = Uint8List(width * height);

    for (int y = 0; y < height; y++) {
      final y0 = math.max(0, y - radius);
      final y1 = math.min(height - 1, y + radius);
      for (int x = 0; x < width; x++) {
        final x0 = math.max(0, x - radius);
        final x1 = math.min(width - 1, x + radius);

        final sum =
            integral[(y1 + 1) * (width + 1) + (x1 + 1)] -
            integral[y0 * (width + 1) + (x1 + 1)] -
            integral[(y1 + 1) * (width + 1) + x0] +
            integral[y0 * (width + 1) + x0];
        final area = (x1 - x0 + 1) * (y1 - y0 + 1);
        final localMean = sum / area;

        final idx = y * width + x;
        final lum = luminance[idx].toDouble();
        final sat = saturation[idx];
        final brightPaper =
            lum >= (localMean - 10) && lum >= 105 && sat <= 0.58;
        final veryBright = lum >= (localMean + 6) && sat <= 0.72;
        final flatLight = lum >= 194 && sat <= 0.80;

        if (brightPaper || veryBright || flatLight) {
          mask[idx] = 1;
        }
      }
    }
    return mask;
  }

  Uint8List _dilateMask(
    Uint8List mask,
    int width,
    int height, {
    int iterations = 1,
    int minNeighbors = 2,
  }) {
    var current = mask;
    for (int i = 0; i < iterations; i++) {
      final output = Uint8List(current.length);
      for (int y = 1; y < height - 1; y++) {
        for (int x = 1; x < width - 1; x++) {
          final idx = y * width + x;
          if (current[idx] == 1) {
            output[idx] = 1;
            continue;
          }
          int neighbors = 0;
          for (int ny = y - 1; ny <= y + 1; ny++) {
            for (int nx = x - 1; nx <= x + 1; nx++) {
              if (current[ny * width + nx] == 1) {
                neighbors++;
              }
            }
          }
          if (neighbors >= minNeighbors) {
            output[idx] = 1;
          }
        }
      }
      current = output;
    }
    return current;
  }

  Uint8List _erodeMask(
    Uint8List mask,
    int width,
    int height, {
    int iterations = 1,
    int minNeighbors = 5,
  }) {
    var current = mask;
    for (int i = 0; i < iterations; i++) {
      final output = Uint8List(current.length);
      for (int y = 1; y < height - 1; y++) {
        for (int x = 1; x < width - 1; x++) {
          final idx = y * width + x;
          if (current[idx] == 0) continue;
          int neighbors = 0;
          for (int ny = y - 1; ny <= y + 1; ny++) {
            for (int nx = x - 1; nx <= x + 1; nx++) {
              if (current[ny * width + nx] == 1) {
                neighbors++;
              }
            }
          }
          if (neighbors >= minNeighbors) {
            output[idx] = 1;
          }
        }
      }
      current = output;
    }
    return current;
  }

  _CropBounds? _findBestPaperComponent(
    Uint8List mask,
    Uint8List luminance,
    Float64List saturation,
    int width,
    int height,
  ) {
    final total = width * height;
    final visited = Uint8List(total);
    final queue = List<int>.filled(total, 0, growable: false);
    _CropBounds? best;

    for (int start = 0; start < total; start++) {
      if (mask[start] == 0 || visited[start] == 1) continue;

      int head = 0;
      int tail = 0;
      queue[tail++] = start;
      visited[start] = 1;

      int count = 0;
      int minX = width;
      int maxX = 0;
      int minY = height;
      int maxY = 0;
      double sumLum = 0;
      double sumSat = 0;

      while (head < tail) {
        final idx = queue[head++];
        final x = idx % width;
        final y = idx ~/ width;
        count++;
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
        sumLum += luminance[idx];
        sumSat += saturation[idx];

        for (int ny = y - 1; ny <= y + 1; ny++) {
          if (ny < 0 || ny >= height) continue;
          for (int nx = x - 1; nx <= x + 1; nx++) {
            if (nx < 0 || nx >= width) continue;
            final nIdx = ny * width + nx;
            if (mask[nIdx] == 0 || visited[nIdx] == 1) continue;
            visited[nIdx] = 1;
            queue[tail++] = nIdx;
          }
        }
      }

      final bboxW = maxX - minX + 1;
      final bboxH = maxY - minY + 1;
      final bboxArea = math.max(1, bboxW * bboxH);
      final areaRatio = count / total;
      final fillRatio = count / bboxArea;
      final widthRatio = bboxW / width;
      final heightRatio = bboxH / height;
      if (areaRatio < 0.08 ||
          fillRatio < 0.22 ||
          widthRatio < 0.35 ||
          heightRatio < 0.35 ||
          areaRatio > 0.96) {
        continue;
      }

      final centerX = (minX + maxX) / 2;
      final centerY = (minY + maxY) / 2;
      final dx = centerX - (width / 2);
      final dy = centerY - (height / 2);
      final maxDist = math.sqrt(
        (width / 2) * (width / 2) + (height / 2) * (height / 2),
      );
      final centerScore = (1.0 - math.sqrt(dx * dx + dy * dy) / maxDist).clamp(
        0.0,
        1.0,
      );

      final aspect = bboxW / bboxH;
      final aspectScore = _aspectScore(aspect);
      final avgLum = (sumLum / count) / 255.0;
      final avgSat = (sumSat / count).clamp(0.0, 1.0);
      final toneScore = (avgLum * 0.65 + (1 - avgSat) * 0.35).clamp(0.0, 1.0);

      final touchesLeft = minX <= 2;
      final touchesTop = minY <= 2;
      final touchesRight = maxX >= width - 3;
      final touchesBottom = maxY >= height - 3;
      final borderTouches =
          (touchesLeft ? 1 : 0) +
          (touchesTop ? 1 : 0) +
          (touchesRight ? 1 : 0) +
          (touchesBottom ? 1 : 0);
      if (borderTouches == 4 && fillRatio < 0.78) continue;

      final borderPenalty = borderTouches >= 3 ? 0.23 : borderTouches * 0.055;
      final score =
          areaRatio * 0.40 +
          fillRatio * 0.25 +
          toneScore * 0.20 +
          centerScore * 0.10 +
          aspectScore * 0.05 -
          borderPenalty;

      if (best == null || score > best.score) {
        best = _CropBounds(
          left: minX,
          top: minY,
          right: maxX,
          bottom: maxY,
          score: score,
        );
      }
    }

    return best;
  }

  double _aspectScore(double aspect) {
    const targets = [0.70, 1.00, 1.40];
    double best = 0;
    for (final t in targets) {
      final diff = (aspect - t).abs() / t;
      final score = (1.0 - diff).clamp(0.0, 1.0);
      if (score > best) {
        best = score;
      }
    }
    return best;
  }

  img.Image _cropFromBounds(img.Image source, _CropBounds bounds) {
    final left = bounds.left.clamp(0, source.width - 1);
    final top = bounds.top.clamp(0, source.height - 1);
    final right = bounds.right.clamp(left, source.width - 1);
    final bottom = bounds.bottom.clamp(top, source.height - 1);
    final cropWidth = right - left + 1;
    final cropHeight = bottom - top + 1;
    if (cropWidth < 10 || cropHeight < 10) return source;
    return img.copyCrop(
      source,
      x: left,
      y: top,
      width: cropWidth,
      height: cropHeight,
    );
  }

  img.Image _trimNoisyOuterRing(img.Image source) {
    if (source.width < 40 || source.height < 40) return source;
    img.Image current = source;
    final minAllowedWidth = (source.width * 0.58).round();
    final minAllowedHeight = (source.height * 0.58).round();

    for (int i = 0; i < 5; i++) {
      if (!_outerRingLooksNoisy(current)) break;
      final step = (math.min(current.width, current.height) * 0.01)
          .round()
          .clamp(1, 12);
      if (current.width - (step * 2) < minAllowedWidth ||
          current.height - (step * 2) < minAllowedHeight) {
        break;
      }
      current = img.copyCrop(
        current,
        x: step,
        y: step,
        width: current.width - (step * 2),
        height: current.height - (step * 2),
      );
    }
    return current;
  }

  bool _outerRingLooksNoisy(img.Image image) {
    final width = image.width;
    final height = image.height;
    final band = (math.min(width, height) * 0.03).round().clamp(2, 22);
    final step = (math.min(width, height) ~/ 320).clamp(1, 4);

    int sampled = 0;
    int colorful = 0;
    double sumLum = 0;
    double sumLumSq = 0;

    bool inRing(int x, int y) =>
        x < band || y < band || x >= width - band || y >= height - band;

    for (int y = 0; y < height; y += step) {
      for (int x = 0; x < width; x += step) {
        if (!inRing(x, y)) continue;
        final p = image.getPixel(x, y);
        final maxRgb = math.max(p.r, math.max(p.g, p.b));
        final minRgb = math.min(p.r, math.min(p.g, p.b));
        final sat = maxRgb <= 0 ? 0.0 : (maxRgb - minRgb) / maxRgb;
        final lum = p.luminance;
        if (lum > 22 && sat > 0.24) colorful++;
        sumLum += lum;
        sumLumSq += lum * lum;
        sampled++;
      }
    }

    if (sampled == 0) return false;
    final colorfulRatio = colorful / sampled;
    final mean = sumLum / sampled;
    final variance = math.max(0.0, (sumLumSq / sampled) - (mean * mean));
    return colorfulRatio > 0.13 || (colorfulRatio > 0.07 && variance > 1900);
  }

  bool _isCropReasonable(
    img.Image original,
    img.Image cropped, {
    double minAreaRatio = 0.42,
    double minWidthRatio = 0.55,
    double minHeightRatio = 0.55,
  }) {
    if (cropped.width > original.width || cropped.height > original.height) {
      return false;
    }
    if (cropped.width == original.width && cropped.height == original.height) {
      return false;
    }
    final widthRatio = cropped.width / original.width;
    final heightRatio = cropped.height / original.height;
    final areaRatio =
        (cropped.width * cropped.height) / (original.width * original.height);

    return widthRatio >= minWidthRatio &&
        heightRatio >= minHeightRatio &&
        areaRatio >= minAreaRatio;
  }

  List<ScanPoint>? _orderPerspectiveCorners(
    List<ScanPoint> corners,
    int width,
    int height, {
    bool useDefaultOnInvalid = true,
  }) {
    if (corners.length != 4) return null;

    final clamped = corners
        .map(
          (p) => ScanPoint(
            p.x.clamp(0, width.toDouble()),
            p.y.clamp(0, height.toDouble()),
          ),
        )
        .toList(growable: false);

    final ordered = _orderCornersClockwise(clamped);

    if (!_isValidQuadrilateral(ordered)) {
      return useDefaultOnInvalid ? _getDefaultEdges(width, height) : null;
    }
    return ordered;
  }

  List<ScanPoint> _orderCornersClockwise(List<ScanPoint> points) {
    if (points.length != 4) return points;

    final cx = points.fold<double>(0.0, (sum, p) => sum + p.x) / points.length;
    final cy = points.fold<double>(0.0, (sum, p) => sum + p.y) / points.length;

    final withAngle =
        points
            .map((p) => (point: p, angle: math.atan2(p.y - cy, p.x - cx)))
            .toList(growable: false)
          ..sort((a, b) => a.angle.compareTo(b.angle));

    final ordered = withAngle.map((e) => e.point).toList(growable: false);
    var start = 0;
    var best = double.infinity;
    for (int i = 0; i < ordered.length; i++) {
      final value = ordered[i].x + ordered[i].y;
      if (value < best) {
        best = value;
        start = i;
      }
    }

    final rotated = List<ScanPoint>.generate(
      4,
      (i) => ordered[(start + i) % 4],
      growable: false,
    );

    final cross = _cross(rotated[0], rotated[1], rotated[2]);
    if (cross < 0) {
      return [rotated[0], rotated[3], rotated[2], rotated[1]];
    }
    return rotated;
  }

  double _cross(ScanPoint a, ScanPoint b, ScanPoint c) {
    final abx = b.x - a.x;
    final aby = b.y - a.y;
    final acx = c.x - a.x;
    final acy = c.y - a.y;
    return abx * acy - aby * acx;
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
    if (area < 1000) return false;

    final top = _distance(edges[0], edges[1]);
    final right = _distance(edges[1], edges[2]);
    final bottom = _distance(edges[2], edges[3]);
    final left = _distance(edges[3], edges[0]);
    final minEdge = math.min(math.min(top, right), math.min(bottom, left));
    if (minEdge < 18) return false;

    final maxEdge = math.max(math.max(top, right), math.max(bottom, left));
    if (maxEdge / minEdge > 25) return false;

    if (_segmentsIntersect(edges[0], edges[1], edges[2], edges[3]) ||
        _segmentsIntersect(edges[1], edges[2], edges[3], edges[0])) {
      return false;
    }

    if (!_anglesLookDocumentLike(edges)) {
      return false;
    }

    return true;
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

  bool _segmentsIntersect(ScanPoint a, ScanPoint b, ScanPoint c, ScanPoint d) {
    double orientation(ScanPoint p, ScanPoint q, ScanPoint r) {
      return (q.y - p.y) * (r.x - q.x) - (q.x - p.x) * (r.y - q.y);
    }

    bool onSegment(ScanPoint p, ScanPoint q, ScanPoint r) {
      return q.x <= math.max(p.x, r.x) &&
          q.x >= math.min(p.x, r.x) &&
          q.y <= math.max(p.y, r.y) &&
          q.y >= math.min(p.y, r.y);
    }

    final o1 = orientation(a, b, c);
    final o2 = orientation(a, b, d);
    final o3 = orientation(c, d, a);
    final o4 = orientation(c, d, b);

    if ((o1 > 0) != (o2 > 0) && (o3 > 0) != (o4 > 0)) {
      return true;
    }
    if (o1.abs() < 1e-6 && onSegment(a, c, b)) return true;
    if (o2.abs() < 1e-6 && onSegment(a, d, b)) return true;
    if (o3.abs() < 1e-6 && onSegment(c, a, d)) return true;
    if (o4.abs() < 1e-6 && onSegment(c, b, d)) return true;
    return false;
  }

  bool _anglesLookDocumentLike(List<ScanPoint> points) {
    for (int i = 0; i < points.length; i++) {
      final prev = points[(i + points.length - 1) % points.length];
      final current = points[i];
      final next = points[(i + 1) % points.length];

      final v1x = prev.x - current.x;
      final v1y = prev.y - current.y;
      final v2x = next.x - current.x;
      final v2y = next.y - current.y;

      final mag1 = math.sqrt(v1x * v1x + v1y * v1y);
      final mag2 = math.sqrt(v2x * v2x + v2y * v2y);
      if (mag1 < 1e-3 || mag2 < 1e-3) return false;

      final cosValue = ((v1x * v2x) + (v1y * v2y)) / (mag1 * mag2);
      final angle = math.acos(cosValue.clamp(-1.0, 1.0));
      final deg = angle * 180 / math.pi;
      if (deg < 25 || deg > 165) {
        return false;
      }
    }
    return true;
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
          final color = _bilinearInterpolate(src, srcX, srcY);
          output.setPixel(x, y, color);
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

    if (det.abs() < 0.0001) {
      return [1, 0, 0, 0, 1, 0, 0, 0, 1];
    }

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

  img.Color _bilinearInterpolate(img.Image src, double x, double y) {
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

    return img.ColorRgb8(r.toInt(), g.toInt(), b.toInt());
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

class _CropBounds {
  final int left;
  final int top;
  final int right;
  final int bottom;
  final double score;

  const _CropBounds({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
    required this.score,
  });
}

class ScanPoint {
  final double x;
  final double y;

  ScanPoint(this.x, this.y);
}
