import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';

enum ImportedFileType { image, pdf, unknown }

class ImportedFile {
  final File file;
  final ImportedFileType type;

  const ImportedFile({required this.file, required this.type});
}

class FileImportService {
  final ImagePicker _picker = ImagePicker();

  Future<List<File>> pickImages({bool multiple = true}) async {
    if (multiple) {
      final images = await _picker.pickMultiImage(imageQuality: 95);
      return images.map((e) => File(e.path)).toList(growable: false);
    }
    final image = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 95,
    );
    if (image == null) return const [];
    return [File(image.path)];
  }

  Future<File?> pickPdf() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
    );
    final path = result?.files.single.path;
    if (path == null || path.isEmpty) return null;
    return File(path);
  }

  Future<ImportedFile?> pickImageOrPdf() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp', 'heic', 'pdf'],
    );
    final path = result?.files.single.path;
    if (path == null || path.isEmpty) return null;
    final lower = path.toLowerCase();
    final type = lower.endsWith('.pdf')
        ? ImportedFileType.pdf
        : (lower.endsWith('.jpg') ||
              lower.endsWith('.jpeg') ||
              lower.endsWith('.png') ||
              lower.endsWith('.webp') ||
              lower.endsWith('.heic'))
        ? ImportedFileType.image
        : ImportedFileType.unknown;
    return ImportedFile(file: File(path), type: type);
  }
}
