import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movil_architect/views/dashboard/widgets/dashboard_shell.dart';

void main() {
  group('DashboardHero and DashboardAskBar Animations', () {
    testWidgets('DashboardHero rotates text on tap',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: DashboardHero(initialIndex: 0),
            ),
          ),
        ),
      );

      // Verify initial text
      expect(find.text('¿Qué plano revisamos hoy?'), findsOneWidget);

      // Tap to advance to next welcome prompt
      await tester.tap(find.byType(DashboardHero));
      await tester.pump(const Duration(milliseconds: 650));

      // Second prompt should now be rendered
      expect(find.text('¿En qué te ayudamos hoy?'), findsOneWidget);
    });

    testWidgets('DashboardAskBar renders BorderBeam and reacts to focus and send',
        (tester) async {
      final controller = TextEditingController();
      var sendTapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DashboardAskBar(
              controller: controller,
              hintText: 'Pregunta sobre normativa...',
              onSendTap: () {
                sendTapped = true;
              },
            ),
          ),
        ),
      );

      // Verify hint and icons
      expect(find.text('Pregunta sobre normativa...'), findsOneWidget);
      expect(find.byIcon(Icons.attach_file_rounded), findsOneWidget);
      expect(find.byIcon(Icons.mic_none_rounded), findsOneWidget);
      expect(find.byIcon(Icons.arrow_upward_rounded), findsOneWidget);

      // Verify CustomPaint is rendered for border beam
      expect(find.byType(CustomPaint), findsWidgets);

      // Tap send button
      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await tester.pump(const Duration(milliseconds: 100));
      expect(sendTapped, isTrue);

      controller.dispose();
    });
  });
}
