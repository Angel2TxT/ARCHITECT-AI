import 'package:flutter/material.dart';
import 'package:movil_architect/core/storage/settings_storage.dart';

class ThemeService extends ChangeNotifier {
  ThemeService({SettingsStorage? settingsStorage})
      : _settingsStorage = settingsStorage;

  SettingsStorage? _settingsStorage;
  ThemeMode _themeMode = ThemeMode.light;

  ThemeMode get themeMode => _themeMode;
  bool get isDarkMode => _themeMode == ThemeMode.dark;

  Future<void> init(SettingsStorage settingsStorage) async {
    _settingsStorage = settingsStorage;
    final dark = await settingsStorage.isDarkModeEnabled();
    _themeMode = dark ? ThemeMode.dark : ThemeMode.light;
    notifyListeners();
  }

  Future<void> setDarkMode(bool enabled) async {
    _themeMode = enabled ? ThemeMode.dark : ThemeMode.light;
    notifyListeners();
    await _settingsStorage?.saveDarkMode(enabled);
  }
}
