import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;
import '../models/scan_pipeline_models.dart';

class OcrService {
  final TextRecognizer _textRecognizer = TextRecognizer(
    script: TextRecognitionScript.latin,
  );

  Future<OcrResult> processImage(File imageFile) async {
    return processImageWithVariants([imageFile]);
  }

  Future<OcrResult> processImageWithVariants(List<File> imageFiles) async {
    if (imageFiles.isEmpty) {
      return OcrResult(success: false, text: '', error: 'No image variants');
    }

    final generatedVariants = <File>[];
    try {
      // First, try OCR on the original images.
      OcrResult? best;
      
      for (final imageFile in imageFiles) {
        if (!await imageFile.exists()) continue;
        final current = await _processSingleImage(imageFile);
        
        if (current.success && current.confidence > 0.82) {
          // If we got a very high confidence result, we can stop early.
          return current;
        }
        
        if (best == null || current.confidence > best.confidence) {
          best = current;
        }
      }

      // If confidence is low, only then try generating enhanced variants.
      if (best == null || best.confidence < 0.75) {
        final sourceForVariants = imageFiles.first; // Use the first available image
        
        final variantTags = ['ocr_text_plus', 'ocr_upscaled', 'ocr_boost'];
        for (final tag in variantTags) {
          File? variant;
          if (tag == 'ocr_text_plus') {
            variant = await _createTextFocusedVariant(sourceForVariants, tag: tag);
          } else if (tag == 'ocr_upscaled') {
            variant = await _createUpscaledVariant(sourceForVariants, tag: tag);
          } else {
            variant = await _createOcrVariant(sourceForVariants, tag: tag, thresholded: false);
          }

          if (variant != null) {
            generatedVariants.add(variant);
            final current = await _processSingleImage(variant);
            if (current.success) {
              if (best == null || current.confidence > best.confidence) {
                best = current;
              }
              // If variant gives great results, stop.
              if (current.confidence > 0.85) break;
            }
          }
        }
      }

      if (best != null && best.success) {
        return best;
      }
      
      return OcrResult(
        success: false,
        text: '',
        error: 'No text detected from image variants',
      );
    } catch (e) {
      return OcrResult(success: false, text: '', error: e.toString());
    } finally {
      for (final file in generatedVariants) {
        try {
          if (await file.exists()) {
            await file.delete();
          }
        } catch (_) {}
      }
    }
  }

  Future<OcrResult> _processSingleImage(File imageFile) async {
    final inputImage = InputImage.fromFile(imageFile);
    final recognizedText = await _textRecognizer.processImage(inputImage);
    final structuredText = _buildStructuredText(recognizedText);
    final text = _normalizeText(_fixCommonWords(_correctOcrErrors(structuredText)));

    final blocks = recognizedText.blocks
        .map((block) {
          return TextBlock(
            text: block.text,
            lines: block.lines.map((line) => line.text).toList(growable: false),
          );
        })
        .toList(growable: false);

    final confidence = _scoreRecognizedText(text, blocks);

    return OcrResult(
      success: true,
      text: text,
      blocks: blocks,
      confidence: confidence,
      sourcePath: imageFile.path,
      sourceFilter: _inferFilterFromPath(imageFile.path),
    );
  }

  String _buildStructuredText(RecognizedText recognizedText) {
    if (recognizedText.blocks.isEmpty) {
      return recognizedText.text.trim().replaceAll(RegExp(r'\s+'), ' ');
    }

    final blocks = <String>[];
    for (final block in recognizedText.blocks) {
      // Form a single paragraph from each detected block by joining lines with a space.
      final blockText = block.lines
          .map((line) => line.text.trim())
          .where((text) => text.isNotEmpty)
          .join(' ');
      
      if (blockText.isNotEmpty) {
        blocks.add(blockText);
      }
    }
    
    // Join blocks with a single newline to ensure "lined wise" structure without gaps.
    // This removes the "distanced" feel the user complained about.
    return blocks.join('\n').trim();
  }

