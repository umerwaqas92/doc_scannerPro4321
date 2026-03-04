import 'dart:io';

enum ScanStage {
  capture,
  preprocess,
  detectEdges,
  perspectiveCorrection,
  crop,
  enhance,
  ocr,
  compress,
  save,
}

enum DocumentFilterMode {
  original,
  blackWhite,
  grayscale,
  colorEnhanced,
  highContrastText,
  warmPaper,
  photoNatural,
}

extension DocumentFilterModeX on DocumentFilterMode {
  String get label {
    switch (this) {
      case DocumentFilterMode.original:
        return 'Original';
      case DocumentFilterMode.blackWhite:
        return 'B&W';
      case DocumentFilterMode.grayscale:
        return 'Grayscale';
      case DocumentFilterMode.colorEnhanced:
        return 'Color+';
      case DocumentFilterMode.highContrastText:
        return 'Text+';
      case DocumentFilterMode.warmPaper:
        return 'Warm';
      case DocumentFilterMode.photoNatural:
        return 'Photo';
    }
  }
}

class ScanCorner {
  final double x;
  final double y;

  const ScanCorner(this.x, this.y);
}

class StageState {
  final bool completed;
  final String message;

  const StageState({required this.completed, required this.message});
}

class DetectedDocument {
  final List<ScanCorner> corners;
  final double confidence;
  final bool isFallback;

  const DetectedDocument({
    required this.corners,
    required this.confidence,
    required this.isFallback,
  });
}

class ScanPipelineOptions {
  final int maxDimension;
  final double minConfidence;

  const ScanPipelineOptions({
    this.maxDimension = 2200,
    this.minConfidence = 0.5,
  });
}

class EditSessionState {
  final int pageIndex;
  final DocumentFilterMode filterMode;
  final double brightness;
  final double contrast;
  final double rotation;
  final File? outputFile;

  const EditSessionState({
    required this.pageIndex,
    required this.filterMode,
    this.brightness = 1.0,
    this.contrast = 1.0,
    this.rotation = 0.0,
    this.outputFile,
  });

  EditSessionState copyWith({
    DocumentFilterMode? filterMode,
    double? brightness,
    double? contrast,
    double? rotation,
    File? outputFile,
    bool clearOutputFile = false,
  }) {
    return EditSessionState(
      pageIndex: pageIndex,
      filterMode: filterMode ?? this.filterMode,
      brightness: brightness ?? this.brightness,
      contrast: contrast ?? this.contrast,
      rotation: rotation ?? this.rotation,
      outputFile: clearOutputFile ? null : (outputFile ?? this.outputFile),
    );
  }
}

class ScanPipelineResult {
  final File originalFile;
  final File preprocessedFile;
  final File perspectiveFile;
  final File croppedFile;
  final Map<DocumentFilterMode, File> enhancedVariants;
  final List<ScanCorner> corners;
  final List<ScanCorner> orderedCorners;
  final double detectionConfidence;
  final double perspectiveConfidence;
  final bool usedFallback;
  final bool perspectiveApplied;
  final Map<ScanStage, StageState> stageStatus;
  final DocumentFilterMode selectedFilter;

  const ScanPipelineResult({
    required this.originalFile,
    required this.preprocessedFile,
    required this.perspectiveFile,
    required this.croppedFile,
    required this.enhancedVariants,
    required this.corners,
    List<ScanCorner>? orderedCorners,
    required this.detectionConfidence,
    double? perspectiveConfidence,
    required this.usedFallback,
    this.perspectiveApplied = false,
    required this.stageStatus,
    this.selectedFilter = DocumentFilterMode.colorEnhanced,
  }) : orderedCorners = orderedCorners ?? corners,
       perspectiveConfidence = perspectiveConfidence ?? detectionConfidence;

  File get selectedOutputFile {
    return enhancedVariants[selectedFilter] ?? croppedFile;
  }

  ScanPipelineResult copyWith({
    Map<DocumentFilterMode, File>? enhancedVariants,
    DocumentFilterMode? selectedFilter,
    Map<ScanStage, StageState>? stageStatus,
    List<ScanCorner>? orderedCorners,
    double? perspectiveConfidence,
    bool? perspectiveApplied,
  }) {
    return ScanPipelineResult(
      originalFile: originalFile,
      preprocessedFile: preprocessedFile,
      perspectiveFile: perspectiveFile,
      croppedFile: croppedFile,
      enhancedVariants: enhancedVariants ?? this.enhancedVariants,
      corners: corners,
      orderedCorners: orderedCorners ?? this.orderedCorners,
      detectionConfidence: detectionConfidence,
      perspectiveConfidence:
          perspectiveConfidence ?? this.perspectiveConfidence,
      usedFallback: usedFallback,
      perspectiveApplied: perspectiveApplied ?? this.perspectiveApplied,
      stageStatus: stageStatus ?? this.stageStatus,
      selectedFilter: selectedFilter ?? this.selectedFilter,
    );
  }
}
