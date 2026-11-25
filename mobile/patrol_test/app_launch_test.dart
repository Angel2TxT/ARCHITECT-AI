import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movil_architect/main.dart' as app;
import 'package:patrol/patrol.dart';

void main() {
  patrolTest(
    'launches ARCHITECT mobile app',
    ($) async {
      await app.main();
      await $.pumpAndSettle();

      expect($(MaterialApp), findsOneWidget);
    },
  );
}
