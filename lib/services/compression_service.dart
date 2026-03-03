import 'dart:io';
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'export_optimization_service.dart';

class CompressionService {
  final ExportOptimizationService _optimization = ExportOptimizationService();

  Future<File> compressFile(
    File source, {
    required ExportQualityPreset quality,
  }) async {
    final lower = source.path.toLowerCase();
    if (lower.endsWith('.pdf')) {
      return _compressPdf(source, quality: quality);
    }
    return _optimization.compressImage(source, quality: quality);
  }

  Future<File> _compressPdf(
    File source, {
    required ExportQualityPreset quality,
  }) async {
    final bytes = await source.readAsBytes();
    final renderedPages = <Uint8List>[];
    final dpi = _dpiForQuality(quality);
    final jpegQuality = quality.jpegQuality;

    await for (final page in Printing.raster(bytes, dpi: dpi)) {
      final pngBytes = await page.toPng();
      final decoded = img.decodeImage(pngBytes);
      if (decoded == null) continue;
      renderedPages.add(
        Uint8List.fromList(img.encodeJpg(decoded, quality: jpegQuality)),
      );
    }

    if (renderedPages.isEmpty) {
      return source;
    }

    final outputPdf = pw.Document();
    for (final pageImage in renderedPages) {
      final mem = pw.MemoryImage(pageImage);
      outputPdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: pw.EdgeInsets.zero,
          build: (context) =>
              pw.Center(child: pw.Image(mem, fit: pw.BoxFit.contain)),
        ),
      );
    }

    final dir = await getApplicationDocumentsDirectory();
    final base = source.path.split('/').last.replaceAll('.pdf', '');
    final outPath =
        '${dir.path}/${base}_compressed_${DateTime.now().millisecondsSinceEpoch}.pdf';
    final out = File(outPath);
    await out.writeAsBytes(await outputPdf.save(), flush: true);
    return out;
  }

  double _dpiForQuality(ExportQualityPreset quality) {
    switch (quality) {
      case ExportQualityPreset.high:
        return 150;
      case ExportQualityPreset.medium:
        return 120;
      case ExportQualityPreset.small:
        return 96;
    }
  }
}
