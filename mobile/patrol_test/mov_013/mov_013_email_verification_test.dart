import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movil_architect/main.dart' as app;
import 'package:patrol/patrol.dart';

import '../fixtures/test_data.dart';
import '../helpers/login_helper.dart';
import '../helpers/navigation_helper.dart';

void main() {
  patrolTest(
    'MOV-013: flujo de verificación de correo con código de 6 dígitos',
    ($) async {
      final password = TestData.testPassword;
      if (password.isEmpty || password.length < 8) {
        fail(
          'Se requiere --dart-define=TEST_PASSWORD=... con al menos 8 caracteres.',
        );
      }

      final ts = DateTime.now().millisecondsSinceEpoch % 1000000;
      final initialEmail = 'verif.patrol.$ts@gmail.com';
      final correctedEmail = 'verif.fixed.$ts@gmail.com';

      // 1. Iniciar la app y esperar pantalla de Login.
      await app.main();
      await $.pump();
      await LoginHelper.waitForLoginScreen($);

      // 2. Navegar a Crear cuenta y registrar usuario nuevo.
      await $('Crear cuenta').tap();
      await $('Regístrate').waitUntilVisible(
        timeout: const Duration(seconds: 15),
      );

      final fields = $(TextField);
      expect(fields, findsAtLeastNWidgets(4));

      await fields.at(0).enterText('Usuario Verificacion');
      await fields.at(1).enterText(initialEmail);
      await fields.at(2).enterText(password);
      await fields.at(3).enterText(password);
      await $.tester.testTextInput.receiveAction(TextInputAction.done);
      await $.pump(const Duration(milliseconds: 300));

      await $(FilledButton).containing($('Crear cuenta')).scrollTo();
      await $(FilledButton).containing($('Crear cuenta')).tap();

      // 3. Verificar llegada a la pantalla de verificación.
      await $('Verifica tu correo').waitUntilVisible(
        timeout: const Duration(seconds: 25),
      );
      expect(
        $(const ValueKey('verify_email_label')),
        findsOneWidget,
        reason: 'Debe mostrarse el correo pendiente de verificación.',
      );
      expect(
        $(initialEmail),
        findsOneWidget,
        reason: 'El correo mostrado debe coincidir con el registrado.',
      );
      expect(
        $(const ValueKey('verify_resend_button')),
        findsOneWidget,
        reason: 'Debe existir el botón de reenvío con temporizador.',
      );

      await NavigationHelper.saveEvidenceScreenshot(
        $,
        'mov013_01_verify_screen',
      );

      // 4. Probar código incorrecto de 6 dígitos.
      await $(const ValueKey('verify_code_field')).enterText('000000');
      await $.tester.testTextInput.receiveAction(TextInputAction.done);
      await $.pump(const Duration(milliseconds: 200));

      await $(const ValueKey('verify_submit_button')).tap();
      await $(const ValueKey('verify_error_text')).waitUntilVisible(
        timeout: const Duration(seconds: 15),
      );
      expect(
        $('Verifica tu correo'),
        findsOneWidget,
        reason: 'Un código incorrecto no debe activar ni salir de verificación.',
      );

      await NavigationHelper.saveEvidenceScreenshot(
        $,
        'mov013_02_invalid_code',
      );

      // 5. Probar corrección de correo electrónico.
      await $(const ValueKey('verify_change_email_button')).scrollTo();
      await $(const ValueKey('verify_change_email_button')).tap();
      await $(const ValueKey('verify_new_email_field')).waitUntilVisible(
        timeout: const Duration(seconds: 10),
      );

      await $(const ValueKey('verify_new_email_field')).enterText(correctedEmail);
      await $(const ValueKey('verify_confirm_password_field')).enterText(password);
      await $(const ValueKey('verify_save_email_button')).tap();

      await $(correctedEmail).waitUntilVisible(
        timeout: const Duration(seconds: 20),
      );
      expect(
        $(correctedEmail),
        findsOneWidget,
        reason: 'El correo actualizado debe reflejarse en pantalla.',
      );

      await NavigationHelper.saveEvidenceScreenshot(
        $,
        'mov013_03_email_corrected',
      );
    },
  );
}
