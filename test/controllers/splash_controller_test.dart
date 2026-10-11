import 'package:flutter_test/flutter_test.dart';
import 'package:movil_architect/controllers/splash_controller.dart';
import 'package:movil_architect/core/network/api_exception.dart';
import 'package:movil_architect/models/auth_models.dart';
import 'package:movil_architect/services/auth_service.dart';
import 'package:movil_architect/services/mobile_api_service.dart';
import 'package:movil_architect/services/push_notification_service.dart';

class FakeAuthService implements AuthService {
  bool tokenExists = false;

  bool logoutCalled = false;
  UserModel? updatedUser;
  SubscriptionModel? updatedSubscription;

  @override
  void Function()? onSessionExpired;

  @override
  Future<bool> hasToken() async => tokenExists;

  @override
  Future<void> logout() async {
    logoutCalled = true;
  }

  @override
  void updateSession({
    required UserModel user,
    SubscriptionModel? subscription,
  }) {
    updatedUser = user;
    updatedSubscription = subscription;
  }

  // no-op stubs for unused interface methods
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeMobileApiService implements MobileApiService {
  HealthResponse Function()? onHealth;
  MeResponse Function()? onMe;

  @override
  Future<HealthResponse> health() async {
    if (onHealth != null) return onHealth!();
    return const HealthResponse(
      ok: true,
      service: 'ARCHITECT',
      message: 'OK',
      version: '1.0.0',
    );
  }

  @override
  Future<MeResponse> me() async {
    if (onMe != null) return onMe!();
    return const MeResponse(
      user: UserModel(
        id: 1,
        email: 'test@example.com',
        fullName: 'Test User',
        role: 'user',
      ),
      subscription: null,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakePushNotificationService implements PushNotificationService {
  bool syncCalled = false;

  @override
  Future<void> syncTokenWithBackend({bool force = false}) async {
    syncCalled = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('SplashController - TDD Tests', () {
    late FakeAuthService fakeAuthService;
    late FakeMobileApiService fakeMobileApiService;
    late FakePushNotificationService fakePushService;

    setUp(() {
      fakeAuthService = FakeAuthService();
      fakeMobileApiService = FakeMobileApiService();
      fakePushService = FakePushNotificationService();
    });

    test('Initial status is loading and errorMessage is null', () {
      final controller = SplashController(
        authService: fakeAuthService,
        mobileApiService: fakeMobileApiService,
        pushNotificationService: fakePushService,
      );

      expect(controller.status, SplashStatus.loading);
      expect(controller.errorMessage, isNull);
    });

    test('Transitions to serverError when health.ok is false', () async {
      fakeMobileApiService.onHealth = () => const HealthResponse(
        ok: false,
        service: 'ARCHITECT',
        message: 'Maintenance',
        version: '1.0.0',
      );

      final controller = SplashController(
        authService: fakeAuthService,
        mobileApiService: fakeMobileApiService,
        pushNotificationService: fakePushService,
      );

      await controller.bootstrap();

      expect(controller.status, SplashStatus.serverError);
      expect(
        controller.errorMessage,
        'El servidor respondió pero no está listo.',
      );
    });

    test(
      'Transitions to serverError when health() throws ApiException',
      () async {
        fakeMobileApiService.onHealth = () => throw ApiException(
          message: 'Sin conexión con el backend',
          isOffline: true,
        );

        final controller = SplashController(
          authService: fakeAuthService,
          mobileApiService: fakeMobileApiService,
          pushNotificationService: fakePushService,
        );

        await controller.bootstrap();

        expect(controller.status, SplashStatus.serverError);
        expect(controller.errorMessage, 'Sin conexión con el backend');
      },
    );

    test('Transitions to readyLogin when user has no token', () async {
      fakeAuthService.tokenExists = false;

      final controller = SplashController(
        authService: fakeAuthService,
        mobileApiService: fakeMobileApiService,
        pushNotificationService: fakePushService,
      );

      await controller.bootstrap();

      expect(controller.status, SplashStatus.readyLogin);
      expect(controller.errorMessage, isNull);
    });

    test(
      'Transitions to readyDashboard and syncs push when authenticated',
      () async {
        fakeAuthService.tokenExists = true;

        final controller = SplashController(
          authService: fakeAuthService,
          mobileApiService: fakeMobileApiService,
          pushNotificationService: fakePushService,
        );

        await controller.bootstrap();

        expect(controller.status, SplashStatus.readyDashboard);
        expect(controller.errorMessage, isNull);
        expect(fakeAuthService.updatedUser?.email, 'test@example.com');
        expect(fakePushService.syncCalled, isTrue);
      },
    );

    test(
      'Transitions to readyLogin and logs out when me() throws 401/invalid token',
      () async {
        fakeAuthService.tokenExists = true;
        fakeMobileApiService.onMe = () => throw ApiException(
          message: 'Token expirado',
          statusCode: 401,
          isOffline: false,
        );

        final controller = SplashController(
          authService: fakeAuthService,
          mobileApiService: fakeMobileApiService,
          pushNotificationService: fakePushService,
        );

        await controller.bootstrap();

        expect(controller.status, SplashStatus.readyLogin);
        expect(fakeAuthService.logoutCalled, isTrue);
      },
    );

    test(
      'Transitions to serverError when me() throws offline ApiException',
      () async {
        fakeAuthService.tokenExists = true;
        fakeMobileApiService.onMe = () =>
            throw ApiException(message: 'Fallo de red', isOffline: true);

        final controller = SplashController(
          authService: fakeAuthService,
          mobileApiService: fakeMobileApiService,
          pushNotificationService: fakePushService,
        );

        await controller.bootstrap();

        expect(controller.status, SplashStatus.serverError);
        expect(controller.errorMessage, 'Fallo de red');
        expect(fakeAuthService.logoutCalled, isTrue);
      },
    );

    test(
      'Restores previous session expired handler in finally block',
      () async {
        void dummyHandler() {}
        fakeAuthService.onSessionExpired = dummyHandler;

        final controller = SplashController(
          authService: fakeAuthService,
          mobileApiService: fakeMobileApiService,
          pushNotificationService: fakePushService,
        );

        await controller.bootstrap();

        expect(fakeAuthService.onSessionExpired, equals(dummyHandler));
      },
    );
  });
}
