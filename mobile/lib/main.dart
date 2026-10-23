import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:movil_architect/app/architect_app.dart';
import 'package:movil_architect/core/app_services.dart';
import 'package:movil_architect/firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  runApp(const _BootstrapApp());
}

class _BootstrapApp extends StatefulWidget {
  const _BootstrapApp();

  @override
  State<_BootstrapApp> createState() => _BootstrapAppState();
}

class _BootstrapAppState extends State<_BootstrapApp> {
  Object? _initError;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      await AppServices.instance.init();
      if (!mounted) return;
      setState(() {
        _ready = true;
        _initError = null;
      });
    } catch (error, stack) {
      debugPrint('App init failed: $error\n$stack');
      if (!mounted) return;
      setState(() => _initError = error);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_ready) {
      return const ArchitectApp();
    }

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFFF7F7F8),
        body: Center(
          child: _initError == null
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'No se pudo iniciar la app',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '$_initError',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.black54),
                      ),
                      const SizedBox(height: 20),
                      FilledButton(
                        onPressed: () {
                          setState(() => _initError = null);
                          _init();
                        },
                        child: const Text('Reintentar'),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}
