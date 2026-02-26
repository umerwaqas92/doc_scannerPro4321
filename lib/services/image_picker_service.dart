import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

class ImagePickerService {
  final ImagePicker _picker = ImagePicker();

  Future<bool> requestPermissions() async {
    final status = await Permission.photos.request();
    return status.isGranted || status.isLimited;
  }

  Future<File?> pickFromGallery() async {
    try {
      final hasPermission = await requestPermissions();
      if (!hasPermission) {
        final result = await _picker.pickImage(
          source: ImageSource.gallery,
          imageQuality: 90,
        );
        if (result != null) {
          return File(result.path);
        }
        return null;
      }

      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 90,
      );

      if (image != null) {
        return File(image.path);
      }
      return null;
    } catch (e) {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 90,
      );
      if (image != null) {
        return File(image.path);
      }
      return null;
    }
  }

  Future<List<File>> pickMultipleFromGallery() async {
    try {
      final List<XFile> images = await _picker.pickMultiImage(imageQuality: 90);
      return images.map((e) => File(e.path)).toList();
    } catch (e) {
      return [];
    }
  }
}
