import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:movil_architect/core/app_services.dart';
import 'package:movil_architect/core/network/api_exception.dart';
import 'package:movil_architect/core/theme/app_colors.dart';
import 'package:movil_architect/core/utils/app_notifications.dart';
import 'package:movil_architect/views/dashboard/dashboard_view.dart';
import 'package:movil_architect/views/login/login_view.dart';
import 'package:movil_architect/views/login/widgets/login_widgets.dart';

class VerifyEmailView extends StatefulWidget {
  const VerifyEmailView({
    super.key,
    required this.email,
    this.initialCooldownSeconds = 60,
  });

  final String email;
  final int initialCooldownSeconds;

  @override
  State<VerifyEmailView> createState() => _VerifyEmailViewState();
}

class _VerifyEmailViewState extends State<VerifyEmailView> {
  final TextEditingController _codeController = TextEditingController();
  late String _email;
  int _cooldownSeconds = 0;
  Timer? _timer;
  bool _isSubmitting = false;
  bool _isResending = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _email = widget.email.trim().toLowerCase();
    _startCooldown(widget.initialCooldownSeconds);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _codeController.dispose();
    super.dispose();
  }

  void _startCooldown(int seconds) {
    _timer?.cancel();
    if (seconds <= 0) {
      if (mounted) setState(() => _cooldownSeconds = 0);
      return;
    }
    setState(() => _cooldownSeconds = seconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_cooldownSeconds <= 1) {
        timer.cancel();
        setState(() => _cooldownSeconds = 0);
      } else {
        setState(() => _cooldownSeconds--);
      }
    });
  }

  Future<void> _handleVerify() async {
    final code = _codeController.text.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      setState(() {
        _errorMessage = 'Ingresa el código numérico de 6 dígitos.';
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      await AppServices.instance.apiClient.refreshBaseUrl();
      await AppServices.instance.authService.verifyEmail(
        email: _email,
        code: code,
      );
      if (!mounted) return;
      AppNotifications.success(context, 'Correo verificado correctamente');
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: (_) => const DashboardView()),
        (_) => false,
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = error.message);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'No se pudo verificar el código. Intenta de nuevo.';
      });
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _handleResend() async {
    if (_cooldownSeconds > 0 || _isResending) return;

    setState(() {
      _isResending = true;
      _errorMessage = null;
    });

    try {
      await AppServices.instance.apiClient.refreshBaseUrl();
      final cooldown = await AppServices.instance.authService
          .resendVerificationCode(email: _email);
      if (!mounted) return;
      _startCooldown(cooldown);
      AppNotifications.success(
        context,
        'Enviamos un nuevo código a $_email',
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = error.message);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'No se pudo reenviar el código. Intenta más tarde.';
      });
    } finally {
      if (mounted) setState(() => _isResending = false);
    }
  }

  Future<void> _openChangeEmailDialog() async {
    final newEmailController = TextEditingController(text: _email);
    final passwordController = TextEditingController();
    String? dialogError;
    bool saving = false;

    final updatedEmail = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Corregir correo electrónico'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Ingresa tu correo correcto y tu contraseña para enviarte un nuevo código.',
                    style: TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    key: const ValueKey('verify_new_email_field'),
                    controller: newEmailController,
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                        RegExp(r'[a-zA-Z0-9@._+-]'),
                      ),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Nuevo correo electrónico',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const ValueKey('verify_confirm_password_field'),
                    controller: passwordController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Contraseña de la cuenta',
                    ),
                  ),
                  if (dialogError != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      dialogError!,
                      style: const TextStyle(
                        color: Colors.redAccent,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed:
                      saving ? null : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  key: const ValueKey('verify_save_email_button'),
                  onPressed: saving
                      ? null
                      : () async {
                          final nextEmail = newEmailController.text.trim();
                          final password = passwordController.text;
                          if (!RegExp(
                            r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
                          ).hasMatch(nextEmail)) {
                            setDialogState(() {
                              dialogError = 'Ingresa un correo válido.';
                            });
                            return;
                          }
                          if (password.isEmpty) {
                            setDialogState(() {
                              dialogError = 'Ingresa tu contraseña.';
                            });
                            return;
                          }
                          setDialogState(() {
                            saving = true;
                            dialogError = null;
                          });
                          try {
                            final saved = await AppServices
                                .instance.authService
                                .updateUnverifiedEmail(
                              currentEmail: _email,
                              newEmail: nextEmail,
                              password: password,
                            );
                            if (dialogContext.mounted) {
                              Navigator.of(dialogContext).pop(saved);
                            }
                          } on ApiException catch (error) {
                            setDialogState(() {
                              saving = false;
                              dialogError = error.message;
                            });
                          } catch (_) {
                            setDialogState(() {
                              saving = false;
                              dialogError = 'No se pudo actualizar el correo.';
                            });
                          }
                        },
                  child: saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Actualizar'),
                ),
              ],
            );
          },
        );
      },
    );

    newEmailController.dispose();
    passwordController.dispose();

    if (!mounted || updatedEmail == null) return;
    setState(() {
      _email = updatedEmail;
      _codeController.clear();
      _errorMessage = null;
    });
    _startCooldown(60);
    AppNotifications.success(
      context,
      'Correo actualizado. Enviamos un nuevo código a $_email',
    );
  }

  Future<void> _backToLogin() async {
    await AppServices.instance.authService.clearPendingVerificationEmail();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const LoginView()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(28, 12, 28, 28),
          physics: const BouncingScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Center(child: LoginAppMark()),
              const SizedBox(height: 32),
              Text(
                'Verifica tu correo',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: colorScheme.onSurface,
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Enviamos un código de 6 dígitos a:',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.muted,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _email,
                key: const ValueKey('verify_email_label'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: colorScheme.onSurface,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'El código expira en 5 minutos y es de un solo uso.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.muted,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 28),
              LoginPillField(
                key: const ValueKey('verify_code_field'),
                controller: _codeController,
                hint: 'CÓDIGO DE 6 DÍGITOS',
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.done,
                autocorrect: false,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(6),
                ],
                onChanged: (_) {
                  if (_errorMessage != null) {
                    setState(() => _errorMessage = null);
                  }
                },
                onSubmitted: (_) => _handleVerify(),
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 12),
                Text(
                  _errorMessage!,
                  key: const ValueKey('verify_error_text'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.redAccent,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
              const SizedBox(height: 22),
              LoginPrimaryButton(
                key: const ValueKey('verify_submit_button'),
                label: 'Verificar cuenta',
                isLoading: _isSubmitting,
                onPressed: _handleVerify,
              ),
              const SizedBox(height: 16),
              OutlinedButton(
                key: const ValueKey('verify_resend_button'),
                onPressed:
                    (_cooldownSeconds > 0 || _isResending) ? null : _handleResend,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(28),
                  ),
                ),
                child: _isResending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(
                        _cooldownSeconds > 0
                            ? 'Reenviar código en ${_cooldownSeconds}s'
                            : 'Reenviar código',
                      ),
              ),
              const SizedBox(height: 12),
              TextButton(
                key: const ValueKey('verify_change_email_button'),
                onPressed: _openChangeEmailDialog,
                child: const Text('¿Escribiste mal tu correo? Corregir'),
              ),
              TextButton(
                key: const ValueKey('verify_back_to_login_button'),
                onPressed: _backToLogin,
                child: const Text(
                  'Volver a iniciar sesión',
                  style: TextStyle(color: AppColors.muted),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
