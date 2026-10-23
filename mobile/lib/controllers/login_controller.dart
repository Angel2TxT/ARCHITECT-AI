import 'package:flutter/material.dart';
import 'package:movil_architect/core/app_services.dart';
import 'package:movil_architect/core/network/api_exception.dart';
import 'package:movil_architect/models/user_credentials.dart';
import 'package:movil_architect/services/auth_service.dart';

class LoginController extends ChangeNotifier {
  LoginController({AuthService? authService})
      : _authService = authService ?? AppServices.instance.authService;

  final AuthService _authService;

  final TextEditingController emailController = TextEditingController(
    text: 'admin@architect.local',
  );
  final TextEditingController passwordController = TextEditingController(
    text: 'admin123',
  );

  bool _obscurePassword = true;
  bool _isLoading = false;
  bool _googleEnabled = false;
  String? _errorMessage;
  bool _disposed = false;

  bool get obscurePassword => _obscurePassword;
  bool get isLoading => _isLoading;
  bool get googleEnabled => _googleEnabled;
  String? get errorMessage => _errorMessage;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> loadGoogleAvailability() async {
    try {
      await AppServices.instance.apiClient.refreshBaseUrl();
      _googleEnabled = await _authService.isGoogleEnabled();
    } catch (_) {
      _googleEnabled = false;
    }
    _notify();
  }

  void toggleObscurePassword() {
    _obscurePassword = !_obscurePassword;
    _notify();
  }

  UserCredentials get credentials => UserCredentials(
        email: emailController.text,
        password: passwordController.text,
      );

  Future<bool> login() async {
    final user = credentials;

    if (!user.isValid) {
      _errorMessage = 'Ingresa correo y contraseña.';
      _notify();
      return false;
    }

    _isLoading = true;
    _errorMessage = null;
    _notify();

    try {
      await AppServices.instance.apiClient.refreshBaseUrl();
      await _authService.login(
        email: user.email,
        password: user.password,
      );
      return !_disposed;
    } on ApiException catch (error) {
      _errorMessage = error.message;
      return false;
    } catch (_) {
      _errorMessage = 'No se pudo iniciar sesión. Intenta de nuevo.';
      return false;
    } finally {
      _isLoading = false;
      _notify();
    }
  }

  Future<bool> completeGoogle(String accessToken) async {
    _isLoading = true;
    _errorMessage = null;
    _notify();
    try {
      await _authService.completeOAuth(accessToken);
      final me = await AppServices.instance.mobileApiService.me();
      _authService.updateSession(
        user: me.user,
        subscription: me.subscription,
      );
      return !_disposed;
    } on ApiException catch (error) {
      _errorMessage = error.message;
      return false;
    } catch (_) {
      _errorMessage = 'No se pudo completar el acceso con Google.';
      return false;
    } finally {
      _isLoading = false;
      _notify();
    }
  }

  void clearError() {
    if (_errorMessage == null) return;
    _errorMessage = null;
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }
}