  String _normalizeText(String text) {
    // Collapsing all multiple newlines into a single newline for a very compact form.
    String result = text.replaceAll(RegExp(r'\n+'), '\n');
    
    // Clean up multiple spaces within lines
    result = result.replaceAll(RegExp(r'[ \t]{2,}'), ' ');
    
    // Fix hyphenation at line breaks
    result = result.replaceAll(RegExp(r'(\w)-\n\s*(\w)'), r'$1$2');
    
    return result.trim();
  }

  double _scoreRecognizedText(String text, List<TextBlock> blocks) {
    if (text.trim().isEmpty) return 0.0;

    final lengthScore = (text.length / 1600).clamp(0.0, 1.0);
    final lineCount = blocks.fold<int>(0, (sum, b) => sum + b.lines.length);
    final lineScore = (lineCount / 35).clamp(0.0, 1.0);

    final validChars = RegExp(
      r'[A-Za-z0-9\s.,:;!?()\-\[\]/\\@#$%&*+=_]',
    ).allMatches(text).length;
    final validRatio = text.isEmpty
        ? 0.0
        : (validChars / text.length).clamp(0.0, 1.0);

    final words = text
        .split(RegExp(r'\s+'))
        .where((w) => w.trim().isNotEmpty)
        .toList(growable: false);
    final alphaWords = words
        .where((w) => RegExp(r"^[A-Za-z][A-Za-z'\-]{1,}$").hasMatch(w))
        .length;
    final wordQuality = words.isEmpty
        ? 0.0
        : (alphaWords / words.length).clamp(0.0, 1.0);

    final hasBadRepeats = RegExp(r'(.)\1{5,}').hasMatch(text);
    final repeatPenalty = hasBadRepeats ? 0.15 : 0.0;
    final gibberishPenalty =
        RegExp(
          r'[^A-Za-z0-9\s.,:;!?()\-\[\]/\\@#$%&*+=_]',
        ).allMatches(text).length /
        text.length;

    final score =
        (0.26 * lengthScore +
                0.20 * lineScore +
                0.25 * validRatio +
                0.29 * wordQuality -
                repeatPenalty -
                (0.14 * gibberishPenalty))
            .clamp(0.0, 1.0);
    return score;
  }

  DocumentFilterMode? _inferFilterFromPath(String path) {
    final name = path.toLowerCase();
    if (name.contains('text_plus')) return DocumentFilterMode.highContrastText;
    if (name.contains('bw')) return DocumentFilterMode.blackWhite;
    if (name.contains('grayscale')) return DocumentFilterMode.grayscale;
    if (name.contains('color_plus')) return DocumentFilterMode.colorEnhanced;
    if (name.contains('warm_paper')) return DocumentFilterMode.warmPaper;
    if (name.contains('photo_natural')) return DocumentFilterMode.photoNatural;
    return null;
  }

  String _correctOcrErrors(String text) {
    final corrections = {
      '|': 'I',
      'ﬁ': 'fi',
      'ﬂ': 'fl',
      '“': '"',
      '”': '"',
      '’': "'",
    };

    String corrected = text;
    corrections.forEach((error, correction) {
      corrected = corrected.replaceAll(error, correction);
    });

    return corrected;
  }

  String _fixCommonWords(String text) {
    final commonErrors = {'thc': 'the', 'nd': 'and', 'tc': 'to', 'hv': 'have'};

    String fixed = text;
    commonErrors.forEach((error, correction) {
      final regex = RegExp('\\b$error\\b', caseSensitive: false);
      fixed = fixed.replaceAll(regex, correction);
    });

    return fixed;
  }

  Future<File?> _createOcrVariant(
    File source, {
    required String tag,
    required bool thresholded,
  }) async {
    try {
      final bytes = await source.readAsBytes();
      final resultBytes = await compute(_ocrVariantWorker, {
        'bytes': bytes,
        'thresholded': thresholded,
      });
      
      if (resultBytes == null) return null;

      final tempFile = File(
        '${Directory.systemTemp.path}/ocr_${DateTime.now().microsecondsSinceEpoch}_$tag.jpg',
      );
      await tempFile.writeAsBytes(resultBytes);
      return tempFile;
    } catch (_) {
      return null;
    }
  }

