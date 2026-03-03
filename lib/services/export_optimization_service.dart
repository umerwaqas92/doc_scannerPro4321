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
    try {
      final outputPath = _buildJpegDerivedPath(source.path, 'compressed');
      final compressed = await FlutterImageCompress.compressAndGetFile(
        source.path,
        outputPath,
        quality: quality.jpegQuality,
        format: CompressFormat.jpeg,
      );
      return compressed != null ? File(compressed.path) : source;
    } catch (_) {
      return source;
    }
  }

  Future<List<File>> compressBatch(
    List<File> sources, {
    ExportQualityPreset quality = ExportQualityPreset.medium,
  }) async {
    final result = <File>[];
    for (final file in sources) {
      try {
        result.add(await compressImage(file, quality: quality));
      } catch (_) {
        result.add(file);
      }
    }
    return result;
  }

  String _buildJpegDerivedPath(String originalPath, String suffix) {
    final dot = originalPath.lastIndexOf('.');
    final base = dot == -1 ? originalPath : originalPath.substring(0, dot);
    return '${base}_$suffix.jpg';
  }
}
