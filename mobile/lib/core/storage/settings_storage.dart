import 'package:movil_architect/core/config/app_config.dart';
import 'package:movil_architect/core/storage/secure_storage_service.dart';

class SettingsStorage {
  SettingsStorage({SecureStorageService? secureStorage})
      : _secureStorage = secureStorage ?? SecureStorageService();

  final SecureStorageService _secureStorage;

  /// Respaldo en memoria si el plugin nativo aún no está listo.
  String? _memoryUrl;
  bool? _memoryDarkMode;

  Future<String> getServerUrl() async {
    if (_memoryUrl != null && _memoryUrl!.isNotEmpty) {
      if (AppConfig.isLegacyDevUrl(_memoryUrl!)) {
        final next = AppConfig.defaultServerUrl();
        await saveServerUrl(next);
        return next;
      }
      return AppConfig.resolveForPlatform(_memoryUrl!);
    }

    try {
      final saved = await _secureStorage.getServerUrl();
      if (saved != null && saved.isNotEmpty) {
        final normalized = AppConfig.normalizeBaseUrl(saved);
        if (AppConfig.isLegacyDevUrl(normalized)) {
          final next = AppConfig.defaultServerUrl();
          await saveServerUrl(next);
          return next;
        }
        final resolved = AppConfig.resolveForPlatform(normalized);
        if (resolved != normalized) {
          await saveServerUrl(resolved);
          return resolved;
        }
        _memoryUrl = normalized;
        return _memoryUrl!;
      }
    } catch (_) {
      // MissingPluginException u otro fallo de plataforma: usar default.
    }

    return AppConfig.defaultServerUrl();
  }

  Future<void> saveServerUrl(String url) async {
    final normalized = AppConfig.resolveForPlatform(url);
    _memoryUrl = normalized;

    try {
      await _secureStorage.saveServerUrl(normalized);
    } catch (_) {
      // Se conserva al menos en memoria durante la sesión.
    }
  }

  Future<bool> isDarkModeEnabled() async {
    if (_memoryDarkMode != null) return _memoryDarkMode!;

    try {
      final saved = await _secureStorage.getDarkMode();
      if (saved != null) {
        _memoryDarkMode = saved;
        return saved;
      }
    } catch (_) {}

    return false;
  }

  Future<void> saveDarkMode(bool enabled) async {
    _memoryDarkMode = enabled;
    try {
      await _secureStorage.saveDarkMode(enabled);
    } catch (_) {}
  }
}
