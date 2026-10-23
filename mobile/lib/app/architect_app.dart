import 'package:flutter/material.dart';
import 'package:movil_architect/core/app_services.dart';
import 'package:movil_architect/core/navigation/app_navigator.dart';
import 'package:movil_architect/core/theme/app_theme.dart';
import 'package:movil_architect/views/login/login_view.dart';
import 'package:movil_architect/views/splash/splash_view.dart';

class ArchitectApp extends StatefulWidget {
  const ArchitectApp({super.key});

  @override
  State<ArchitectApp> createState() => _ArchitectAppState();
}

class _ArchitectAppState extends State<ArchitectApp> {
  @override
  void initState() {
    super.initState();
    AppServices.instance.authService.onSessionExpired = () {
      appNavigatorKey.currentState?.pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: (_) => const LoginView()),
        (_) => false,
      );
    };
  }

  @override
  Widget build(BuildContext context) {
    final themeService = AppServices.instance.themeService;

    return ListenableBuilder(
      listenable: themeService,
      builder: (context, _) {
        return MaterialApp(
          title: 'Architect',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: themeService.themeMode,
          navigatorKey: appNavigatorKey,
          home: const SplashView(),
        );
      },
    );
  }
}
