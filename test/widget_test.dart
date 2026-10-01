import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movil_architect/views/login/widgets/login_widgets.dart';

void main() {
  testWidgets('LoginAppMark renders ARCHITECT brand and logo', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: LoginAppMark())),
    );

    expect(find.text('ARCHITECT'), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
  });
}
