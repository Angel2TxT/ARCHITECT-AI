import 'package:flutter_test/flutter_test.dart';
import 'package:movil_architect/core/utils/chat_response_formatter.dart';

void main() {
  group('ChatResponseFormatter', () {
    test('limpia viñetas forzadas en presentaciones y saludos conversacionales', () {
      const raw =
          '• Mucho gusto, Ángel\n• quedo a tu servicio para resolver cualquier duda técnica sobre arquitectura, ingeniería civil o construcción';
      final formatted = ChatResponseFormatter.formatAssistantText(raw);

      expect(formatted.contains('•'), isFalse);
      expect(formatted.contains('- '), isFalse);
      expect(
        formatted,
        'Mucho gusto, Ángel. Quedo a tu servicio para resolver cualquier duda técnica sobre arquitectura, ingeniería civil o construcción.',
      );
    });

    test('limpia viñeta simple en saludo casual', () {
      const raw = '- ¡Hola! ¿En qué plano te ayudo hoy?';
      final formatted = ChatResponseFormatter.formatAssistantText(raw);

      expect(formatted, '¡Hola! ¿En qué plano te ayudo hoy?');
    });

    test('preserva listas de hallazgos bajo encabezado técnico', () {
      const raw =
          '**Hallazgos principales**\n- Puerta de 0.83 m\n- Ventana reducida de 0.10 m';
      final formatted = ChatResponseFormatter.formatAssistantText(raw);

      expect(formatted.contains('**Hallazgos principales**'), isTrue);
      expect(formatted.contains('- Puerta de 0.83 m'), isTrue);
      expect(formatted.contains('- Ventana reducida de 0.10 m'), isTrue);
    });
  });
}
