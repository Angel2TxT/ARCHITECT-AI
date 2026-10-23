import 'package:dio/dio.dart';
import 'package:movil_architect/core/network/api_client.dart';
import 'package:movil_architect/core/network/api_exception.dart';
import 'package:movil_architect/core/utils/json_utils.dart';
import 'package:movil_architect/models/support_models.dart';

class SupportService {
  SupportService({required ApiClient apiClient}) : _apiClient = apiClient;

  final ApiClient _apiClient;

  Future<List<SupportTicket>> listTickets({int limit = 20}) async {
    try {
      final response = await _apiClient.dio.get<dynamic>(
        '/api/support/tickets',
        queryParameters: {'limit': limit},
      );
      final data = response.data;
      final list = data is List ? data : asJsonMap(data)['tickets'];
      if (list is! List) return [];
      return list
          .whereType<Map>()
          .map((e) => SupportTicket.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<SupportTicket> createTicket({
    required String subject,
    required String body,
    String priority = 'normal',
    String? relatedChatId,
    int? relatedAnalysisId,
  }) async {
    try {
      final response = await _apiClient.dio.post<dynamic>(
        '/api/support/tickets',
        data: {
          'subject': subject.trim(),
          'body': body.trim(),
          'priority': priority,
          'related_chat_id': relatedChatId,
          'related_analysis_id': relatedAnalysisId,
        },
      );
      final map = asJsonMap(response.data);
      if (map['ticket'] is Map) {
        return SupportTicket.fromJson(asJsonMap(map['ticket']));
      }
      return SupportTicket.fromJson(map);
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<SupportTicketDetail> getTicket(String ticketId) async {
    try {
      final response =
          await _apiClient.dio.get<dynamic>('/api/support/tickets/$ticketId');
      return SupportTicketDetail.fromJson(asJsonMap(response.data));
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<void> addMessage({
    required String ticketId,
    required String body,
  }) async {
    try {
      await _apiClient.dio.post<dynamic>(
        '/api/support/tickets/$ticketId/messages',
        data: {'body': body.trim()},
      );
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<void> deleteTicket(String ticketId) async {
    try {
      await _apiClient.dio.delete<void>('/api/support/tickets/$ticketId');
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<void> deleteAllTickets(List<String> ticketIds) async {
    try {
      await _apiClient.dio.delete<void>('/api/support/tickets');
    } on DioException catch (error) {
      if (error.response?.statusCode == 404 ||
          error.response?.statusCode == 405) {
        for (final id in ticketIds) {
          await deleteTicket(id);
        }
        return;
      }
      throw ApiException.fromDio(error);
    }
  }
}
