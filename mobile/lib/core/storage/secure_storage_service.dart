import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStorageService {
  SecureStorageService({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  static const _tokenKey = 'access_token';
  static const _serverUrlKey = 'server_base_url';
  static const _darkModeKey = 'dark_mode_enabled';
  static const _pinnedChatsKey = 'pinned_chat_ids';
  static const _pinnedHomeProjectsKey = 'pinned_home_project_ids';
  static const _fcmTokenKey = 'fcm_device_token';

  final FlutterSecureStorage _storage;

  Future<void> saveToken(String token) =>
      _storage.write(key: _tokenKey, value: token);

  Future<String?> getToken() => _storage.read(key: _tokenKey);

  Future<void> clearToken() => _storage.delete(key: _tokenKey);

  Future<void> saveFcmToken(String token) =>
      _storage.write(key: _fcmTokenKey, value: token);

  Future<String?> getFcmToken() => _storage.read(key: _fcmTokenKey);

  Future<void> clearFcmToken() => _storage.delete(key: _fcmTokenKey);

  Future<void> saveServerUrl(String url) =>
      _storage.write(key: _serverUrlKey, value: url);

  Future<String?> getServerUrl() => _storage.read(key: _serverUrlKey);

  Future<void> saveDarkMode(bool enabled) => _storage.write(
        key: _darkModeKey,
        value: enabled ? '1' : '0',
      );

  Future<bool?> getDarkMode() async {
    final value = await _storage.read(key: _darkModeKey);
    if (value == null) return null;
    return value == '1' || value.toLowerCase() == 'true';
  }

  Future<List<String>> getPinnedChatIds() async {
    final value = await _storage.read(key: _pinnedChatsKey);
    if (value == null || value.isEmpty) return [];
    return value.split(',').where((id) => id.isNotEmpty).toList();
  }

  Future<void> savePinnedChatIds(List<String> ids) => _storage.write(
        key: _pinnedChatsKey,
        value: ids.join(','),
      );

  Future<List<String>> getPinnedHomeProjectIds() async {
    final value = await _storage.read(key: _pinnedHomeProjectsKey);
    if (value == null || value.isEmpty) return [];
    return value.split(',').where((id) => id.isNotEmpty).toList();
  }

  Future<void> savePinnedHomeProjectIds(List<String> ids) => _storage.write(
        key: _pinnedHomeProjectsKey,
        value: ids.join(','),
      );
}