  static Uint8List? _ocrVariantWorker(Map<String, dynamic> params) {
    final Uint8List bytes = params['bytes'];
    final bool thresholded = params['thresholded'];
    
    var image = img.decodeImage(bytes);
    if (image == null) return null;

    image = img.bakeOrientation(image);
    image = img.grayscale(image);
    image = img.gaussianBlur(image, radius: 1);

    if (thresholded) {
      image = img.adjustColor(image, contrast: 1.95, brightness: 1.12);
      image = img.luminanceThreshold(image, threshold: 0.52);
    } else {
      image = img.adjustColor(image, contrast: 1.45, brightness: 1.08);
    }

    return img.encodeJpg(image, quality: 95);
  }

  Future<File?> _createTextFocusedVariant(
    File source, {
    required String tag,
  }) async {
    try {
      final bytes = await source.readAsBytes();
      final resultBytes = await compute(_textFocusedWorker, bytes);
      
      if (resultBytes == null) return null;

      final tempFile = File(
        '${Directory.systemTemp.path}/ocr_${DateTime.now().microsecondsSinceEpoch}_$tag.jpg',
      );
      await tempFile.writeAsBytes(resultBytes);
      return tempFile;
    } catch (_) {
      return null;
    }
  }

  static Uint8List? _textFocusedWorker(Uint8List bytes) {
    var image = img.decodeImage(bytes);
    if (image == null) return null;

    image = img.bakeOrientation(image);
    image = img.grayscale(image);
    image = img.adjustColor(image, contrast: 2.1, brightness: 1.08);
    image = img.gaussianBlur(image, radius: 1);
    image = img.luminanceThreshold(image, threshold: 0.5);

    return img.encodeJpg(image, quality: 96);
  }

  Future<File?> _createUpscaledVariant(
    File source, {
    required String tag,
  }) async {
    try {
      final bytes = await source.readAsBytes();
      final resultBytes = await compute(_upscaleWorker, bytes);
      
      if (resultBytes == null) return null;

      final tempFile = File(
        '${Directory.systemTemp.path}/ocr_${DateTime.now().microsecondsSinceEpoch}_$tag.jpg',
      );
      await tempFile.writeAsBytes(resultBytes);
      return tempFile;
    } catch (_) {
      return null;
    }
  }

  static Uint8List? _upscaleWorker(Uint8List bytes) {
    var image = img.decodeImage(bytes);
    if (image == null) return null;

    image = img.bakeOrientation(image);
    final longest = image.width > image.height ? image.width : image.height;
    if (longest < 1800) {
      final scale = 1800 / longest;
      image = img.copyResize(
        image,
        width: (image.width * scale).round(),
        height: (image.height * scale).round(),
        interpolation: img.Interpolation.cubic,
      );
    }
    image = img.grayscale(image);
    image = img.adjustColor(image, contrast: 1.65, brightness: 1.04);

    return img.encodeJpg(image, quality: 96);
  }

  void dispose() {
    _textRecognizer.close();
  }
}

class OcrResult {
  final bool success;
  final String text;
  final String? error;
  final List<TextBlock> blocks;
  final double confidence;
  final String? sourcePath;
  final DocumentFilterMode? sourceFilter;

  OcrResult({
    required this.success,
    required this.text,
    this.error,
    this.blocks = const [],
    this.confidence = 0,
    this.sourcePath,
    this.sourceFilter,
  });

  OcrResult copyWith({
    bool? success,
    String? text,
    String? error,
    List<TextBlock>? blocks,
    double? confidence,
    String? sourcePath,
    DocumentFilterMode? sourceFilter,
  }) {
    return OcrResult(
      success: success ?? this.success,
      text: text ?? this.text,
      error: error ?? this.error,
      blocks: blocks ?? this.blocks,
      confidence: confidence ?? this.confidence,
      sourcePath: sourcePath ?? this.sourcePath,
      sourceFilter: sourceFilter ?? this.sourceFilter,
    );
  }
}

class TextBlock {
  final String text;
  final List<String> lines;

  TextBlock({required this.text, required this.lines});
}
