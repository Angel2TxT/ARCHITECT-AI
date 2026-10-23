import 'package:dio/dio.dart';

class ApiException implements Exception {
  ApiException({
    required this.message,
    this.statusCode,
    this.code,
    this.isOffline = false,
  });

  final String message;
  final int? statusCode;
  final String? code;
  final bool isOffline;

  bool get isPlanLimit => statusCode == 402;

  factory ApiException.fromDio(DioException error) {
    if (error.type == DioExceptionType.connectionError ||
        error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.sendTimeout ||
        error.type == DioExceptionType.receiveTimeout) {
      return ApiException(
        message:
            'Sin conexión al servidor. Revisa tu red o la URL configurada.',
        isOffline: true,
      );
    }

    final response = error.response;
    final statusCode = response?.statusCode;
    final data = response?.data;
    final path = error.requestOptions.path;
    final host = error.requestOptions.uri.host;

    String message = 'Ocurrió un error inesperado.';
    String? code;
    if (data is String) {
      message = _sanitizeBodyMessage(data, host: host) ?? message;
    } else if (data is Map && data['detail'] != null) {
      final detail = data['detail'];
      if (detail is String) {
        message = _sanitizeBodyMessage(detail, host: host) ?? detail;
      } else if (detail is Map) {
        code = detail['code']?.toString();
        final nested = detail['message']?.toString();
        if (nested != null && nested.isNotEmpty) {
          message = _sanitizeBodyMessage(nested, host: host) ?? nested;
        }
      } else if (detail is List && detail.isNotEmpty) {
        final first = detail.first;
        if (first is Map && first['msg'] is String) {
          message = first['msg'] as String;
        } else {
          message = first.toString();
        }
      }
    } else if (data is Map && data['message'] is String) {
      message = _sanitizeBodyMessage(data['message'] as String, host: host) ??
          data['message'] as String;
    }

    switch (statusCode) {
      case 401:
        if (message == 'Ocurrió un error inesperado.') {
          final isAuthAttempt =
              path.contains('/login') || path.contains('/register');
          message = isAuthAttempt
              ? 'Correo o contraseña incorrectos'
              : 'Sesión expirada. Inicia sesión de nuevo.';
        }
      case 403:
        message = message == 'Ocurrió un error inesperado.' ||
                message == 'Forbidden'
            ? 'No tienes permiso o alcanzaste el límite de tu plan.'
            : message;
      case 402:
        if (message == 'Ocurrió un error inesperado.') {
          message = code == 'trial_exhausted'
              ? 'Tu prueba se agotó. Crea una cuenta o inicia sesión.'
              : 'Has alcanzado el límite de tu plan.';
        }
      case 413:
        message = 'El archivo es demasiado grande.';
      case 400:
        message = message == 'Ocurrió un error inesperado.'
            ? 'Formato no soportado o archivo inválido.'
            : message;
      case 404:
        if (message == 'Ocurrió un error inesperado.' ||
            message == 'Not Found') {
          message = path.contains('/api/chats/')
              ? 'Conversación no encontrada.'
              : 'Ruta no encontrada en el servidor. Verifica la URL en Ajustes.';
        }
      case 502:
      case 503:
      case 504:
        message = _tunnelOrServerUnavailable(host);
      case 500:
        if (message == 'Ocurrió un error inesperado.' ||
            message == 'Internal Server Error' ||
            _looksLikeHtml(message)) {
          message = 'Error en el servidor al procesar la solicitud.';
        }
    }

    if (_looksLikeHtml(message) || _looksLikeCloudflareError(message)) {
      message = _tunnelOrServerUnavailable(host);
    }

    return ApiException(message: message, statusCode: statusCode, code: code);
  }

  static String _tunnelOrServerUnavailable(String host) {
    final isTunnel = host.contains('trycloudflare.com') ||
        host.contains('ngrok') ||
        host.contains('cloudflare');
    if (isTunnel) {
      return 'El túnel del servidor no está disponible. '
          'Inicia de nuevo el túnel o cambia la URL en Ajustes.';
    }
    return 'El servidor no responde. Verifica que esté en marcha y la URL en Ajustes.';
  }

  static bool _looksLikeHtml(String value) {
    final lower = value.toLowerCase();
    return lower.contains('<html') ||
        lower.contains('<!doctype') ||
        lower.contains('<head') ||
        lower.contains('<body') ||
        lower.contains('<script');
  }

  static bool _looksLikeCloudflareError(String value) {
    final lower = value.toLowerCase();
    return lower.contains('cloudflare tunnel error') ||
        lower.contains('errorcode:1033') ||
        lower.contains('cf-error') ||
        lower.contains('trycloudflare.com');
  }

  /// Evita mostrar HTML crudo (p. ej. páginas de error de Cloudflare).
  static String? _sanitizeBodyMessage(String raw, {required String host}) {
    final value = raw.trim();
    if (value.isEmpty) return null;
    if (_looksLikeHtml(value) || _looksLikeCloudflareError(value)) {
      return _tunnelOrServerUnavailable(host);
    }
    if (value.length > 280) {
      return '${value.substring(0, 277).trimRight()}…';
    }
    return value;
  }

  @override
  String toString() => message;
}
