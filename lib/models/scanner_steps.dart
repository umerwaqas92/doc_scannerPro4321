/// Seven-step workflow for bottom (flatbed) scanner flow.
/// Used to guide the user and show progress during scan.
enum ScannerStep {
  preScanPrep(1, 'Initial preparation', 'Optimizing lighting and alignment...'),
  initialization(2, 'Scanner initialization', 'Lamp on. Moving to start position...'),
  scanning(3, 'High-resolution scan', 'Capturing image and detecting edges...'),
  adConversion(4, 'Enhancement phase', 'Detecting and correcting lighting and white balance...'),
  imageProcessing(5, 'Image processing', 'Removing noise and blur while preserving details...'),
  imageFormation(6, 'Image formation', 'Improving sharpness, clarity and perspective...'),
  postScan(7, 'Post-scan', 'Outputting high-resolution, clean, natural image.');

  const ScannerStep(this.stepNumber, this.title, this.description);

  final int stepNumber;
  final String title;
  final String description;

  static const int totalSteps = 7;

  static ScannerStep fromStepNumber(int number) {
    return ScannerStep.values.firstWhere(
      (s) => s.stepNumber == number,
      orElse: () => ScannerStep.preScanPrep,
    );
  }
}
