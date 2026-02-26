import 'dart:io';
import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import '../models/scanned_document.dart';
import 'storage_service.dart';

class PdfService {
  final StorageService _storageService = StorageService();

  Future<ScannedDocument> createPdfFromImages(
    List<File> images,
    String fileName,
  ) async {
    final pdf = pw.Document();

    for (final image in images) {
      final imageBytes = await image.readAsBytes();
      final pdfImage = pw.MemoryImage(imageBytes);

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(0),
          build: (context) {
            return pw.Center(child: pw.Image(pdfImage, fit: pw.BoxFit.contain));
          },
        ),
      );
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
      pageCount: images.length,
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
