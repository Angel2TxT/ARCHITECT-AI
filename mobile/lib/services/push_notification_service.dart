import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:movil_architect/core/navigation/app_navigator.dart';
import 'package:movil_architect/core/network/api_client.dart';
import 'package:movil_architect/core/storage/secure_storage_service.dart';
import 'package:movil_architect/core/utils/app_notifications.dart';
import 'package:movil_architect/views/home_projects/home_project_detail_view.dart';
import 'package:movil_architect/views/home_projects/home_projects_list_view.dart';

/// Handler en isolate de background (debe ser top-level).
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint(
    'FCM background: ${message.messageId} kind=${message.data['kind']}',
  );
}

class PushNotificationService {
  PushNotificationService({
    required ApiClient apiClient,
    required SecureStorageService secureStorage,
  })  : _apiClient = apiClient,
        _secureStorage = secureStorage;

  final ApiClient _apiClient;
  final SecureStorageService _secureStorage;
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  bool _started = false;
  String? _currentToken;

  Future<void> start() async {
    if (_started || kIsWeb || !(Platform.isAndroid || Platform.isIOS)) {
      return;
    }
    _started = true;

    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    await _messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );
    debugPrint('FCM permission: ${settings.authorizationStatus}');

    FirebaseMessaging.onMessage.listen(_onForegroundMessage);
    FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationOpen);

    final initial = await _messaging.getInitialMessage();
    if (initial != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _handleNotificationOpen(initial);
      });
    }

    _messaging.onTokenRefresh.listen((token) async {
      _currentToken = token;
      await _secureStorage.saveFcmToken(token);
      await syncTokenWithBackend(force: true);
    });
  }

  /// Pide token local y lo registra en el backend (requiere sesión JWT).
  Future<void> syncTokenWithBackend({bool force = false}) async {
    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) return;

    try {
      final jwt = await _secureStorage.getToken();
      if (jwt == null || jwt.isEmpty) return;

      final token = await _messaging.getToken();
      if (token == null || token.isEmpty) {
        debugPrint('FCM: sin token de dispositivo');
        return;
      }

      final previous = await _secureStorage.getFcmToken();
      if (!force && previous == token && _currentToken == token) {
        return;
      }

      _currentToken = token;
      await _secureStorage.saveFcmToken(token);

      await _apiClient.dio.post<Map<String, dynamic>>(
        '/api/mobile/device-token',
        data: {
          'token': token,
          'platform': Platform.isIOS ? 'ios' : 'android',
        },
      );
      debugPrint('FCM: token registrado en backend');
    } catch (error) {
      debugPrint('FCM sync error: $error');
    }
  }

  /// Quita el token del backend al cerrar sesión.
  Future<void> unregisterFromBackend() async {
    try {
      final token = _currentToken ?? await _secureStorage.getFcmToken();
      if (token == null || token.isEmpty) return;

      await _apiClient.dio.delete<Map<String, dynamic>>(
        '/api/mobile/device-token',
        data: {
          'token': token,
          'platform': Platform.isIOS ? 'ios' : 'android',
        },
      );
    } catch (error) {
      debugPrint('FCM unregister error: $error');
    } finally {
      _currentToken = null;
      await _secureStorage.clearFcmToken();
    }
  }

  void _onForegroundMessage(RemoteMessage message) {
    final title = message.notification?.title ??
        message.data['title']?.toString() ??
        'ARCHITECT';
    final body = message.notification?.body ??
        message.data['body']?.toString() ??
        '';
    final ctx = appNavigatorKey.currentContext;
    if (ctx != null && ctx.mounted) {
      final text = body.isEmpty ? title : '$title — $body';
      AppNotifications.success(ctx, text);
    }
  }

  void _handleNotificationOpen(RemoteMessage message) {
    final data = message.data;
    final kind = data['kind']?.toString() ?? '';
    final entityType = data['entity_type']?.toString() ?? '';
    final entityId = data['entity_id']?.toString() ?? '';
    final link = data['link']?.toString() ?? '';

    debugPrint(
      'FCM open kind=$kind entity=$entityType/$entityId link=$link',
    );

    final nav = appNavigatorKey.currentState;
    if (nav == null) return;

    final projectId = _extractHomeProjectId(
      entityType: entityType,
      entityId: entityId,
      link: link,
      kind: kind,
    );

    if (projectId != null && projectId.isNotEmpty) {
      nav.push(
        MaterialPageRoute<void>(
          builder: (_) => HomeProjectDetailView(projectId: projectId),
        ),
      );
      return;
    }

    if (kind.startsWith('home_') || link.contains('home_project')) {
      nav.push(
        MaterialPageRoute<void>(
          builder: (_) => const HomeProjectsListView(),
        ),
      );
    }
  }

  String? _extractHomeProjectId({
    required String entityType,
    required String entityId,
    required String link,
    required String kind,
  }) {
    if (entityType == 'home_project' && entityId.isNotEmpty) {
      return entityId;
    }
    final fromLink = RegExp(r'home_project=([^&]+)').firstMatch(link);
    if (fromLink != null) return Uri.decodeComponent(fromLink.group(1)!);
    if (kind.startsWith('home_') && entityId.isNotEmpty) return entityId;
    return null;
  }
}
