import 'dart:io';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

class OcrService {
  final TextRecognizer _textRecognizer = TextRecognizer(
    script: TextRecognitionScript.latin,
  );

  Future<OcrResult> processImage(File imageFile) async {
    try {
      final inputImage = InputImage.fromFile(imageFile);
      final recognizedText = await _textRecognizer.processImage(inputImage);
      final text = _fixCommonWords(
        _correctOcrErrors(recognizedText.text.trim()),
      );

      final blocks = recognizedText.blocks
          .map((block) {
            return TextBlock(
              text: block.text,
              lines: block.lines
                  .map((line) => line.text)
                  .toList(growable: false),
            );
          })
          .toList(growable: false);

      return OcrResult(success: true, text: text, blocks: blocks);
    } catch (e) {
      return OcrResult(success: false, text: '', error: e.toString());
    }
  }

  String _correctOcrErrors(String text) {
    final corrections = {'|': 'I', '0': 'O', '1': 'I', 'rn': 'm', 'vv': 'w'};

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

  void dispose() {
    _textRecognizer.close();
  }
}

class OcrResult {
  final bool success;
  final String text;
  final String? error;
  final List<TextBlock> blocks;

  OcrResult({
    required this.success,
    required this.text,
    this.error,
    this.blocks = const [],
  });
}

class TextBlock {
  final String text;
  final List<String> lines;

  TextBlock({required this.text, required this.lines});
}
