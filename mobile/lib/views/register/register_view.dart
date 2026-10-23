import 'package:flutter/material.dart';
import 'package:movil_architect/controllers/register_controller.dart';
import 'package:movil_architect/core/theme/app_colors.dart';
import 'package:movil_architect/views/dashboard/dashboard_view.dart';
import 'package:movil_architect/views/login/widgets/login_widgets.dart';

class RegisterView extends StatefulWidget {
  const RegisterView({super.key});

  @override
  State<RegisterView> createState() => _RegisterViewState();
}

class _RegisterViewState extends State<RegisterView> {
  late final RegisterController _controller;

  @override
  void initState() {
    super.initState();
    _controller = RegisterController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _handleRegister() async {
    if (!await _controller.register()) return;
    if (!mounted) return;

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const DashboardView()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        iconTheme: IconThemeData(color: colorScheme.onSurface),
        title: Text(
          'Crear cuenta',
          style: TextStyle(
            color: colorScheme.onSurface,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) {
          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(28),
              physics: const BouncingScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Center(child: LoginAppMark()),
                  const SizedBox(height: 32),
                  Text(
                    'Regístrate',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: colorScheme.onSurface,
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 28),
                  LoginPillField(
                    controller: _controller.fullNameController,
                    hint: 'NOMBRE COMPLETO (OPCIONAL)',
                    textInputAction: TextInputAction.next,
                    autocorrect: false,
                    onChanged: (_) => _controller.clearError(),
                  ),
                  const SizedBox(height: 14),
                  LoginPillField(
                    controller: _controller.emailController,
                    hint: 'CORREO ELECTRÓNICO',
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    autocorrect: false,
                    onChanged: (_) => _controller.clearError(),
                  ),
                  const SizedBox(height: 14),
                  LoginPillField(
                    controller: _controller.passwordController,
                    hint: 'CONTRASEÑA (MÍN. 8)',
                    obscureText: _controller.obscurePassword,
                    textInputAction: TextInputAction.next,
                    onChanged: (_) => _controller.clearError(),
                    suffix: GestureDetector(
                      onTap: _controller.toggleObscurePassword,
                      child: Icon(
                        _controller.obscurePassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        size: 20,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  LoginPillField(
                    controller: _controller.confirmPasswordController,
                    hint: 'CONFIRMAR CONTRASEÑA',
                    obscureText: _controller.obscureConfirmPassword,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _handleRegister(),
                    onChanged: (_) => _controller.clearError(),
                    suffix: GestureDetector(
                      onTap: _controller.toggleObscureConfirmPassword,
                      child: Icon(
                        _controller.obscureConfirmPassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        size: 20,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  if (_controller.errorMessage != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      _controller.errorMessage!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.redAccent,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  LoginPrimaryButton(
                    label: 'Crear cuenta',
                    isLoading: _controller.isLoading,
                    onPressed: _handleRegister,
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: TextButton(
                      onPressed: _controller.isLoading
                          ? null
                          : () => Navigator.of(context).pop(),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.muted,
                      ),
                      child: const Text('¿Ya tienes cuenta? Inicia sesión'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
