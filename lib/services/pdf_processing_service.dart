import 'dart:io';
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class PdfProcessingService {
  Future<Uint8List?> renderFirstPage(File pdfFile, {double dpi = 130}) async {
    try {
      final bytes = await pdfFile.readAsBytes();
      await for (final page in Printing.raster(bytes, dpi: dpi)) {
        return await page.toPng();
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<Uint8List?> renderFirstPageSafe(File pdfFile) async {
    final attempts = <double>[130, 96, 72];
    for (final dpi in attempts) {
      final bytes = await renderFirstPage(pdfFile, dpi: dpi);
      if (bytes != null) return bytes;
    }
    return null;
  }

  Future<List<Uint8List>> renderAllPages(
    File pdfFile, {
    double dpi = 130,
  }) async {
    final pages = <Uint8List>[];
    try {
      if (!await pdfFile.exists()) return [];
      final bytes = await pdfFile.readAsBytes();
      if (bytes.isEmpty) return [];
      await for (final page in Printing.raster(bytes, dpi: dpi)) {
        final png = await page.toPng();
        if (png.isNotEmpty) {
          pages.add(png);
        }
      }
    } catch (_) {}
    return pages;
  }

  Uint8List? rotateImage(Uint8List pageBytes, {int angle = 90}) {
    try {
      final decoded = img.decodeImage(pageBytes);
      if (decoded == null) return null;
      final normalized = (((angle ~/ 90) % 4) + 4) % 4;
      final rotateAngle = (normalized * 90).toDouble();
      final rotated = img.copyRotate(decoded, angle: rotateAngle);
      return Uint8List.fromList(img.encodePng(rotated));
    } catch (_) {
      return null;
    }
  }

  Future<File?> buildPdfFromPageImages(
    List<Uint8List> pageImages, {
    required String fileName,
  }) async {
    if (pageImages.isEmpty) return null;
    try {
      final pdf = pw.Document();
      for (final bytes in pageImages) {
        final image = pw.MemoryImage(bytes);
        pdf.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4,
            margin: const pw.EdgeInsets.all(0),
            build: (context) =>
                pw.Center(child: pw.Image(image, fit: pw.BoxFit.contain)),
          ),
        );
      }

      final dir = await getApplicationDocumentsDirectory();
      final safe = fileName
          .trim()
          .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
          .replaceAll(RegExp(r'\s+'), '_');
      final outPath =
          '${dir.path}/${safe}_${DateTime.now().millisecondsSinceEpoch}.pdf';
      final outFile = File(outPath);
      await outFile.writeAsBytes(await pdf.save(), flush: true);
      return outFile;
    } catch (_) {
      return null;
    }
  }
}
