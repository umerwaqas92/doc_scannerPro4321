import 'dart:io';
import 'package:image/image.dart' as img;

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
      final sourceBytes = await source.readAsBytes();
      var decoded = img.decodeImage(sourceBytes);
      if (decoded == null) {
        return source;
      }

      decoded = img.bakeOrientation(decoded);
      decoded = _resizeForQuality(decoded, quality);

      final outputPath = _buildJpegOutputPath(source.path, 'compressed');
      final output = File(outputPath);
      await output.writeAsBytes(
        img.encodeJpg(decoded, quality: quality.jpegQuality),
        flush: true,
      );

      if (!await output.exists()) return source;
      final outputSize = await output.length();
      if (outputSize <= 0) return source;
      return output;
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

  img.Image _resizeForQuality(img.Image source, ExportQualityPreset quality) {
    final maxDimension = switch (quality) {
      ExportQualityPreset.high => 2200,
      ExportQualityPreset.medium => 1800,
      ExportQualityPreset.small => 1400,
    };

    final longest = source.width > source.height ? source.width : source.height;
    if (longest <= maxDimension) return source;

    final scale = maxDimension / longest;
    final width = (source.width * scale).round();
    final height = (source.height * scale).round();
    return img.copyResize(
      source,
      width: width,
      height: height,
      interpolation: img.Interpolation.cubic,
    );
  }

  String _buildJpegOutputPath(String originalPath, String suffix) {
    final fileName = originalPath.split('/').last;
    final dot = fileName.lastIndexOf('.');
    final baseName = dot == -1 ? fileName : fileName.substring(0, dot);
    return '${Directory.systemTemp.path}/${baseName}_${suffix}_${DateTime.now().microsecondsSinceEpoch}.jpg';
  }
}
