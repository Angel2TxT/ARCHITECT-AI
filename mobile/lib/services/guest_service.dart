import 'dart:io';

import 'package:dio/dio.dart';
import 'package:movil_architect/core/network/api_client.dart';
import 'package:movil_architect/core/network/api_exception.dart';
import 'package:movil_architect/models/analysis_models.dart';
import 'package:movil_architect/models/app_config_models.dart';
import 'package:movil_architect/models/chat_models.dart';

class GuestService {
  GuestService({required ApiClient apiClient}) : _apiClient = apiClient;

  final ApiClient _apiClient;

  Future<GuestStatus> status() async {
    try {
      final response =
          await _apiClient.dio.get<Map<String, dynamic>>('/api/guest/status');
      return GuestStatus.fromJson(response.data ?? {});
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<AnalysisResult> analyze({
    required File file,
    String? message,
    bool autoCalibrate = true,
    double? ppm,
    double? conf,
  }) async {
    try {
      final response = await _apiClient.dio.post<Map<String, dynamic>>(
        '/api/guest/analyze',
        data: FormData.fromMap({
          'file': await MultipartFile.fromFile(
            file.path,
            filename: file.uri.pathSegments.last,
          ),
          'auto_calibrate': autoCalibrate ? '1' : '0',
          if (ppm != null) 'ppm': ppm.toString(),
          if (conf != null) 'conf': conf.toString(),
          if (message != null && message.trim().isNotEmpty)
            'message': message.trim(),
        }),
      );
      return AnalysisResult.fromJson(response.data ?? {});
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<AskResponse> ask(String message) async {
    try {
      final response = await _apiClient.dio.post<Map<String, dynamic>>(
        '/api/guest/ask',
        data: FormData.fromMap({'message': message.trim()}),
      );
      return AskResponse.fromJson(response.data ?? {});
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<PlanoPreview> preview(File file) async {
    try {
      final response = await _apiClient.dio.post<Map<String, dynamic>>(
        '/api/guest/preview',
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
}
