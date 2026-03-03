import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'ocr_service.dart';

class OcrToolPageResult {
  final List<OcrResult> pages;
  final bool fromPdf;
  final String sourceName;

  const OcrToolPageResult({
    required this.pages,
    required this.fromPdf,
    required this.sourceName,
  });
}

class OcrToolService {
  final OcrService _ocrService = OcrService();

  Future<OcrToolPageResult> processImage(File imageFile) async {
    final result = await _ocrService.processImageWithVariants([imageFile]);
    return OcrToolPageResult(
      pages: [result],
      fromPdf: false,
      sourceName: imageFile.path.split('/').last,
    );
  }

  Future<OcrToolPageResult> processPdf(File pdfFile) async {
    final bytes = await pdfFile.readAsBytes();
    final pages = <OcrResult>[];

    var index = 0;
    await for (final page in Printing.raster(bytes, dpi: 180)) {
      index++;
      final png = await page.toPng();
      final imageFile = await _writeTempImage(png, index: index);
      final result = await _ocrService.processImageWithVariants([imageFile]);
      pages.add(result);
      try {
        if (await imageFile.exists()) {
          await imageFile.delete();
        }
      } catch (_) {}
    }

    return OcrToolPageResult(
      pages: pages,
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

  void dispose() {
    _ocrService.dispose();
  }
}
