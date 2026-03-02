import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

class CameraService {
  CameraController? _controller;
  List<CameraDescription>? _cameras;
  bool _isInitialized = false;
  String? _errorMessage;
  bool _isCapturing = false;

  bool get isInitialized => _isInitialized;
  CameraController? get controller => _controller;
  String? get errorMessage => _errorMessage;
  bool get isCapturing => _isCapturing;

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
        ResolutionPreset.veryHigh,
        enableAudio: false,
        imageFormatGroup: Platform.isIOS
            ? ImageFormatGroup.bgra8888
            : ImageFormatGroup.yuv420,
      );

      await _controller!.initialize();

      await _applyDocumentSettings();

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

  Future<void> _applyDocumentSettings() async {
    if (_controller == null || !_controller!.value.isInitialized) return;

    try {
      await _controller!.setFlashMode(FlashMode.auto);
      await _controller!.setFocusMode(FocusMode.auto);
      await _controller!.setExposureMode(ExposureMode.auto);
      debugPrint('Applied document settings: Flash auto');
    } catch (e) {
      debugPrint('Could not apply camera settings: $e');
    }
  }

  Future<File?> captureImage() async {
    if (_controller == null ||
        !_controller!.value.isInitialized ||
        _isCapturing) {
      debugPrint('Camera not initialized or capturing, cannot capture');
      return null;
    }

    _isCapturing = true;

    try {
      await _controller!.setFlashMode(FlashMode.auto);

      await Future.delayed(const Duration(milliseconds: 100));

      final XFile image = await _controller!.takePicture();
      debugPrint('Image captured: ${image.path}');
      return File(image.path);
    } catch (e) {
      debugPrint('Error capturing image: $e');
      return null;
    } finally {
      _isCapturing = false;
    }
  }

  Future<void> dispose() async {
    _isInitialized = false;
    final controller = _controller;
    _controller = null;
    if (controller != null) {
      try {
        await controller.dispose();
      } catch (e) {
        debugPrint('Error disposing camera: $e');
      }
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
