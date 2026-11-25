import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patrol/patrol.dart';

import '../fixtures/test_data.dart';

/// Helper reutilizable para autenticar un usuario en la app móvil.
class LoginHelper {
  const LoginHelper._();

  static Future<void> waitForLoginScreen(PatrolIntegrationTester $) async {
    await _waitForAppReady($);

    if ($('Guardar y conectar').exists) {
      final urlField = $(TextField).first;
      await urlField.enterText(TestData.apiBaseUrl);
      await $('Guardar y conectar').tap();
      await $.pump(const Duration(milliseconds: 500));
      await _waitForAppReady($);
    }

    await $('Iniciar sesión').waitUntilVisible(
      timeout: const Duration(seconds: 25),
    );
  }

  static Future<void> ensureLoggedIn(
    PatrolIntegrationTester $, {
    String? email,
    String? password,
  }) async {
    final userEmail = (email ?? TestData.testEmail).trim();
    final userPassword = password ?? TestData.testPassword;

    if (userEmail.isEmpty || userPassword.isEmpty) {
      fail(
        'Faltan credenciales de prueba. Pasa --dart-define=TEST_EMAIL=... '
        'y --dart-define=TEST_PASSWORD=...',
      );
    }

    // Esperar a que termine el SplashView y aparezca LoginView, Dashboard o conexión.
    await _waitForAppReady($);

    // Si aparece la pantalla de configuración de servidor, guardar la URL de pruebas.
    if ($('Guardar y conectar').exists) {
      final urlField = $(TextField).first;
      await urlField.enterText(TestData.apiBaseUrl);
      await $('Guardar y conectar').tap();
      await $.pumpAndSettle();
      await _waitForAppReady($);
    }

    // Si ya hay sesión activa en Dashboard, no volver a iniciar sesión.
    if ($(Icons.menu_rounded).exists && !$('Iniciar sesión').exists) {
      return;
    }

    // Esperar al formulario de login real (hint 'CORREO ELECTRÓNICO' y 'CONTRASEÑA').
    await $('Iniciar sesión').waitUntilVisible();

    final textFields = $(TextField);
    expect(textFields, findsAtLeastNWidgets(2));

    await textFields.at(0).enterText(userEmail);
    await textFields.at(1).enterText(userPassword);
    await $.tester.testTextInput.receiveAction(TextInputAction.done);
    await $.pump();

    // Tocar el botón principal "Iniciar sesión" (último texto coincidente, debajo del título).
    await $('Iniciar sesión').last.tap();
    await $.pump(const Duration(milliseconds: 500));

    // Confirmar llegada al Dashboard (botón de menú del drawer).
    await $(Icons.menu_rounded).waitUntilVisible(
      timeout: const Duration(seconds: 25),
    );
    await $.pump(const Duration(milliseconds: 500));
  }

  static Future<void> _waitForAppReady(PatrolIntegrationTester $) async {
    final deadline = DateTime.now().add(const Duration(seconds: 45));
    while (DateTime.now().isBefore(deadline)) {
      await $.pump(const Duration(milliseconds: 300));
      if ($('Iniciar sesión').exists ||
          $(Icons.menu_rounded).exists ||
          $('Guardar y conectar').exists) {
        await $.pump(const Duration(milliseconds: 500));
        return;
      }
    }
    fail('La aplicación no mostró Login, Dashboard ni pantalla de servidor a tiempo.');
  }
}
