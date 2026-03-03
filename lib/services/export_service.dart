import 'dart:io';
import 'package:image_gallery_saver/image_gallery_saver.dart';
import 'package:permission_handler/permission_handler.dart';

class GalleryExportResult {
  final int total;
  final int saved;
  final List<String> errors;

  const GalleryExportResult({
    required this.total,
    required this.saved,
    this.errors = const [],
  });

  bool get success => saved == total && errors.isEmpty;
  bool get partialSuccess => saved > 0 && !success;
}

class ExportService {
  Future<GalleryExportResult> saveImagesToGallery(
    List<File> images, {
    String albumName = 'DocScan',
  }) async {
    final errors = <String>[];
    final valid = images.where((f) => f.existsSync()).toList(growable: false);
    if (valid.isEmpty) {
      return const GalleryExportResult(total: 0, saved: 0);
    }

    await _requestGalleryPermission();

    var saved = 0;
    for (var i = 0; i < valid.length; i++) {
      final file = valid[i];
      try {
        final result = await ImageGallerySaver.saveFile(
          file.path,
          name: _buildName(albumName, i),
        );
        final ok =
            (result is Map &&
                (result['isSuccess'] == true || result['filePath'] != null)) ||
            result == true;
        if (ok) {
          saved++;
        } else {
          errors.add('Could not save ${file.path.split('/').last}');
        }
      } catch (e) {
        errors.add('Failed to save ${file.path.split('/').last}: $e');
      }
    }

    return GalleryExportResult(
      total: valid.length,
      saved: saved,
      errors: errors,
    );
  }

  Future<void> _requestGalleryPermission() async {
    try {
      await Permission.photosAddOnly.request();
    } catch (_) {}
    try {
      await Permission.photos.request();
    } catch (_) {}
    try {
      await Permission.storage.request();
    } catch (_) {}
  }

  String _buildName(String albumName, int index) {
    final stamp = DateTime.now().millisecondsSinceEpoch;
    return '${albumName}_${stamp}_$index';
  }
}
