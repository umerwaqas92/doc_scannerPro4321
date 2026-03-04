import 'dart:io';
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../models/scanned_document.dart';
import 'storage_service.dart';

class PdfService {
  final StorageService _storageService = StorageService();

  Future<ScannedDocument> createPdfFromImages(
    List<File> images,
    String fileName,
  ) async {
    final pdf = pw.Document();
    var pageCount = 0;

    for (final image in images) {
      if (!await image.exists() || await image.length() == 0) continue;
      final imageBytes = await image.readAsBytes();
      Uint8List? usableBytes;
      try {
        final decoded = img.decodeImage(imageBytes);
        if (decoded != null) {
          final oriented = img.bakeOrientation(decoded);
          final longest = oriented.width > oriented.height
              ? oriented.width
              : oriented.height;
          final resized = longest > 2200
              ? img.copyResize(
                  oriented,
                  width: oriented.width > oriented.height ? 2200 : null,
                  height: oriented.height >= oriented.width ? 2200 : null,
                  interpolation: img.Interpolation.cubic,
                )
              : oriented;
          usableBytes = Uint8List.fromList(img.encodeJpg(resized, quality: 92));
        }
      } catch (_) {
        usableBytes = null;
      }

      usableBytes ??= imageBytes;
      if (usableBytes.isEmpty) continue;
      final pdfImage = pw.MemoryImage(usableBytes);

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(0),
          build: (context) {
            return pw.Center(child: pw.Image(pdfImage, fit: pw.BoxFit.contain));
          },
        ),
      );
      pageCount++;
    }

    if (pageCount == 0) {
      throw Exception('No valid images to build PDF');
    }

    final docsPath = await _storageService.getDocumentsDirectory();
    final pdfPath = '$docsPath/$fileName.pdf';
    final file = File(pdfPath);

    final Uint8List pdfBytes = await pdf.save();
    await file.writeAsBytes(pdfBytes);

    final fileSize = await file.length();

    return ScannedDocument(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: fileName,
      filePath: pdfPath,
      createdAt: DateTime.now(),
      pageCount: pageCount,
      fileSize: fileSize,
      isPdf: true,
    );
  }

  Future<ScannedDocument> saveImageAsDocument(
    File image,
    String fileName,
  ) async {
    final docsPath = await _storageService.getDocumentsDirectory();
    final ext = fileName.contains('.') ? '' : '.jpg';
    final newPath = '$docsPath/$fileName$ext';

    final newFile = await image.copy(newPath);
    final fileSize = await newFile.length();

    return ScannedDocument(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: fileName.endsWith(ext) ? fileName : '$fileName$ext',
      filePath: newPath,
      createdAt: DateTime.now(),
      pageCount: 1,
      fileSize: fileSize,
      isPdf: false,
    );
  }
}
