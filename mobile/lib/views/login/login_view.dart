import 'package:flutter/material.dart';
import 'package:movil_architect/controllers/login_controller.dart';
import 'package:movil_architect/core/app_services.dart';
import 'package:movil_architect/core/theme/app_colors.dart';
import 'package:movil_architect/core/utils/app_notifications.dart';
import 'package:movil_architect/views/auth/forgot_password_view.dart';
import 'package:movil_architect/views/auth/google_auth_view.dart';
import 'package:movil_architect/views/dashboard/dashboard_view.dart';
import 'package:movil_architect/views/guest/guest_view.dart';
import 'package:movil_architect/views/login/widgets/login_widgets.dart';
import 'package:movil_architect/views/register/register_view.dart';

class LoginView extends StatefulWidget {
  const LoginView({super.key});

  @override
  State<LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends State<LoginView> {
  late final LoginController _controller;

  @override
  void initState() {
    super.initState();
    _controller = LoginController()..loadGoogleAvailability();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _handleGoogle() async {
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => GoogleAuthView(
          startUrl: AppServices.instance.authService.googleAuthUrl(),
        ),
      ),
    );
    if (!mounted || result == null) return;
    if (result.startsWith('error:')) {
      AppNotifications.error(context, result.substring(6));
      return;
    }
    if (!await _controller.completeGoogle(result)) return;
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => const DashboardView()),
    );
  }

  Future<void> _handleLogin() async {
    if (!await _controller.login()) return;
    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => const DashboardView()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) {
          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(28, 8, 28, 28),
              physics: const BouncingScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Center(child: LoginAppMark()),
                  const SizedBox(height: 40),
                  Text(
                    'Iniciar sesión',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: colorScheme.onSurface,
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 32),
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
                    hint: 'CONTRASEÑA',
                    obscureText: _controller.obscurePassword,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _handleLogin(),
                    onChanged: (_) => _controller.clearError(),
                    suffix: GestureDetector(
                      onTap: _controller.toggleObscurePassword,
                      child: Icon(
                        _controller.obscurePassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        size: 20,
                        color: AppColors.muted,
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
                    label: 'Iniciar sesión',
                    isLoading: _controller.isLoading,
                    onPressed: _handleLogin,
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: TextButton(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const ForgotPasswordView(),
                          ),
                        );
                      },
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.muted,
                      ),
                      child: const Text('¿Olvidaste tu contraseña?'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Center(
                    child: TextButton(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const RegisterView(),
                          ),
                        );
                      },
                      style: TextButton.styleFrom(
                        foregroundColor: colorScheme.onSurface,
                      ),
                      child: const Text('Crear cuenta'),
                    ),
                  ),
                  const SizedBox(height: 28),
                  if (_controller.googleEnabled) ...[
                    const LoginSocialDivider(),
                    const SizedBox(height: 20),
                    LoginGoogleButton(onPressed: _handleGoogle),
                    const SizedBox(height: 16),
                  ],
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const GuestView(),
                        ),
                      );
                    },
                    style: TextButton.styleFrom(
                      foregroundColor: colorScheme.onSurface,
                    ),
                    child: const Text('Continuar sin cuenta'),
                  ),
                  const SizedBox(height: 16),
                  const LoginLegalFooter(),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
