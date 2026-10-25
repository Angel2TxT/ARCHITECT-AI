import 'package:flutter_test/flutter_test.dart';
import 'package:movil_architect/controllers/profile_controller.dart';
import 'package:movil_architect/models/auth_models.dart';
import 'package:movil_architect/services/auth_service.dart';
import 'package:movil_architect/services/mobile_api_service.dart';

class MockAuthService implements AuthService {
  UserModel? mockUser;
  String? updatedName;

  @override
  UserModel? get currentUser => mockUser;

  @override
  Future<UserModel> updateProfileName(String fullName) async {
    updatedName = fullName;
    mockUser = UserModel(
      id: mockUser?.id ?? 1,
      email: mockUser?.email ?? 'test@example.com',
      fullName: fullName,
      role: mockUser?.role ?? 'user',
      hasPassword: mockUser?.hasPassword ?? true,
    );
    return mockUser!;
  }

  @override
  void updateSession({required UserModel user, SubscriptionModel? subscription}) {
    mockUser = user;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockMobileApiService implements MobileApiService {
  @override
  Future<MeResponse> me() async {
    return const MeResponse(
      user: UserModel(
        id: 1,
        email: 'juan.perez@example.com',
        fullName: 'Juan Pérez',
        role: 'user',
        hasPassword: true,
      ),
      subscription: null,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('ProfileController validations', () {
    late MockAuthService fakeAuth;
    late MockMobileApiService fakeApi;
    late ProfileController controller;

    setUp(() {
      fakeAuth = MockAuthService();
      fakeApi = MockMobileApiService();
      controller = ProfileController(
        authService: fakeAuth,
        mobileApiService: fakeApi,
      );
    });

    tearDown(() {
      controller.dispose();
    });

    test('load() populates nameController and emailController', () async {
      await controller.load();
      expect(controller.nameController.text, 'Juan Pérez');
      expect(controller.emailController.text, 'juan.perez@example.com');
    });

    test('saveName() rejects invalid names containing numbers or special chars', () async {
      controller.nameController.text = 'Juan123';
      final ok = await controller.saveName();
      expect(ok, false);
      expect(controller.errorMessage, 'El nombre solo puede contener letras y espacios.');

      controller.nameController.text = 'Juan@#%';
      final okSymbols = await controller.saveName();
      expect(okSymbols, false);
      expect(controller.errorMessage, 'El nombre solo puede contener letras y espacios.');
    });

    test('saveName() accepts valid names with letters, spaces and Spanish accents', () async {
      controller.nameController.text = 'María José Peña Núñez';
      final ok = await controller.saveName();
      expect(ok, true);
      expect(controller.successMessage, 'Nombre actualizado.');
      expect(fakeAuth.updatedName, 'María José Peña Núñez');
    });

    test('deleteAccount() rejects invalid email format when user has no password', () async {
      fakeAuth.mockUser = const UserModel(
        id: 1,
        email: 'google.user@example.com',
        fullName: 'Google User',
        role: 'user',
        hasPassword: false,
      );

      controller.confirmDeleteController.text = 'not-an-email';
      final ok = await controller.deleteAccount();
      expect(ok, false);
      expect(controller.errorMessage, 'Ingresa un correo electrónico válido.');
    });
  });
}
