import 'dart:io';
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'ocr_service.dart';

class OcrToolPageResult {
  final List<OcrResult> pages;
  final List<File> clearPages;
  final bool fromPdf;
  final String sourceName;

  const OcrToolPageResult({
    required this.pages,
    this.clearPages = const [],
    required this.fromPdf,
    required this.sourceName,
  });
}

class OcrToolService {
  final OcrService _ocrService = OcrService();

  Future<OcrToolPageResult> processImage(File imageFile) async {
    final clear = await _createClearPreview(
      imageFile,
      tag: 'clear_img',
      index: 1,
    );
    final variants = <File>[if (clear != null) clear, imageFile];
    final result = await _ocrService.processImageWithVariants(variants);
    return OcrToolPageResult(
      pages: [result],
      clearPages: [clear ?? imageFile],
      fromPdf: false,
      sourceName: imageFile.path.split('/').last,
    );
  }

  Future<OcrToolPageResult> processPdf(File pdfFile) async {
    final bytes = await pdfFile.readAsBytes();
    final pages = <OcrResult>[];
    final clearPages = <File>[];

    var index = 0;
    await for (final page in Printing.raster(bytes, dpi: 180)) {
      index++;
      final png = await page.toPng();
      final imageFile = await _writeTempImage(png, index: index);
      final clear = await _createClearPreview(
        imageFile,
        tag: 'clear_pdf',
        index: index,
      );
      final variants = <File>[if (clear != null) clear, imageFile];
      final result = await _ocrService.processImageWithVariants(variants);
      pages.add(result);
      if (clear != null) {
        clearPages.add(clear);
      } else {
        clearPages.add(
          await _persistDisplayCopy(imageFile, tag: 'pdf_page', index: index),
        );
      }
      try {
        if (await imageFile.exists()) {
          await imageFile.delete();
        }
      } catch (_) {}
    }

    return OcrToolPageResult(
      pages: pages,
      clearPages: clearPages,
      fromPdf: true,
      sourceName: pdfFile.path.split('/').last,
    );
  }

  Future<File> _writeTempImage(Uint8List bytes, {required int index}) async {
    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/ocr_pdf_page_${DateTime.now().microsecondsSinceEpoch}_$index.png';
    final file = File(path);
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  Future<File> _persistDisplayCopy(
    File source, {
    required String tag,
    required int index,
  }) async {
    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/ocr_${tag}_${DateTime.now().microsecondsSinceEpoch}_$index.jpg';
    return source.copy(path);
  }

  Future<File?> _createClearPreview(
    File source, {
    required String tag,
    required int index,
  }) async {
    try {
      final bytes = await source.readAsBytes();
      var image = img.decodeImage(bytes);
      if (image == null) return null;

      image = img.bakeOrientation(image);

      final maxDim = image.width > image.height ? image.width : image.height;
      if (maxDim > 1800) {
        final ratio = 1800 / maxDim;
        image = img.copyResize(
          image,
          width: (image.width * ratio).round(),
          height: (image.height * ratio).round(),
          interpolation: img.Interpolation.linear,
        );
      }

      final gray = img.grayscale(image);
      final boosted = img.adjustColor(gray, contrast: 1.95, brightness: 1.08);
      final mean = _meanLuma(boosted);
      final threshold = ((mean / 255.0) * 0.92).clamp(0.38, 0.62);
      var cleaned = img.luminanceThreshold(boosted, threshold: threshold);
      cleaned = img.adjustColor(cleaned, contrast: 1.14, brightness: 1.05);

      final out = await _persistDisplayCopy(source, tag: tag, index: index);
      await out.writeAsBytes(img.encodeJpg(cleaned, quality: 95), flush: true);
      return out;
    } catch (_) {
      return null;
    }
  }

  double _meanLuma(img.Image image) {
    var sum = 0.0;
    var samples = 0;
    final stepX = (image.width ~/ 80).clamp(1, 12);
    final stepY = (image.height ~/ 80).clamp(1, 12);
    for (int y = 0; y < image.height; y += stepY) {
      for (int x = 0; x < image.width; x += stepX) {
        sum += image.getPixel(x, y).luminance;
        samples++;
      }
    }
    if (samples == 0) return 200;
    return sum / samples;
  }

  void dispose() {
    _ocrService.dispose();
  }
}
