import 'dart:io';
import 'package:flutter_image_compress/flutter_image_compress.dart';

enum ExportQualityPreset { high, medium, small }

extension ExportQualityPresetX on ExportQualityPreset {
  int get jpegQuality {
    switch (this) {
      case ExportQualityPreset.high:
        return 92;
      case ExportQualityPreset.medium:
        return 82;
      case ExportQualityPreset.small:
        return 70;
    }
  }
}

class ExportOptimizationService {
  Future<File> compressImage(
    File source, {
    ExportQualityPreset quality = ExportQualityPreset.medium,
  }) async {
    final outputPath = _buildDerivedPath(source.path, 'compressed');
    final compressed = await FlutterImageCompress.compressAndGetFile(
      source.path,
      outputPath,
      quality: quality.jpegQuality,
      format: CompressFormat.jpeg,
    );
    return compressed != null ? File(compressed.path) : source;
  }

  Future<List<File>> compressBatch(
    List<File> sources, {
    ExportQualityPreset quality = ExportQualityPreset.medium,
  }) async {
    final result = <File>[];
    for (final file in sources) {
      result.add(await compressImage(file, quality: quality));
    }
    return result;
  }

  String _buildDerivedPath(String originalPath, String suffix) {
    final dot = originalPath.lastIndexOf('.');
    if (dot == -1) return '${originalPath}_$suffix.jpg';
    return '${originalPath.substring(0, dot)}_$suffix${originalPath.substring(dot)}';
  }
}
