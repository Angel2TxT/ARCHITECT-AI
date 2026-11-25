import 'package:flutter/material.dart';
import 'package:movil_architect/core/app_services.dart';
import 'package:movil_architect/core/network/api_exception.dart';
import 'package:movil_architect/services/auth_service.dart';

class RegisterController extends ChangeNotifier {
  RegisterController({AuthService? authService})
      : _authService = authService ?? AppServices.instance.authService;

  final AuthService _authService;

  final TextEditingController fullNameController = TextEditingController();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController confirmPasswordController =
      TextEditingController();

  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _isLoading = false;
  bool _requiresVerification = false;
  String _registeredEmail = '';
  String? _errorMessage;
  bool _disposed = false;

  bool get obscurePassword => _obscurePassword;
  bool get obscureConfirmPassword => _obscureConfirmPassword;
  bool get isLoading => _isLoading;
  bool get requiresVerification => _requiresVerification;
  String get registeredEmail => _registeredEmail;
  String? get errorMessage => _errorMessage;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void toggleObscurePassword() {
    _obscurePassword = !_obscurePassword;
    _notify();
  }

  void toggleObscureConfirmPassword() {
    _obscureConfirmPassword = !_obscureConfirmPassword;
    _notify();
  }

  bool _isValidEmail(String email) {
    if (RegExp(r'[<>/\s]').hasMatch(email)) return false;
    return RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$')
        .hasMatch(email);
  }

  String? _validateForm() {
    final fullName = fullNameController.text.trim();
    final email = emailController.text.trim();
    final password = passwordController.text;
    final confirm = confirmPasswordController.text;

    if (fullName.isEmpty) {
      return 'Ingresa tu nombre completo.';
    }
    if (fullName.length < 2) {
      return 'El nombre debe tener al menos 2 caracteres.';
    }
    if (RegExp(r"[<>/&;]").hasMatch(fullName) ||
        !RegExp(r"^[a-zA-ZáéíóúÁÉÍÓÚñÑüÜ\s'\-]+$").hasMatch(fullName)) {
      return 'El nombre solo puede contener letras, espacios, guiones y apóstrofes.';
    }
    if (email.isEmpty) {
      return 'Ingresa tu correo electrónico.';
    }
    if (!_isValidEmail(email)) {
      return 'Ingresa un correo electrónico válido (sin <, > o /).';
    }
    if (password.length < 8) {
      return 'La contraseña debe tener al menos 8 caracteres.';
    }
    if (confirm.isEmpty) {
      return 'Confirma tu contraseña.';
    }
    if (password != confirm) {
      return 'Las contraseñas no coinciden.';
    }
    return null;
  }

  Future<bool> register() async {
    final validationError = _validateForm();
    if (validationError != null) {
      _errorMessage = validationError;
      _notify();
      return false;
    }

    _isLoading = true;
    _errorMessage = null;
    _notify();

    try {
      final fullName = fullNameController.text.trim();
      final auth = await _authService.register(
        email: emailController.text.trim(),
        password: passwordController.text,
        fullName: fullName.isEmpty ? null : fullName,
      );
      _requiresVerification =
          auth.requiresVerification || auth.accessToken.isEmpty;
      _registeredEmail = auth.user.email;
      return !_disposed;
    } on ApiException catch (error) {
      _errorMessage = error.message;
      return false;
    } catch (_) {
      _errorMessage = 'No se pudo crear la cuenta.';
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
    fullNameController.dispose();
    emailController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();
    super.dispose();
  }
}
