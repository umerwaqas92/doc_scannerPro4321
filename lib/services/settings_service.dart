import 'package:shared_preferences/shared_preferences.dart';

class SettingsService {
  static const String _autoCropKey = 'auto_crop';
  static const String _flashModeKey = 'flash_mode';
  static const String _defaultFormatKey = 'default_format';
  static const String _cloudBackupKey = 'cloud_backup';

  Future<bool> getAutoCrop() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_autoCropKey) ?? true;
  }

  Future<void> setAutoCrop(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoCropKey, value);
  }

  Future<String> getFlashMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_flashModeKey) ?? 'Auto';
  }

  Future<void> setFlashMode(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_flashModeKey, value);
  }

  Future<String> getDefaultFormat() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_defaultFormatKey) ?? 'PDF';
  }

  Future<void> setDefaultFormat(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_defaultFormatKey, value);
  }

  Future<bool> getCloudBackup() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_cloudBackupKey) ?? false;
  }

  Future<void> setCloudBackup(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_cloudBackupKey, value);
  }
}
