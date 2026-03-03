import 'dart:io';
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
      final candidates = <File>[];
      for (final imageFile in imageFiles) {
        if (!await imageFile.exists()) continue;
        candidates.add(imageFile);

        final boosted = await _createOcrVariant(
          imageFile,
          tag: 'ocr_boost',
          thresholded: false,
        );
        if (boosted != null) {
          candidates.add(boosted);
          generatedVariants.add(boosted);
        }

        final thresholded = await _createOcrVariant(
          imageFile,
          tag: 'ocr_bw',
          thresholded: true,
        );
        if (thresholded != null) {
          candidates.add(thresholded);
          generatedVariants.add(thresholded);
        }

        final textBoost = await _createTextFocusedVariant(
          imageFile,
          tag: 'ocr_text_plus',
        );
        if (textBoost != null) {
          candidates.add(textBoost);
          generatedVariants.add(textBoost);
        }
      }

      final seen = <String>{};
      final deduped = <File>[];
      for (final candidate in candidates) {
        if (seen.add(candidate.path)) {
          deduped.add(candidate);
        }
      }

      OcrResult? best;
      for (final imageFile in deduped) {
        final current = await _processSingleImage(imageFile);
        if (!current.success) continue;

        if (best == null || current.confidence > best.confidence) {
          best = current;
        }
      }

      if (best != null) {
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
    final text = _fixCommonWords(_correctOcrErrors(recognizedText.text.trim()));

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

      final tempFile = File(
        '${Directory.systemTemp.path}/ocr_${DateTime.now().microsecondsSinceEpoch}_$tag.jpg',
      );
      await tempFile.writeAsBytes(img.encodeJpg(image, quality: 95));
      return tempFile;
    } catch (_) {
      return null;
    }
  }

  Future<File?> _createTextFocusedVariant(
    File source, {
    required String tag,
  }) async {
    try {
      final bytes = await source.readAsBytes();
      var image = img.decodeImage(bytes);
      if (image == null) return null;

      image = img.bakeOrientation(image);
      image = img.grayscale(image);
      image = img.adjustColor(image, contrast: 2.1, brightness: 1.08);
      image = img.gaussianBlur(image, radius: 1);
      image = img.luminanceThreshold(image, threshold: 0.5);

      final tempFile = File(
        '${Directory.systemTemp.path}/ocr_${DateTime.now().microsecondsSinceEpoch}_$tag.jpg',
      );
      await tempFile.writeAsBytes(img.encodeJpg(image, quality: 96));
      return tempFile;
    } catch (_) {
      return null;
    }
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
