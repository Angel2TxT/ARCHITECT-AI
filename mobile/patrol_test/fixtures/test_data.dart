/// Datos y configuración de pruebas parametrizados por `--dart-define`.
/// No almacena credenciales reales en el código fuente.
abstract final class TestData {
  static const String testEmail = String.fromEnvironment('TEST_EMAIL');
  static const String testPassword = String.fromEnvironment('TEST_PASSWORD');
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000',
  );
  static const String projectName = String.fromEnvironment(
    'TEST_PROJECT_NAME',
    defaultValue: 'UTS',
  );
  static const String sectionTitle = String.fromEnvironment(
    'TEST_SECTION_TITLE',
    defaultValue: 'Necesidades del cliente',
  );
  static const String initialStatusLabel = 'Pendiente';
  static const String targetStatusLabel = 'En progreso';
  static const String targetStatusApiValue = 'in_progress';
}
