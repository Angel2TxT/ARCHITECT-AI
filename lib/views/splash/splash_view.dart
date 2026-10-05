import 'package:flutter/material.dart';
import 'package:movil_architect/controllers/splash_controller.dart';
import 'package:movil_architect/core/app_services.dart';
import 'package:movil_architect/core/config/app_config.dart';
import 'package:movil_architect/views/dashboard/dashboard_view.dart';
import 'package:movil_architect/views/login/login_view.dart';
import 'package:movil_architect/views/login/widgets/login_widgets.dart';

class SplashView extends StatefulWidget {
  const SplashView({super.key});

  @override
  State<SplashView> createState() => _SplashViewState();
}

class _SplashViewState extends State<SplashView> {
  late final SplashController _controller;
  late final TextEditingController _urlController;
  bool _navigating = false;
  bool _savingUrl = false;

  @override
  void initState() {
    super.initState();
    _controller = SplashController();
    _urlController = TextEditingController(
      text: AppServices.instance.apiClient.dio.options.baseUrl,
    );
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await _controller.bootstrap();
    if (!mounted || _navigating) return;

    final status = _controller.status;
    if (status == SplashStatus.readyDashboard) {
      _goTo(const DashboardView());
    } else if (status == SplashStatus.readyLogin) {
      _goTo(const LoginView());
    } else if (status == SplashStatus.serverError) {
      _urlController.text =
          AppServices.instance.apiClient.dio.options.baseUrl;
    }
  }

  Future<void> _saveServerAndRetry() async {
    final resolved = AppConfig.resolveForPlatform(_urlController.text.trim());
    if (resolved.isEmpty) return;

    setState(() => _savingUrl = true);
    try {
      await AppServices.instance.apiClient.setBaseUrl(resolved);
      _urlController.text = resolved;
      debugPrint('Splash server URL → $resolved');
      _navigating = false;
      await _bootstrap();
    } finally {
      if (mounted) setState(() => _savingUrl = false);
    }
  }

  void _goTo(Widget page) {
    if (_navigating || !mounted) return;
    _navigating = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => page),
      );
    });
  }

  @override
  void dispose() {
    _urlController.dispose();
    _controller.dispose();
    super.dispose();
  }

  Widget _splashContent() {
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset(
            'assets/icons/logo.png',
            width: 120,
            height: 120,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.medium,
          ),
          const SizedBox(height: 28),
          Text(
            'ARCHITECT',
            style: TextStyle(
              color: colorScheme.onSurface,
              fontSize: 14,
              fontWeight: FontWeight.w800,
              letterSpacing: 4,
            ),
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(
              strokeWidth: 2.4,
              color: colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  Widget _serverErrorContent() {
    final colorScheme = Theme.of(context).colorScheme;
    final message = _controller.errorMessage ??
        'No se pudo conectar al servidor';

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          children: [
            const SizedBox(height: 24),
            Icon(
              Icons.cloud_off,
              size: 56,
              color: colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colorScheme.onSurface,
                fontSize: 16,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'En teléfono físico usa la IP de tu PC, por ejemplo:\n'
              'http://192.168.0.104:8000\n'
              '(misma Wi‑Fi; no uses 10.0.2.2 ni localhost)',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: 13,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 20),
            LoginPillField(
              controller: _urlController,
              hint: 'URL DEL SERVIDOR',
              keyboardType: TextInputType.url,
              autocorrect: false,
            ),
            const SizedBox(height: 14),
            LoginPrimaryButton(
              label: 'Guardar y conectar',
              isLoading: _savingUrl,
              onPressed: _savingUrl ? null : _saveServerAndRetry,
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: _savingUrl ? null : _saveServerAndRetry,
              child: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) {
          if (_controller.status == SplashStatus.serverError) {
            return _serverErrorContent();
          }

          return _splashContent();
        },
      ),
    );
  }
}
