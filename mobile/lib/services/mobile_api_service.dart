import 'dart:io';

import 'package:dio/dio.dart';
import 'package:movil_architect/core/network/api_client.dart';
import 'package:movil_architect/core/network/api_exception.dart';
import 'package:movil_architect/core/utils/json_utils.dart';
import 'package:movil_architect/models/analysis_models.dart';
import 'package:movil_architect/models/app_config_models.dart';
import 'package:movil_architect/models/auth_models.dart';
import 'package:movil_architect/models/chat_models.dart';

class MobileApiService {
  MobileApiService({required ApiClient apiClient}) : _apiClient = apiClient;

  final ApiClient _apiClient;

  Future<HealthResponse> health() async {
    try {
      final response = await _apiClient.dio.get<dynamic>('/api/health');
      final data = asJsonMap(response.data);
      if (data.isEmpty && response.statusCode != null && response.statusCode! >= 400) {
        throw ApiException(
          message: 'Error en el servidor al procesar la solicitud.',
          statusCode: response.statusCode,
        );
      }
      return HealthResponse.fromJson(data);
    } on ApiException {
      rethrow;
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<MeResponse> me() async {
    try {
      final response = await _apiClient.dio.get<Map<String, dynamic>>(
        '/api/auth/me',
      );
      final data = response.data ?? {};
      if (data['ok'] == false) {
        throw ApiException(
          message: data['message'] as String? ??
              'No se pudo obtener el perfil del usuario.',
        );
      }
      return MeResponse.fromJson(data);
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<List<AnalysisSummary>> listAnalyses({int limit = 20}) async {
    try {
      final response = await _apiClient.dio.get<dynamic>(
        '/api/analyses',
        queryParameters: {'limit': limit},
      );
      final data = response.data;
      if (data is List) {
        return data
            .whereType<Map<String, dynamic>>()
            .map(AnalysisSummary.fromJson)
            .toList();
      }
      return [];
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<List<ChatSummary>> listChats({int limit = 40}) async {
    try {
      final response = await _apiClient.dio.get<dynamic>(
        '/api/chats',
        queryParameters: {'limit': limit},
      );
      final data = response.data;
      if (data is List) {
        return data
            .whereType<Map<String, dynamic>>()
            .map(ChatSummary.fromJson)
            .toList();
      }
      return [];
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<ChatDetail> getChat(String chatId) async {
    try {
      final response = await _apiClient.dio.get<Map<String, dynamic>>(
        '/api/chats/$chatId',
      );
      return ChatDetail.fromJson(response.data ?? {});
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<AnalysisResult> sendFollowup({
    required String message,
    required int analysisId,
    String? chatId,
  }) async {
    try {
      final response = await _apiClient.dio.post<Map<String, dynamic>>(
        '/api/analyze/followup',
        data: FormData.fromMap({
          'message': message.trim(),
          'analysis_id': analysisId.toString(),
          'auto_calibrate': '1',
          if (chatId != null && chatId.isNotEmpty) 'chat_id': chatId,
        }),
      );
      return AnalysisResult.fromJson(response.data ?? {});
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<AskResponse> sendAsk({
    required String message,
    String? chatId,
  }) async {
    try {
      final response = await _apiClient.dio.post<Map<String, dynamic>>(
        '/api/ask',
        data: FormData.fromMap({
          'message': message.trim(),
          if (chatId != null && chatId.isNotEmpty) 'chat_id': chatId,
        }),
      );
      return AskResponse.fromJson(response.data ?? {});
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<void> deleteChat(String chatId) async {
    try {
      await _apiClient.dio.delete<void>('/api/chats/$chatId');
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<ChatSummary> renameChat({
    required String chatId,
    required String title,
  }) async {
    try {
      final response = await _apiClient.dio.patch<dynamic>(
        '/api/chats/$chatId',
        data: {'title': title.trim()},
      );
      final map = asJsonMap(response.data);
      if (map['chat'] is Map) {
        return ChatSummary.fromJson(asJsonMap(map['chat']));
      }
      if (map.isNotEmpty && (map.containsKey('id') || map.containsKey('title'))) {
        return ChatSummary.fromJson(map);
      }
      return ChatSummary(
        id: chatId,
        title: title.trim(),
        updatedAt: DateTime.now(),
        messageCount: 0,
      );
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<AnalysisResult> analyze({
    required File file,
    String? message,
    String? chatId,
  }) async {
    try {
      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(
          file.path,
          filename: file.uri.pathSegments.last,
        ),
        'auto_calibrate': '1',
        if (message != null && message.trim().isNotEmpty)
          'message': message.trim(),
        if (chatId != null && chatId.isNotEmpty) 'chat_id': chatId,
      });

      final response = await _apiClient.dio.post<Map<String, dynamic>>(
        '/api/mobile/analyze',
        data: formData,
      );

      return AnalysisResult.fromJson(response.data ?? {});
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  /// Imagen anotada de un análisis (historial). 404 → null (sin preview).
  Future<String?> getAnnotatedImage(int analysisId) async {
    try {
      final response = await _apiClient.dio.get<Map<String, dynamic>>(
        '/api/analyses/$analysisId/annotated',
        queryParameters: {'format': 'base64'},
      );
      final data = response.data ?? {};
      final image = data['image_base64'];
      if (image is String && image.trim().isNotEmpty) return image.trim();
      return null;
    } on DioException catch (error) {
      if (error.response?.statusCode == 404) return null;
      throw ApiException.fromDio(error);
    }
  }

  Future<ChatSummary> createChat({String title = 'Nuevo chat'}) async {
    try {
      final response = await _apiClient.dio.post<dynamic>(
        '/api/chats',
        data: {'title': title},
      );
      final map = asJsonMap(response.data);
      if (map['chat'] is Map) {
        return ChatSummary.fromJson(asJsonMap(map['chat']));
      }
      return ChatSummary.fromJson(map);
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<PlanoPreview> previewPlano(File file) async {
    try {
      final response = await _apiClient.dio.post<Map<String, dynamic>>(
        '/api/plano/preview',
        data: FormData.fromMap({
          'file': await MultipartFile.fromFile(
            file.path,
            filename: file.uri.pathSegments.last,
          ),
        }),
      );
      return PlanoPreview.fromJson(response.data ?? {});
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<Map<String, dynamic>> getNorms() async {
    try {
      final response = await _apiClient.dio.get<dynamic>('/api/norms');
      return asJsonMap(response.data);
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<AppRemoteConfig> getConfig() async {
    try {
      final response = await _apiClient.dio.get<Map<String, dynamic>>('/api/config');
      return AppRemoteConfig.fromJson(response.data ?? {});
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<AskStatus> getAskStatus() async {
    try {
      final response =
          await _apiClient.dio.get<Map<String, dynamic>>('/api/ask/status');
      return AskStatus.fromJson(response.data ?? {});
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<AnalysisResult> correctDetection({
    required int analysisId,
    required int detectionIndex,
    required String action,
    String? newClass,
    String? note,
    String? chatId,
  }) async {
    try {
      final response = await _apiClient.dio.post<Map<String, dynamic>>(
        '/api/analyses/$analysisId/corrections',
        queryParameters: {
          if (chatId != null && chatId.isNotEmpty) 'chat_id': chatId,
        },
        data: {
          'detection_index': detectionIndex,
          'action': action,
          'new_class': newClass,
          'note': note ?? '',
        },
      );
      return AnalysisResult.fromJson(response.data ?? {});
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<AnalysisResult> correctFromMessage({
    required int analysisId,
    required String message,
    String? chatId,
  }) async {
    try {
      final response = await _apiClient.dio.post<Map<String, dynamic>>(
        '/api/analyses/$analysisId/correct-from-message',
        data: {
          'message': message.trim(),
          if (chatId != null && chatId.isNotEmpty) 'chat_id': chatId,
        },
      );
      return AnalysisResult.fromJson(response.data ?? {});
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }
}
