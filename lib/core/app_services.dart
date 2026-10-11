import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:path_provider/path_provider.dart';
import 'package:movil_architect/core/network/api_client.dart';
import 'package:movil_architect/core/storage/secure_storage_service.dart';
import 'package:movil_architect/core/storage/settings_storage.dart';
import 'package:movil_architect/core/theme/theme_service.dart';
import 'package:movil_architect/services/auth_service.dart';
import 'package:movil_architect/services/billing_service.dart';
import 'package:movil_architect/services/guest_service.dart';
import 'package:movil_architect/services/home_project_service.dart';
import 'package:movil_architect/services/mobile_api_service.dart';
import 'package:movil_architect/services/push_notification_service.dart';
import 'package:movil_architect/services/support_service.dart';

class AppServices {
  AppServices._();

  static final AppServices instance = AppServices._();

  late final SettingsStorage settingsStorage;
  late final SecureStorageService secureStorage;
  late final ApiClient apiClient;
  late final AuthService authService;
  late final MobileApiService mobileApiService;
  late final HomeProjectService homeProjectService;
  late final BillingService billingService;
  late final SupportService supportService;
  late final GuestService guestService;
  late final ThemeService themeService;
  late final PushNotificationService pushNotificationService;

  bool _initialized = false;
  bool get isInitialized => _initialized;

  Future<void> init() async {
    if (_initialized) return;

    settingsStorage = SettingsStorage();
    secureStorage = SecureStorageService();
    themeService = ThemeService();
    apiClient = ApiClient(
      settingsStorage: settingsStorage,
      secureStorage: secureStorage,
    );

    final dir = await getApplicationSupportDirectory();
    final cookieJar = PersistCookieJar(
      ignoreExpires: true,
      storage: FileStorage('${dir.path}/cookies'),
    );
    apiClient.dio.interceptors.insert(0, CookieManager(cookieJar));

    authService = AuthService(
      apiClient: apiClient,
      secureStorage: secureStorage,
    );
    mobileApiService = MobileApiService(apiClient: apiClient);
    homeProjectService = HomeProjectService(apiClient: apiClient);
    billingService = BillingService(apiClient: apiClient);
    supportService = SupportService(apiClient: apiClient);
    guestService = GuestService(apiClient: apiClient);
    pushNotificationService = PushNotificationService(
      apiClient: apiClient,
      secureStorage: secureStorage,
    );
    authService.attachPush(pushNotificationService);

    apiClient.onUnauthorized = authService.handleUnauthorized;

    await apiClient.refreshBaseUrl();
    await themeService.init(settingsStorage);
    await pushNotificationService.start();
    _initialized = true;
  }
}
