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
    File? ocrVariant;
    try {
      final clear = await _createDisplayClearPreview(
        imageFile,
        tag: 'clear_img',
        index: 1,
      );
      ocrVariant = await _createOcrVariantForDetection(
        imageFile,
        tag: 'clear_img',
        index: 1,
      );

      final variants = <File>[
        if (ocrVariant != null) ocrVariant,
        if (clear != null) clear,
        imageFile,
      ];
      final result = await _ocrService.processImageWithVariants(variants);

      return OcrToolPageResult(
        pages: [result],
        clearPages: [clear ?? imageFile],
        fromPdf: false,
        sourceName: imageFile.path.split('/').last,
      );
    } finally {
      await _deleteIfExists(ocrVariant);
    }
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
      File? ocrVariant;
      try {
        final clear = await _createDisplayClearPreview(
          imageFile,
          tag: 'clear_pdf',
          index: index,
        );
        ocrVariant = await _createOcrVariantForDetection(
          imageFile,
          tag: 'clear_pdf',
          index: index,
        );

        final variants = <File>[
          if (ocrVariant != null) ocrVariant,
          if (clear != null) clear,
          imageFile,
        ];
        final result = await _ocrService.processImageWithVariants(variants);
        pages.add(result);

        if (clear != null) {
          clearPages.add(clear);
        } else {
          clearPages.add(
            await _persistDisplayCopy(imageFile, tag: 'pdf_page', index: index),
          );
        }
      } finally {
        await _deleteIfExists(ocrVariant);
        await _deleteIfExists(imageFile);
      }
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
    final path = await _buildOutputPath(tag: tag, index: index);
    return source.copy(path);
  }

  Future<File?> _createDisplayClearPreview(
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

      final sourceLuma = _meanLuma(image);
      final denoised = img.gaussianBlur(image, radius: 1);
      final colorBoosted = img.adjustColor(
        denoised,
        contrast: 1.14,
        brightness: 1.05,
        saturation: 1.10,
        gamma: 0.97,
      );
      var cleaned = img.convolution(
        colorBoosted,
        filter: [0, -0.18, 0, -0.18, 1.72, -0.18, 0, -0.18, 0],
      );

      final outLuma = _meanLuma(cleaned);
      if (outLuma < 46 || outLuma < sourceLuma * 0.52 || outLuma > 244) {
        cleaned = img.adjustColor(
          image,
          contrast: 1.08,
          brightness: 1.04,
          saturation: 1.06,
          gamma: 0.98,
        );
      }

      final out = File(await _buildOutputPath(tag: tag, index: index));
      await out.writeAsBytes(img.encodeJpg(cleaned, quality: 95), flush: true);
      return out;
    } catch (_) {
      return null;
    }
  }

  Future<File?> _createOcrVariantForDetection(
    File source, {
    required String tag,
    required int index,
  }) async {
    try {
      final bytes = await source.readAsBytes();
      var image = img.decodeImage(bytes);
      if (image == null) return null;
      image = img.bakeOrientation(image);

      final gray = img.grayscale(image);
      final boosted = img.adjustColor(gray, contrast: 1.60, brightness: 1.10);
      final soft = img.gaussianBlur(boosted, radius: 1);
      final mean = _meanLuma(soft);
      final threshold = ((mean / 255.0) * 0.94).clamp(0.42, 0.62);
      var ocrReady = img.luminanceThreshold(soft, threshold: threshold);
      ocrReady = img.adjustColor(ocrReady, contrast: 1.12, brightness: 1.05);

      final out = File(await _buildOutputPath(tag: '${tag}_ocr', index: index));
      await out.writeAsBytes(img.encodeJpg(ocrReady, quality: 95), flush: true);
      return out;
    } catch (_) {
      return null;
    }
  }

  Future<String> _buildOutputPath({
    required String tag,
    required int index,
  }) async {
    final dir = await getTemporaryDirectory();
    return '${dir.path}/ocr_${tag}_${DateTime.now().microsecondsSinceEpoch}_$index.jpg';
  }

  Future<void> _deleteIfExists(File? file) async {
    if (file == null) return;
    try {
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
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
