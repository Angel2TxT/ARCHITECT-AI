import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movil_architect/main.dart' as app;
import 'package:patrol/patrol.dart';

import '../fixtures/test_data.dart';
import '../helpers/login_helper.dart';
import '../helpers/navigation_helper.dart';

void main() {
  patrolTest(
    'MOV-006: cambiar estado de apartado Necesidades del cliente de Pendiente a En progreso y verificar persistencia',
    ($) async {
      // 1. Iniciar la app en el emulador Android.
      await app.main();
      await $.pump();

      // 2. Iniciar sesión con la cuenta de cliente de prueba.
      await LoginHelper.ensureLoggedIn($);

      // 3-5. Ir a Proyectos -> UTS -> Necesidades del cliente.
      await NavigationHelper.openHomeProjectsList($);
      await NavigationHelper.openProject($, projectName: TestData.projectName);
      await NavigationHelper.openSection($, sectionTitle: TestData.sectionTitle);

      final statusRow = $(Row).containing($('Cambiar estado'));

      // 6. Verificar estado inicial "Pendiente" en la píldora del apartado.
      expect(statusRow.$(TestData.initialStatusLabel), findsOneWidget);
      await NavigationHelper.saveEvidenceScreenshot($, '01_estado_inicial_pendiente');

      // 7-8. Pulsar "Cambiar estado" y esperar selector "Estado del apartado".
      await $('Cambiar estado').tap();
      await $.pumpAndSettle();

      await $('Estado del apartado').waitUntilVisible();
      expect($('Estado del apartado'), findsOneWidget);
      expect($(ListTile).containing($(TestData.initialStatusLabel)), findsOneWidget);
      expect($(ListTile).containing($(TestData.targetStatusLabel)), findsOneWidget);
      expect($(ListTile).containing($('Completado')), findsOneWidget);
      await NavigationHelper.saveEvidenceScreenshot($, '02_selector_estados');

      // 9-11. Seleccionar "En progreso" y esperar respuesta del backend.
      await $(ListTile).containing($(TestData.targetStatusLabel)).tap();
      await $.pump(const Duration(milliseconds: 500));

      // Esperar notificación de éxito o cambio de estado sin ocultar fallos.
      await _waitForStatusUpdate($, statusRow);
      await NavigationHelper.saveEvidenceScreenshot($, '03_despues_seleccionar_en_progreso');

      // 12. Verificar que en la píldora del apartado aparezca "En progreso" y ya no "Pendiente".
      expect(statusRow.$(TestData.targetStatusLabel), findsOneWidget);
      expect(statusRow.$(TestData.initialStatusLabel), findsNothing);

      // Verificar directamente contra la API REST que el backend persistió el cambio.
      final apiStatusAfterChange = await _fetchSectionStatusFromApi();
      debugPrint('MOV006_API_STATUS_AFTER_CHANGE:$apiStatusAfterChange');
      expect(
        apiStatusAfterChange,
        TestData.targetStatusApiValue,
        reason: 'El backend REST no persistió el estado "in_progress" tras cambiarlo en la UI.',
      );

      // 13-15. Salir del detalle del apartado, volver a abrir el proyecto y la etapa/apartado.
      await NavigationHelper.navigateBack($); // -> HomeProjectDetailView
      await NavigationHelper.navigateBack($); // -> HomeProjectsListView
      await NavigationHelper.openProject($, projectName: TestData.projectName);
      await NavigationHelper.openSection($, sectionTitle: TestData.sectionTitle);

      // Verificar que el estado persiste en la UI y no volvió a "Pendiente".
      final reopenedStatusRow = $(Row).containing($('Cambiar estado'));
      expect(reopenedStatusRow.$(TestData.targetStatusLabel), findsOneWidget);
      expect(reopenedStatusRow.$(TestData.initialStatusLabel), findsNothing);
      await NavigationHelper.saveEvidenceScreenshot($, '04_despues_reabrir_apartado');

      final apiStatusAfterReopen = await _fetchSectionStatusFromApi();
      debugPrint('MOV006_API_STATUS_AFTER_REOPEN:$apiStatusAfterReopen');
      expect(apiStatusAfterReopen, TestData.targetStatusApiValue);
    },
  );
}

Future<void> _waitForStatusUpdate(
  PatrolIntegrationTester $,
  PatrolFinder statusRow,
) async {
  final deadline = DateTime.now().add(const Duration(seconds: 15));
  while (DateTime.now().isBefore(deadline)) {
    await $.pump(const Duration(milliseconds: 250));
    if ($('Estado actualizado').exists) {
      await $.pumpAndSettle();
      return;
    }
    if (statusRow.$(TestData.targetStatusLabel).exists &&
        !statusRow.$(TestData.initialStatusLabel).exists) {
      await $.pumpAndSettle();
      return;
    }
  }
  await $.pumpAndSettle();
}

Future<String?> _fetchSectionStatusFromApi() async {
  final dio = Dio(BaseOptions(baseUrl: TestData.apiBaseUrl));
  final loginResp = await dio.post<Map<String, dynamic>>(
    '/api/auth/login',
    data: {
      'email': TestData.testEmail,
      'password': TestData.testPassword,
    },
  );
  final token = loginResp.data?['access_token'] as String?;
  if (token == null || token.isEmpty) {
    throw StateError('No se obtuvo access_token al consultar API REST.');
  }

  final authHeaders = Options(headers: {'Authorization': 'Bearer $token'});
  final listResp = await dio.get<dynamic>(
    '/api/home-projects',
    options: authHeaders,
  );

  final projects = (listResp.data is Map)
      ? (listResp.data['projects'] as List<dynamic>? ?? const [])
      : (listResp.data as List<dynamic>? ?? const []);

  Map<String, dynamic>? targetProject;
  for (final item in projects) {
    if (item is Map<String, dynamic> && item['name'] == TestData.projectName) {
      targetProject = item;
      break;
    }
  }
  if (targetProject == null) {
    throw StateError('No se encontró el proyecto "${TestData.projectName}" en /api/home-projects.');
  }

  final projectId = targetProject['id'] as String;
  final detailResp = await dio.get<Map<String, dynamic>>(
    '/api/home-projects/$projectId',
    options: authHeaders,
  );
  final projectData = (detailResp.data?['project'] as Map<String, dynamic>?) ?? detailResp.data;
  final stages = (projectData?['stages'] as List<dynamic>?) ?? const [];

  for (final stage in stages) {
    if (stage is! Map<String, dynamic>) continue;
    final sections = (stage['sections'] as List<dynamic>?) ?? const [];
    for (final section in sections) {
      if (section is Map<String, dynamic> && section['title'] == TestData.sectionTitle) {
        return section['status'] as String?;
      }
    }
  }
  return null;
}
