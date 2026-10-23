import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:movil_architect/core/network/api_client.dart';
import 'package:movil_architect/core/network/api_exception.dart';
import 'package:movil_architect/core/storage/secure_storage_service.dart';
import 'package:movil_architect/models/auth_models.dart';
import 'package:movil_architect/services/push_notification_service.dart';

class AuthService extends ChangeNotifier {
  AuthService({
    required ApiClient apiClient,
    required SecureStorageService secureStorage,
  })  : _apiClient = apiClient,
        _secureStorage = secureStorage;

  final ApiClient _apiClient;
  final SecureStorageService _secureStorage;
  PushNotificationService? _push;

  UserModel? _currentUser;
  SubscriptionModel? _subscription;

  UserModel? get currentUser => _currentUser;
  SubscriptionModel? get subscription => _subscription;

  VoidCallback? onSessionExpired;

  void attachPush(PushNotificationService push) {
    _push = push;
  }

  Future<AuthResponse> login({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _apiClient.dio.post<Map<String, dynamic>>(
        '/api/auth/login',
        data: {'email': email.trim(), 'password': password},
      );
      final auth = AuthResponse.fromJson(response.data ?? {});
      await _persistSession(auth);
      await _push?.syncTokenWithBackend(force: true);
      return auth;
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<AuthResponse> register({
    required String email,
    required String password,
    String? fullName,
  }) async {
    try {
      final payload = <String, dynamic>{
        'email': email.trim(),
        'password': password,
      };
      final name = fullName?.trim();
      if (name != null && name.isNotEmpty) {
        payload['full_name'] = name;
      }

      final response = await _apiClient.dio.post<Map<String, dynamic>>(
        '/api/auth/register',
        data: payload,
      );
      final auth = AuthResponse.fromJson(response.data ?? {});
      await _persistSession(auth);
      await _push?.syncTokenWithBackend(force: true);
      return auth;
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<bool> hasToken() async {
    final token = await _secureStorage.getToken();
    return token != null && token.isNotEmpty;
  }

  Future<void> logout() async {
    try {
      await _push?.unregisterFromBackend();
    } catch (_) {}
    await _secureStorage.clearToken();
    _currentUser = null;
    _subscription = null;
    notifyListeners();
  }

  void handleUnauthorized() {
    _currentUser = null;
    _subscription = null;
    notifyListeners();
    onSessionExpired?.call();
  }

  Future<void> _persistSession(AuthResponse auth) async {
    await _secureStorage.saveToken(auth.accessToken);
    _currentUser = auth.user;
    _subscription = auth.subscription;
    notifyListeners();
  }

  void updateSession({required UserModel user, SubscriptionModel? subscription}) {
    _currentUser = user;
    _subscription = subscription;
    notifyListeners();
  }

  Future<void> completeOAuth(String accessToken) async {
    await _secureStorage.saveToken(accessToken);
    await _push?.syncTokenWithBackend(force: true);
  }

  Future<bool> isGoogleEnabled() async {
    try {
      final response = await _apiClient.dio.get<Map<String, dynamic>>(
        '/api/auth/google/enabled',
      );
      return response.data?['enabled'] == true;
    } on DioException {
      return false;
    }
  }

  String googleAuthUrl() {
    final base = _apiClient.dio.options.baseUrl;
    return '$base/api/auth/google';
  }

  Future<UserModel> updateProfileName(String fullName) async {
    try {
      final response = await _apiClient.dio.patch<Map<String, dynamic>>(
        '/api/auth/me',
        data: {'full_name': fullName.trim()},
      );
      final user = _userFromPayload(response.data);
      _currentUser = user;
      notifyListeners();
      return user;
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<UserModel> changePassword({
    required String newPassword,
    String? currentPassword,
  }) async {
    try {
      final response = await _apiClient.dio.post<Map<String, dynamic>>(
        '/api/auth/me/password',
        data: {
          'current_password': currentPassword,
          'new_password': newPassword,
        },
      );
      final user = _userFromPayload(response.data);
      _currentUser = user;
      notifyListeners();
      return user;
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<void> deleteAccount({String? password, String? confirmEmail}) async {
    try {
      await _apiClient.dio.delete<Map<String, dynamic>>(
        '/api/auth/me',
        data: {
          'password': ?password,
          'confirm_email': ?confirmEmail,
        },
      );
      await logout();
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<UserModel> uploadAvatar(File file) async {
    try {
      final response = await _apiClient.dio.post<Map<String, dynamic>>(
        '/api/auth/me/avatar',
        data: FormData.fromMap({
          'file': await MultipartFile.fromFile(
            file.path,
            filename: file.uri.pathSegments.last,
          ),
        }),
      );
      final user = _userFromPayload(response.data);
      _currentUser = user;
      notifyListeners();
      return user;
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<UserModel> deleteAvatar() async {
    try {
      final response = await _apiClient.dio.delete<Map<String, dynamic>>(
        '/api/auth/me/avatar',
      );
      final user = _userFromPayload(response.data);
      _currentUser = user;
      notifyListeners();
      return user;
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<void> forgotPassword(String email) async {
    try {
      await _apiClient.dio.post<Map<String, dynamic>>(
        '/api/auth/forgot-password',
        data: {'email': email.trim()},
      );
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<bool> validateResetToken(String token) async {
    try {
      final response = await _apiClient.dio.get<Map<String, dynamic>>(
        '/api/auth/reset-password/validate',
        queryParameters: {'token': token},
      );
      final data = response.data ?? {};
      return data['ok'] != false && data['valid'] != false;
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<void> resetPassword({
    required String token,
    required String password,
  }) async {
    try {
      await _apiClient.dio.post<Map<String, dynamic>>(
        '/api/auth/reset-password',
        data: {'token': token.trim(), 'password': password},
      );
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  UserModel _userFromPayload(Map<String, dynamic>? data) {
    final map = data ?? {};
    if (map['user'] is Map<String, dynamic>) {
      return UserModel.fromJson(map['user'] as Map<String, dynamic>);
    }
    if (map['user'] is Map) {
      return UserModel.fromJson(Map<String, dynamic>.from(map['user'] as Map));
    }
    return _currentUser ?? UserModel.fromJson(map);
  }
}
