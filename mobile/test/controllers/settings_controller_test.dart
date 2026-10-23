import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movil_architect/controllers/settings_controller.dart';
import 'package:movil_architect/core/network/api_client.dart';
import 'package:movil_architect/core/network/api_exception.dart';
import 'package:movil_architect/core/storage/settings_storage.dart';
import 'package:movil_architect/core/theme/theme_service.dart';
import 'package:movil_architect/models/auth_models.dart';
import 'package:movil_architect/services/mobile_api_service.dart';

class FakeSettingsStorage implements SettingsStorage {
  String storedUrl = 'http://10.0.2.2:8000';
  bool storedDarkMode = false;
  int saveUrlCalls = 0;

  @override
  Future<String> getServerUrl() async => storedUrl;

  @override
  Future<void> saveServerUrl(String url) async {
    storedUrl = url;
    saveUrlCalls++;
  }

  @override
  Future<bool> isDarkModeEnabled() async => storedDarkMode;

  @override
  Future<void> saveDarkMode(bool enabled) async {
    storedDarkMode = enabled;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeApiClient implements ApiClient {
  String currentBaseUrl = '';
  String appliedBaseUrl = '';
  int refreshCalls = 0;
  int setBaseUrlCalls = 0;

  @override
  Future<void> setBaseUrl(String url) async {
    setBaseUrlCalls++;
    currentBaseUrl = url;
  }

  @override
  void applyBaseUrl(String url) {
    appliedBaseUrl = url;
  }

  @override
  Future<void> refreshBaseUrl() async {
    refreshCalls++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeMobileApiService implements MobileApiService {
  HealthResponse Function()? onHealth;

  @override
  Future<HealthResponse> health() async {
    if (onHealth != null) return onHealth!();
    return const HealthResponse(
      ok: true,
      service: 'ARCHITECT',
      message: 'OK',
      version: '1.2.0',
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeThemeService extends ChangeNotifier implements ThemeService {
  bool _dark = false;

  @override
  bool get isDarkMode => _dark;

  @override
  ThemeMode get themeMode => _dark ? ThemeMode.dark : ThemeMode.light;

  @override
  Future<void> setDarkMode(bool enabled) async {
    _dark = enabled;
    notifyListeners();
  }

  @override
  Future<void> init(SettingsStorage settingsStorage) async {
    _dark = await settingsStorage.isDarkModeEnabled();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('SettingsController - TDD Test Suite', () {
    late FakeSettingsStorage fakeStorage;
    late FakeApiClient fakeApiClient;
    late FakeMobileApiService fakeMobileApi;
    late FakeThemeService fakeThemeService;
    late SettingsController controller;

    setUp(() {
      fakeStorage = FakeSettingsStorage();
      fakeApiClient = FakeApiClient();
      fakeMobileApi = FakeMobileApiService();
      fakeThemeService = FakeThemeService();

      controller = SettingsController(
        settingsStorage: fakeStorage,
        apiClient: fakeApiClient,
        mobileApiService: fakeMobileApi,
        themeService: fakeThemeService,
      );
    });

    tearDown(() {
      controller.dispose();
    });

    test('Initial state is correct', () {
      expect(controller.isLoading, isFalse);
      expect(controller.isTesting, isFalse);
      expect(controller.errorMessage, isNull);
      expect(controller.successMessage, isNull);
      expect(controller.isDarkMode, isFalse);
      expect(controller.urlController.text, isEmpty);
    });

    test('load() populates urlController with stored server URL and notifies listeners', () async {
      fakeStorage.storedUrl = 'https://api.myarchapp.com';
      var notified = false;
      controller.addListener(() => notified = true);

      await controller.load();

      expect(controller.urlController.text, 'https://api.myarchapp.com');
      expect(notified, isTrue);
    });

    test('setDarkMode() updates theme and triggers notification', () async {
      var notifications = 0;
      controller.addListener(() => notifications++);

      expect(controller.isDarkMode, isFalse);
      await controller.setDarkMode(true);

      expect(controller.isDarkMode, isTrue);
      expect(fakeThemeService.isDarkMode, isTrue);
      expect(notifications, greaterThanOrEqualTo(1));
    });

    group('save() flow', () {
      test('Fails and sets error when URL input is empty or whitespace', () async {
        controller.urlController.text = '   ';

        final result = await controller.save();

        expect(result, isFalse);
        expect(controller.errorMessage, 'Ingresa una URL válida.');
        expect(controller.isLoading, isFalse);
        expect(fakeApiClient.setBaseUrlCalls, 0);
      });

      test('Successfully normalizes and saves server URL when health returns ok', () async {
        controller.urlController.text = 'http://127.0.0.1:8000/';

        final result = await controller.save();

        expect(result, isTrue);
        expect(controller.errorMessage, isNull);
        expect(controller.successMessage, 'Servidor configurado correctamente.');
        expect(controller.isLoading, isFalse);
        expect(fakeApiClient.setBaseUrlCalls, 1);
        expect(fakeApiClient.currentBaseUrl, isNotEmpty);
      });

      test('Fails when health responds ok=false (server not ready)', () async {
        controller.urlController.text = 'http://10.0.2.2:8000';
        fakeMobileApi.onHealth = () => const HealthResponse(
              ok: false,
              service: 'ARCHITECT',
              message: 'Maintenance',
              version: '',
            );

        final result = await controller.save();

        expect(result, isFalse);
        expect(controller.errorMessage, 'La URL respondió pero el servicio no está listo.');
        expect(controller.successMessage, isNull);
        expect(controller.isLoading, isFalse);
      });

      test('Fails and captures message on ApiException', () async {
        controller.urlController.text = 'http://10.0.2.2:8000';
        fakeMobileApi.onHealth = () => throw ApiException(
              message: 'Servidor no encontrado o timeout',
              statusCode: 503,
            );

        final result = await controller.save();

        expect(result, isFalse);
        expect(controller.errorMessage, 'Servidor no encontrado o timeout');
        expect(controller.successMessage, isNull);
        expect(controller.isLoading, isFalse);
      });

      test('Fails and displays generic error on unanticipated exception', () async {
        controller.urlController.text = 'http://10.0.2.2:8000';
        fakeMobileApi.onHealth = () => throw Exception('Socket connection failed');

        final result = await controller.save();

        expect(result, isFalse);
        expect(controller.errorMessage, 'No se pudo conectar con esa URL.');
        expect(controller.successMessage, isNull);
        expect(controller.isLoading, isFalse);
      });
    });

    group('testConnection() flow', () {
      test('Fails immediately when URL input is empty or whitespace', () async {
        controller.urlController.text = '   ';

        await controller.testConnection();

        expect(controller.errorMessage, 'Ingresa una URL válida.');
        expect(controller.successMessage, isNull);
        expect(controller.isTesting, isFalse);
        expect(fakeApiClient.refreshCalls, 0);
      });

      test('Sets success message with version when health returns ok and version is present', () async {
        controller.urlController.text = 'http://10.0.2.2:8000';
        fakeMobileApi.onHealth = () => const HealthResponse(
              ok: true,
              service: 'ARCHITECT',
              message: 'OK',
              version: '2.1.0',
            );

        await controller.testConnection();

        expect(controller.successMessage, 'Conexión exitosa (2.1.0)');
        expect(controller.errorMessage, isNull);
        expect(controller.isTesting, isFalse);
        expect(fakeApiClient.refreshCalls, 1);
      });

      test('Sets success message without version when version is empty', () async {
        controller.urlController.text = 'http://10.0.2.2:8000';
        fakeMobileApi.onHealth = () => const HealthResponse(
              ok: true,
              service: 'ARCHITECT',
              message: 'OK',
              version: '',
            );

        await controller.testConnection();

        expect(controller.successMessage, 'Conexión exitosa');
        expect(controller.errorMessage, isNull);
        expect(controller.isTesting, isFalse);
        expect(fakeApiClient.refreshCalls, 1);
      });

      test('Sets error message when health.ok is false', () async {
        controller.urlController.text = 'http://10.0.2.2:8000';
        fakeMobileApi.onHealth = () => const HealthResponse(
              ok: false,
              service: 'ARCHITECT',
              message: 'Unhealthy',
              version: '',
            );

        await controller.testConnection();

        expect(controller.errorMessage, 'El servidor no está listo.');
        expect(controller.successMessage, isNull);
        expect(controller.isTesting, isFalse);
        expect(fakeApiClient.refreshCalls, 1);
      });

      test('Sets error on ApiException and always restores base URL in finally', () async {
        controller.urlController.text = 'http://10.0.2.2:8000';
        fakeMobileApi.onHealth = () => throw ApiException(
              message: 'DNS lookup failed',
              statusCode: null,
            );

        await controller.testConnection();

        expect(controller.errorMessage, 'DNS lookup failed');
        expect(controller.isTesting, isFalse);
        expect(fakeApiClient.refreshCalls, 1);
      });

      test('Sets generic error on unanticipated exception and restores base URL', () async {
        controller.urlController.text = 'http://10.0.2.2:8000';
        fakeMobileApi.onHealth = () => throw const FormatException('Invalid payload');

        await controller.testConnection();

        expect(controller.errorMessage, 'No se pudo conectar al servidor.');
        expect(controller.isTesting, isFalse);
        expect(fakeApiClient.refreshCalls, 1);
      });
    });

    test('dispose() cleans up text controller and prevents notify after disposal', () {
      final freshController = SettingsController(
        settingsStorage: fakeStorage,
        apiClient: fakeApiClient,
        mobileApiService: fakeMobileApi,
        themeService: fakeThemeService,
      );

      expect(() => freshController.dispose(), returnsNormally);
      expect(() => freshController.load(), returnsNormally);
    });
  });
}
