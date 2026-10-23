import 'package:flutter/material.dart';
import 'package:movil_architect/core/app_services.dart';
import 'package:movil_architect/core/network/api_exception.dart';
import 'package:movil_architect/views/login/widgets/login_widgets.dart';

class ResetPasswordView extends StatefulWidget {
  const ResetPasswordView({super.key, this.initialToken});

  final String? initialToken;

  @override
  State<ResetPasswordView> createState() => _ResetPasswordViewState();
}

class _ResetPasswordViewState extends State<ResetPasswordView> {
  late final TextEditingController _token;
  final _password = TextEditingController();
  bool _loading = false;
  bool _valid = false;
  String? _error;
  String? _message;

  @override
  void initState() {
    super.initState();
    _token = TextEditingController(text: widget.initialToken ?? '');
    if (_token.text.isNotEmpty) {
      _validate();
    }
  }

  @override
  void dispose() {
    _token.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _validate() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final valid = await AppServices.instance.authService
          .validateResetToken(_token.text.trim());
      if (!mounted) return;
      setState(() {
        _valid = valid;
        if (!_valid) _error = 'El enlace no es válido o ya expiró.';
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _valid = false;
        _error = error.message;
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submit() async {
    if (_password.text.length < 8) {
      setState(() => _error = 'La contraseña debe tener al menos 8 caracteres.');
      return;
    }
    if (!_valid) {
      await _validate();
      if (!_valid || !mounted) return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await AppServices.instance.authService.resetPassword(
        token: _token.text,
        password: _password.text,
      );
      if (!mounted) return;
      setState(() => _message = 'Contraseña actualizada. Ya puedes iniciar sesión.');
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Restablecer contraseña'),
        backgroundColor: theme.scaffoldBackgroundColor,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
      ),
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LoginPillField(
              controller: _token,
              hint: 'TOKEN DEL CORREO',
              autocorrect: false,
            ),
            const SizedBox(height: 12),
            LoginPillField(
              controller: _password,
              hint: 'NUEVA CONTRASEÑA',
              obscureText: true,
              autocorrect: false,
            ),
            const SizedBox(height: 20),
            LoginPrimaryButton(
              label: 'Guardar contraseña',
              isLoading: _loading,
              onPressed: _submit,
            ),
            if (_message != null) ...[
              const SizedBox(height: 12),
              Text(_message!, style: const TextStyle(color: Color(0xFF1B8A5A))),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Colors.redAccent)),
            ],
          ],
        ),
      ),
    );
  }
}
