import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:patrol/patrol.dart';

import '../fixtures/test_data.dart';

/// Helper reutilizable para navegar por Casa hogar y capturar evidencias.
class NavigationHelper {
  const NavigationHelper._();

  static Future<void> openHomeProjectsList(PatrolIntegrationTester $) async {
    await $(Icons.menu_rounded).waitUntilVisible();
    await $(Icons.menu_rounded).tap();
    await $.pump(const Duration(milliseconds: 600));

    await $('Casa hogar').waitUntilVisible(timeout: const Duration(seconds: 15));
    await $('Casa hogar').tap();
    await $.pumpAndSettle();

    await $('Casa hogar').waitUntilVisible(timeout: const Duration(seconds: 15));
  }

  static Future<void> openProject(
    PatrolIntegrationTester $, {
    String? projectName,
  }) async {
    final target = projectName ?? TestData.projectName;
    await $(target).waitUntilVisible(timeout: const Duration(seconds: 15));
    await $(target).tap();
    await $.pumpAndSettle();

    await $('Apartados').waitUntilVisible(timeout: const Duration(seconds: 15));
  }

  static Future<void> openSection(
    PatrolIntegrationTester $, {
    String? sectionTitle,
  }) async {
    final target = sectionTitle ?? TestData.sectionTitle;
    await $(target).scrollTo();
    await $(target).waitUntilVisible();
    await $(target).tap();
    await $.pumpAndSettle();

    await $('Cambiar estado').waitUntilVisible(
      timeout: const Duration(seconds: 15),
    );
  }

  static Future<void> navigateBack(PatrolIntegrationTester $) async {
    await $.tester.pageBack();
    await $.pumpAndSettle();
  }

  /// Captura el árbol visual actual de Flutter y lo guarda en el almacenamiento
  /// interno de la app para extraerlo luego con `adb`.
  static Future<String?> saveEvidenceScreenshot(
    PatrolIntegrationTester $,
    String fileName,
  ) async {
    try {
      await $.pumpAndSettle();
      final renderView = RendererBinding.instance.renderViews.first;
      final layer = renderView.debugLayer;
      if (layer is! OffsetLayer) return null;

      final image = await layer.toImage(renderView.paintBounds, pixelRatio: 2.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (byteData == null) return null;

      final dir = await getApplicationDocumentsDirectory();
      final evidenceDir = Directory('${dir.path}/qa_evidence');
      if (!evidenceDir.existsSync()) {
        evidenceDir.createSync(recursive: true);
      }
      final file = File('${evidenceDir.path}/$fileName.png');
      await file.writeAsBytes(byteData.buffer.asUint8List(), flush: true);
      debugPrint('QA_SCREENSHOT_SAVED:${file.path}');
      return file.path;
    } catch (e) {
      debugPrint('QA_SCREENSHOT_ERROR($fileName): $e');
      return null;
    }
  }
}
