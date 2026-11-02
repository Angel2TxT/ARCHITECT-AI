import 'package:flutter_test/flutter_test.dart';
import 'package:movil_architect/controllers/dashboard_controller.dart';
import 'package:movil_architect/core/storage/secure_storage_service.dart';
import 'package:movil_architect/models/analysis_models.dart';
import 'package:movil_architect/models/auth_models.dart';
import 'package:movil_architect/models/chat_models.dart';
import 'package:movil_architect/services/auth_service.dart';
import 'package:movil_architect/services/mobile_api_service.dart';

class MockAuthService implements AuthService {
  UserModel? mockUser = const UserModel(
    id: 1,
    email: 'user@example.com',
    fullName: 'Test User',
    role: 'user',
    hasPassword: true,
  );

  @override
  UserModel? get currentUser => mockUser;

  @override
  SubscriptionModel? get subscription => null;

  @override
  void updateSession({required UserModel user, SubscriptionModel? subscription}) {
    mockUser = user;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockMobileApiService implements MobileApiService {
  List<ChatSummary> returnedChats = [];
  List<String> deletedChatIds = [];

  @override
  Future<MeResponse> me() async {
    return const MeResponse(
      user: UserModel(
        id: 1,
        email: 'user@example.com',
        fullName: 'Test User',
        role: 'user',
        hasPassword: true,
      ),
      subscription: null,
    );
  }

  @override
  Future<List<ChatSummary>> listChats({int limit = 40}) async {
    return returnedChats;
  }

  @override
  Future<List<AnalysisSummary>> listAnalyses({int limit = 20}) async {
    return [];
  }

  @override
  Future<void> deleteChat(String chatId) async {
    deletedChatIds.add(chatId);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockSecureStorageService implements SecureStorageService {
  @override
  Future<List<String>> getPinnedChatIds() async => [];

  @override
  Future<void> savePinnedChatIds(List<String> ids) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('ChatSummary.fromJson', () {
    test('parses message_count safely from various types', () {
      final json1 = {
        'id': 'chat-1',
        'title': 'Análisis de casa',
        'message_count': 5,
        'updated_at': '2026-11-02T15:00:00Z',
      };
      final chat1 = ChatSummary.fromJson(json1);
      expect(chat1.id, 'chat-1');
      expect(chat1.title, 'Análisis de casa');
      expect(chat1.messageCount, 5);
      expect(chat1.updatedAt, isNotNull);

      // message_count as double/num
      final json2 = {
        'id': 'chat-2',
        'title': 'Plano eléctrico',
        'message_count': 3.0,
      };
      final chat2 = ChatSummary.fromJson(json2);
      expect(chat2.messageCount, 3);
    });

    test('handles null updated_at and null message_count gracefully', () {
      final json = {
        'id': 'chat-3',
        'title': null,
        'updated_at': null,
      };
      final chat = ChatSummary.fromJson(json);
      expect(chat.id, 'chat-3');
      expect(chat.title, 'Conversación');
      expect(chat.updatedAt, isNull);
      expect(chat.messageCount, 0);
    });
  });

  group('DashboardController recent chats sync', () {
    test('loads multiple recent chats from backend without dropping them', () async {
      final mockAuth = MockAuthService();
      final mockApi = MockMobileApiService();
      final mockStorage = MockSecureStorageService();

      mockApi.returnedChats = [
        ChatSummary(
          id: 'chat-1',
          title: 'Casa Residencial Norte',
          updatedAt: DateTime.parse('2026-11-02T14:00:00Z'),
          messageCount: 4,
        ),
        ChatSummary(
          id: 'chat-2',
          title: 'Peritaje Estructural',
          updatedAt: DateTime.parse('2026-11-02T12:00:00Z'),
          messageCount: 2,
        ),
        ChatSummary(
          id: 'chat-3',
          title: 'Normativa Chiapas',
          updatedAt: DateTime.parse('2026-11-01T10:00:00Z'),
          messageCount: 8,
        ),
      ];

      final controller = DashboardController(
        authService: mockAuth,
        mobileApiService: mockApi,
        secureStorage: mockStorage,
      );

      await controller.load();

      expect(controller.state, DashboardState.success);
      expect(controller.chats.length, 3);
      expect(controller.chats[0].id, 'chat-1');
      expect(controller.chats[1].id, 'chat-2');
      expect(controller.chats[2].id, 'chat-3');
      expect(mockApi.deletedChatIds, isEmpty);
    });

    test('skips empty placeholder chat without destructively deleting it on the server', () async {
      final mockAuth = MockAuthService();
      final mockApi = MockMobileApiService();
      final mockStorage = MockSecureStorageService();

      mockApi.returnedChats = [
        ChatSummary(
          id: 'chat-1',
          title: 'Proyecto Real',
          updatedAt: DateTime.now(),
          messageCount: 3,
        ),
        ChatSummary(
          id: 'chat-empty',
          title: 'Nuevo chat',
          updatedAt: DateTime.now(),
          messageCount: 0,
        ),
      ];

      final controller = DashboardController(
        authService: mockAuth,
        mobileApiService: mockApi,
        secureStorage: mockStorage,
      );

      await controller.load();

      expect(controller.chats.length, 1);
      expect(controller.chats.first.id, 'chat-1');
      // No debe mandar a borrar nada durante la sincronización de lectura
      expect(mockApi.deletedChatIds, isEmpty);
    });
  });
}

