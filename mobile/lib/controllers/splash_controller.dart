import 'package:flutter/material.dart';
import 'package:movil_architect/core/app_services.dart';
import 'package:movil_architect/core/network/api_exception.dart';
import 'package:movil_architect/services/auth_service.dart';
import 'package:movil_architect/services/mobile_api_service.dart';
import 'package:movil_architect/services/push_notification_service.dart';

enum SplashStatus { loading, readyDashboard, readyLogin, serverError }

class SplashController extends ChangeNotifier {
  SplashController({
    AuthService? authService,
    MobileApiService? mobileApiService,
    PushNotificationService? pushNotificationService,
  })  : _authService = authService ?? AppServices.instance.authService,
        _mobileApiService =
            mobileApiService ?? AppServices.instance.mobileApiService,
        _pushNotificationService = pushNotificationService;

  final AuthService _authService;
  final MobileApiService _mobileApiService;
  final PushNotificationService? _pushNotificationService;

  SplashStatus _status = SplashStatus.loading;
  String? _errorMessage;
  bool _disposed = false;

  SplashStatus get status => _status;
  String? get errorMessage => _errorMessage;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  Future<void> bootstrap() async {
    _status = SplashStatus.loading;
    _errorMessage = null;
    _notify();

    final previousSessionHandler = _authService.onSessionExpired;
    _authService.onSessionExpired = null;

    try {
      if (AppServices.instance.isInitialized) {
        debugPrint(
          'Splash health → ${AppServices.instance.apiClient.dio.options.baseUrl}/api/health',
        );
      }
      final health = await _mobileApiService.health();
      debugPrint('Splash health ok=${health.ok} version=${health.version}');
      if (!health.ok) {
        _status = SplashStatus.serverError;
        _errorMessage = 'El servidor respondió pero no está listo.';
        _notify();
        return;
      }

      final hasToken = await _authService.hasToken();
      if (!hasToken) {
        _status = SplashStatus.readyLogin;
        _notify();
        return;
      }

      try {
        final me = await _mobileApiService.me();
        _authService.updateSession(
          user: me.user,
          subscription: me.subscription,
        );
        final push = _pushNotificationService ??
            (AppServices.instance.isInitialized
                ? AppServices.instance.pushNotificationService
                : null);
        await push?.syncTokenWithBackend(force: true);
        _status = SplashStatus.readyDashboard;
      } on ApiException catch (error) {
        await _authService.logout();
        if (error.isOffline) {
          _status = SplashStatus.serverError;
          _errorMessage = error.message;
        } else {
          // Token inválido o el backend falló al cargar el perfil.
          _status = SplashStatus.readyLogin;
        }
      }
    } on ApiException catch (error) {
      debugPrint(
        'Splash ApiException status=${error.statusCode} offline=${error.isOffline} ${error.message}',
      );
      _status = SplashStatus.serverError;
      _errorMessage = error.message;
    } catch (error) {
      debugPrint('Splash error: $error');
      _status = SplashStatus.serverError;
      _errorMessage = 'No se pudo conectar al servidor.';
    } finally {
      _authService.onSessionExpired = previousSessionHandler;
    }

    _notify();
  }
}
