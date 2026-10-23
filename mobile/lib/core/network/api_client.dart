import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:movil_architect/core/storage/secure_storage_service.dart';
import 'package:movil_architect/core/storage/settings_storage.dart';

class ApiClient {
  ApiClient({
    required SettingsStorage settingsStorage,
    required SecureStorageService secureStorage,
    Dio? dio,
  })  : _settingsStorage = settingsStorage,
        _secureStorage = secureStorage,
        _dio = dio ?? Dio() {
    _dio.options
      ..connectTimeout = const Duration(seconds: 20)
      ..receiveTimeout = const Duration(minutes: 3)
      ..sendTimeout = const Duration(minutes: 3)
      ..headers = {
        'Accept': 'application/json',
        // Evita el interstitial HTML de ngrok free en clientes no-browser.
        'ngrok-skip-browser-warning': 'true',
      };

    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await _secureStorage.getToken();
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          // Reafirmar en cada request (por si se limpia el header).
          options.headers['ngrok-skip-browser-warning'] ??= 'true';
          handler.next(options);
        },
        onError: (error, handler) async {
          if (error.response?.statusCode == 401 &&
              !_isAuthCredentialRequest(error.requestOptions)) {
            await _secureStorage.clearToken();
            onUnauthorized?.call();
          }
          handler.next(error);
        },
      ),
    );

    if (kDebugMode) {
      _dio.interceptors.add(
        LogInterceptor(
          request: true,
          requestHeader: false,
          requestBody: false,
          responseHeader: false,
          responseBody: false,
          error: true,
          logPrint: (object) => debugPrint(object.toString()),
        ),
      );
    }
  }

  final SettingsStorage _settingsStorage;
  final SecureStorageService _secureStorage;
  final Dio _dio;

  VoidCallback? onUnauthorized;

  Dio get dio => _dio;

  static bool _isAuthCredentialRequest(RequestOptions options) {
    final path = options.path;
    final method = options.method.toUpperCase();
    if (path.contains('/login') ||
        path.contains('/register') ||
        path.contains('/forgot-password') ||
        path.contains('/reset-password') ||
        path.contains('/auth/google') ||
        path.contains('/auth/me/password')) {
      return true;
    }
    if (method == 'DELETE' && path.contains('/auth/me')) return true;
    return false;
  }

  Future<void> refreshBaseUrl() async {
    final url = await _settingsStorage.getServerUrl();
    _dio.options.baseUrl = url;
  }

  /// Cambia la URL en memoria sin guardarla (p. ej. al probar conexión).
  void applyBaseUrl(String url) {
    _dio.options.baseUrl = url;
  }

  Future<void> setBaseUrl(String url) async {
    await _settingsStorage.saveServerUrl(url);
    _dio.options.baseUrl = url;
  }
}
