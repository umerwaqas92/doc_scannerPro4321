/// Seven-step workflow for bottom (flatbed) scanner flow.
/// Used to guide the user and show progress during scan.
enum ScannerStep {
  preScanPrep(1, 'Preparing scanner', 'Optimizing lighting and alignment...'),
  initialization(2, 'Initializing', 'Starting scanner system...'),
  scanning(3, 'Scanning', 'Capturing high-resolution image...'),
  adConversion(
    4,
    'Lighting correction',
    'Automatically detect and correct lighting and white balance...',
  ),
  imageProcessing(
    5,
    'Noise reduction',
    'Remove noise and blur while preserving natural details...',
  ),
  imageFormation(
    6,
    'Enhancing',
    'Improve sharpness, clarity and correct perspective...',
  ),
  postScan(
    7,
    'Finalizing',
    'Outputting high-resolution, clean, natural image...',
  );

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
