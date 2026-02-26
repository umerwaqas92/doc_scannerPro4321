import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

class CameraService {
  CameraController? _controller;
  List<CameraDescription>? _cameras;
  bool _isInitialized = false;
  String? _errorMessage;

  bool get isInitialized => _isInitialized;
  CameraController? get controller => _controller;
  String? get errorMessage => _errorMessage;

  Future<bool> requestPermissions() async {
    try {
      final cameraStatus = await Permission.camera.request();
      debugPrint('Camera permission status: ${cameraStatus.name}');

      if (cameraStatus.isDenied) {
        _errorMessage = 'Camera permission denied';
        return false;
      }

      if (cameraStatus.isPermanentlyDenied) {
        _errorMessage =
            'Camera permission permanently denied. Please enable in Settings.';
        return false;
      }

      return cameraStatus.isGranted;
    } catch (e) {
      _errorMessage = 'Error requesting camera permission: $e';
      debugPrint(_errorMessage);
      return false;
    }
  }

  Future<bool> initializeCamera() async {
    try {
      _errorMessage = null;

      final hasPermission = await requestPermissions();
      if (!hasPermission) {
        debugPrint('Camera permission not granted: $_errorMessage');
        return false;
      }

      _cameras = await availableCameras();
      if (_cameras == null || _cameras!.isEmpty) {
        _errorMessage = 'No cameras available on device';
        debugPrint(_errorMessage);
        return false;
      }

      debugPrint('Found ${_cameras!.length} camera(s)');

      CameraDescription? backCamera;
      for (var camera in _cameras!) {
        if (camera.lensDirection == CameraLensDirection.back) {
          backCamera = camera;
          break;
        }
      }

      final selectedCamera = backCamera ?? _cameras!.first;
      debugPrint('Using camera: ${selectedCamera.lensDirection}');

      _controller = CameraController(
        selectedCamera,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await _controller!.initialize();
      _isInitialized = true;
      debugPrint('Camera initialized successfully');
      return true;
    } catch (e) {
      _errorMessage = 'Failed to initialize camera: $e';
      _isInitialized = false;
      debugPrint(_errorMessage);
      return false;
    }
  }

  Future<File?> captureImage() async {
    if (_controller == null || !_controller!.value.isInitialized) {
      debugPrint('Camera not initialized, cannot capture');
      return null;
    }

    try {
      final XFile image = await _controller!.takePicture();
      debugPrint('Image captured: ${image.path}');
      return File(image.path);
    } catch (e) {
      debugPrint('Error capturing image: $e');
      return null;
    }
  }

  Future<void> dispose() async {
    _isInitialized = false;
    if (_controller != null) {
      try {
        await _controller!.dispose();
      } catch (e) {
        debugPrint('Error disposing camera: $e');
      }
      _controller = null;
    }
  }

  Future<void> setFlashMode(FlashMode mode) async {
    if (_controller != null && _controller!.value.isInitialized) {
      try {
        await _controller!.setFlashMode(mode);
      } catch (e) {
        debugPrint('Error setting flash mode: $e');
      }
    }
  }
}
