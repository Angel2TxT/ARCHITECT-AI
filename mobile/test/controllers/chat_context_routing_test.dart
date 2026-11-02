import 'package:flutter_test/flutter_test.dart';
import 'package:movil_architect/controllers/chat_controller.dart';
import 'package:movil_architect/models/analysis_models.dart';
import 'package:movil_architect/models/chat_models.dart';
import 'package:movil_architect/services/mobile_api_service.dart';

class MockMobileApiServiceForChat implements MobileApiService {
  int sendAskCallCount = 0;
  int sendFollowupCallCount = 0;
  String? lastAskedMessage;
  String? lastAskedChatId;

  final ChatDetail stubChatDetail = ChatDetail(
    chat: ChatSummary(
      id: 'chat-abc-123',
      title: 'Plano y Dudas',
      updatedAt: DateTime.parse('2026-11-02T16:00:00Z'),
      messageCount: 2,
    ),
    messages: [
      ChatMessage(
        id: 1,
        role: 'user',
        content: const MessageContent(
          text: 'Analiza este plano arquitectónico',
        ),
        createdAt: DateTime.parse('2026-11-02T16:00:00Z'),
      ),
      ChatMessage(
        id: 2,
        role: 'assistant',
        content: const MessageContent(
          text: 'Plano analizado con éxito.',
          analysisId: 42,
        ),
        createdAt: DateTime.parse('2026-11-02T16:01:00Z'),
      ),
    ],
  );

  @override
  Future<ChatDetail> getChat(String chatId) async {
    return stubChatDetail;
  }

  @override
  Future<AskResponse> sendAsk({
    required String message,
    String? chatId,
  }) async {
    sendAskCallCount++;
    lastAskedMessage = message;
    lastAskedChatId = chatId;
    return const AskResponse(
      text: 'Respuesta técnica general sobre construcción.',
      chatId: 'chat-abc-123',
    );
  }

  @override
  Future<AnalysisResult> sendFollowup({
    required String message,
    required int analysisId,
    String? chatId,
  }) async {
    sendFollowupCallCount++;
    throw UnimplementedError('sendFollowup no debe ser llamado por sendMessage');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ChatController - Routing y Desacople de Contexto', () {
    late MockMobileApiServiceForChat mockApi;
    late ChatController controller;

    setUp(() {
      mockApi = MockMobileApiServiceForChat();
      controller = ChatController(
        chatId: 'chat-abc-123',
        mobileApiService: mockApi,
      );
    });

    test('sendMessage no reenvia a sendFollowup cuando hay un analisis previo en el chat', () async {
      // 1. Cargar el chat (el cual contiene un mensaje previo con analysisId: 42)
      await controller.load(showLoading: false);
      expect(controller.activeAnalysisId, 42);

      // 2. El usuario escribe una pregunta de cambio de tema
      controller.messageController.text = '¿Cuánto tiempo tarda en fraguar el concreto?';

      // 3. Enviar el mensaje
      final success = await controller.sendMessage();
      expect(success, isTrue);

      // 4. Verificaciones:
      // Debe enrutarse a sendAsk para que el backend decida el contexto semánticamente
      expect(mockApi.sendAskCallCount, 1);
      expect(mockApi.lastAskedMessage, '¿Cuánto tiempo tarda en fraguar el concreto?');
      expect(mockApi.lastAskedChatId, 'chat-abc-123');

      // NO debe haberse invocado sendFollowup (que reanalizaba la imagen pesada en disco)
      expect(mockApi.sendFollowupCallCount, 0);
    });
  });
}
