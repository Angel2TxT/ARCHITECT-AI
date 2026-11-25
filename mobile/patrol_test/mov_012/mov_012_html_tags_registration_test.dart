import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movil_architect/main.dart' as app;
import 'package:patrol/patrol.dart';

import '../fixtures/test_data.dart';
import '../helpers/login_helper.dart';
import '../helpers/navigation_helper.dart';

void main() {
  patrolTest(
    'MOV-012: registro de nombre y correo con etiquetas HTML',
    ($) async {
      final password = TestData.testPassword;
      if (password.isEmpty || password.length < 8) {
        fail(
          'Se requiere --dart-define=TEST_PASSWORD=... con al menos 8 caracteres.',
        );
      }

      const htmlName = '<b>prueba</b>';
      final uniqueSuffix = DateTime.now().millisecondsSinceEpoch % 100000;
      final htmlEmail = '<b>prueba</b>$uniqueSuffix@gmail.com';

      // 1. Iniciar la app y esperar pantalla de Login.
      await app.main();
      await $.pump();
      await LoginHelper.waitForLoginScreen($);

      // 2. Navegar a Crear cuenta.
      await $('Crear cuenta').tap();
      await $('Regístrate').waitUntilVisible(
        timeout: const Duration(seconds: 15),
      );

      // 3-7. Localizar campos e introducir nombre y correo con etiquetas HTML.
      final fields = $(TextField);
      expect(
        fields,
        findsAtLeastNWidgets(4),
        reason: 'El formulario de registro debe mostrar 4 campos de texto.',
      );

      await fields.at(0).enterText(htmlName);
      await fields.at(1).enterText(htmlEmail);
      await fields.at(2).enterText(password);
      await fields.at(3).enterText(password);
      await $.tester.testTextInput.receiveAction(TextInputAction.done);
      await $.pump(const Duration(milliseconds: 400));

      // Verificar qué valor quedó realmente en los campos tras inputFormatters.
      final enteredName = $.tester.widget<TextField>(fields.at(0)).controller?.text ?? '';
      final enteredEmail = $.tester.widget<TextField>(fields.at(1)).controller?.text ?? '';
      debugPrint('MOV012_FORM_NAME:$enteredName');
      debugPrint('MOV012_FORM_EMAIL:$enteredEmail');

      await NavigationHelper.saveEvidenceScreenshot(
        $,
        'mov012_01_formulario_registro',
      );

      // 8. Presionar el botón de registro "Crear cuenta".
      await $(FilledButton).containing($('Crear cuenta')).scrollTo();
      await $(FilledButton).containing($('Crear cuenta')).tap();
      await $.pump(const Duration(milliseconds: 500));

      // 9. Esperar respuesta: o mensaje de validación o llegada al Dashboard.
      final outcome = await _waitForRegisterOutcome($);
      debugPrint('MOV012_REGISTER_OUTCOME:$outcome');

      if (outcome == _RegisterOutcome.stayedOnRegister) {
        await NavigationHelper.saveEvidenceScreenshot(
          $,
          'mov012_02_validacion_registro',
        );
        // La app rechazó el registro; verificar que muestre mensaje de validación y no navegue.
        final hasValidationMessage = $(Text).evaluate().any((el) {
          final w = el.widget as Text;
          return w.style?.color == Colors.redAccent &&
              (w.data ?? '').trim().isNotEmpty;
        });
        expect(
          hasValidationMessage,
          isTrue,
          reason:
              'La pantalla de registro debe mostrar un mensaje de validación al rechazar etiquetas HTML.',
        );
        expect(
          $('Regístrate'),
          findsOneWidget,
          reason: 'Debe permanecer en la pantalla de registro cuando los datos son inválidos.',
        );
        return;
      }

      // 10. Si permitió crear la cuenta, navegar hasta el Perfil.
      await $(Icons.menu_rounded).waitUntilVisible(
        timeout: const Duration(seconds: 20),
      );
      await $(Icons.menu_rounded).tap();
      await $.pump(const Duration(milliseconds: 600));

      // Abrir Settings desde el botón circular del footer del drawer.
      final settingsButton = $(Drawer).$(InkWell).last;
      await settingsButton.waitUntilVisible(
        timeout: const Duration(seconds: 10),
      );
      await settingsButton.tap();
      await $.pump(const Duration(milliseconds: 600));

      await $('Perfil').waitUntilVisible(timeout: const Duration(seconds: 10));
      await $('Perfil').tap();
      await $('DATOS DE LA CUENTA').waitUntilVisible(
        timeout: const Duration(seconds: 15),
      );
      await $.pump(const Duration(milliseconds: 500));

      // 11-12. Capturar evidencia del perfil y verificar nombre y correo.
      await NavigationHelper.saveEvidenceScreenshot(
        $,
        'mov012_03_perfil_registrado',
      );

      final profileFields = $(TextField);
      expect(profileFields, findsAtLeastNWidgets(2));
      final profileName =
          $.tester.widget<TextField>(profileFields.at(0)).controller?.text ?? '';
      final profileEmail =
          $.tester.widget<TextField>(profileFields.at(1)).controller?.text ?? '';

      debugPrint('MOV012_PROFILE_NAME:$profileName');
      debugPrint('MOV012_PROFILE_EMAIL:$profileEmail');

      // Criterio de evaluación: no debe aceptar/almacenar etiquetas HTML en nombre ni correo.
      expect(
        profileName.contains('<') || profileName.contains('>'),
        isFalse,
        reason:
            'El perfil muestra etiquetas HTML sin rechazar ni sanitizar en el nombre: "$profileName".',
      );
      expect(
        profileEmail.contains('<') || profileEmail.contains('>'),
        isFalse,
        reason:
            'El perfil muestra etiquetas HTML sin rechazar ni sanitizar en el correo: "$profileEmail".',
      );
    },
  );
}

enum _RegisterOutcome { navigatedToDashboard, stayedOnRegister }

Future<_RegisterOutcome> _waitForRegisterOutcome(
  PatrolIntegrationTester $,
) async {
  final deadline = DateTime.now().add(const Duration(seconds: 25));
  while (DateTime.now().isBefore(deadline)) {
    await $.pump(const Duration(milliseconds: 300));
    if ($(Icons.menu_rounded).exists && !$('Regístrate').exists) {
      return _RegisterOutcome.navigatedToDashboard;
    }
    if ($('Regístrate').exists) {
      // Si hay un mensaje de error visible (color redAccent) o dejó de cargar tras intentar enviar.
      final hasErrorText = $(Text).evaluate().any((el) {
        final w = el.widget as Text;
        return w.style?.color == Colors.redAccent;
      });
      if (hasErrorText) {
        return _RegisterOutcome.stayedOnRegister;
      }
    }
  }
  return _RegisterOutcome.stayedOnRegister;
}
