import 'dart:io';

import 'package:dio/dio.dart';
import 'package:movil_architect/core/network/api_client.dart';
import 'package:movil_architect/core/network/api_exception.dart';
import 'package:movil_architect/models/home_project_models.dart';

class HomeProjectService {
  HomeProjectService({required ApiClient apiClient}) : _apiClient = apiClient;

  final ApiClient _apiClient;

  static const _base = '/api/home-projects';

  Map<String, dynamic> _map(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return {};
  }

  HomeProject _projectFrom(dynamic data) {
    final map = _map(data);
    if (map['project'] is Map) {
      return HomeProject.fromJson(_map(map['project']));
    }
    if (map['id'] != null) {
      return HomeProject.fromJson(map);
    }
    throw ApiException(message: 'Respuesta inválida del servidor.');
  }

  List<HomeProject> _projectsFrom(dynamic data) {
    if (data is List) {
      return data
          .whereType<Map>()
          .map((e) => HomeProject.fromJson(_map(e)))
          .toList();
    }
    final map = _map(data);
    final list = map['projects'] ?? map['items'] ?? map['data'];
    if (list is List) {
      return list
          .whereType<Map>()
          .map((e) => HomeProject.fromJson(_map(e)))
          .toList();
    }
    return [];
  }

  Future<List<HomeProject>> listProjects() async {
    try {
      final response = await _apiClient.dio.get<dynamic>(_base);
      return _projectsFrom(response.data);
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<HomeProject> getProject(String projectId) async {
    try {
      final response = await _apiClient.dio.get<dynamic>('$_base/$projectId');
      return _projectFrom(response.data);
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<HomeProject> createProject({
    required String name,
    String? clientName,
    String? location,
    String? description,
  }) async {
    try {
      final response = await _apiClient.dio.post<dynamic>(
        _base,
        data: {
          'name': name.trim(),
          'client_name': clientName?.trim() ?? '',
          'location': location?.trim() ?? '',
          'description': description?.trim() ?? '',
        },
      );
      return _projectFrom(response.data);
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<HomeProject> updateProject(
    String projectId, {
    String? name,
    String? clientName,
    String? location,
    String? description,
    String? status,
  }) async {
    try {
      final body = <String, dynamic>{};
      if (name != null) body['name'] = name.trim();
      if (clientName != null) body['client_name'] = clientName.trim();
      if (location != null) body['location'] = location.trim();
      if (description != null) body['description'] = description.trim();
      if (status != null) body['status'] = status;

      final response = await _apiClient.dio.patch<dynamic>(
        '$_base/$projectId',
        data: body,
      );
      return _projectFrom(response.data);
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<HomeProject> renameProject({
    required String projectId,
    required String name,
  }) async {
    try {
      final response = await _apiClient.dio.patch<dynamic>(
        '$_base/$projectId/rename',
        data: {'name': name.trim()},
      );
      return _projectFrom(response.data);
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<void> deleteProject(String projectId) async {
    try {
      await _apiClient.dio.delete<void>('$_base/$projectId');
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<HomeProject> updateSection({
    required String projectId,
    required int sectionId,
    String? status,
    String? title,
    String? description,
  }) async {
    try {
      final body = <String, dynamic>{};
      if (status != null) body['status'] = status;
      if (title != null) body['title'] = title;
      if (description != null) body['description'] = description;

      final response = await _apiClient.dio.patch<dynamic>(
        '$_base/$projectId/sections/$sectionId',
        data: body,
      );
      final map = _map(response.data);
      if (map['project'] is Map || map['id'] != null) {
        return _projectFrom(map);
      }
      // Si solo devolvió el apartado, recargar proyecto.
      return getProject(projectId);
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<HomeProjectDocument> uploadDocument({
    required String projectId,
    required int stageNumber,
    required File file,
    int? sectionId,
    String? slotKey,
  }) async {
    try {
      final safeKey = (slotKey != null && slotKey.trim().isNotEmpty)
          ? slotKey.trim()
          : 'general';

      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(
          file.path,
          filename: file.uri.pathSegments.isNotEmpty
              ? file.uri.pathSegments.last
              : 'archivo',
        ),
        'section_id': ?sectionId,
        'slot_key': safeKey,
        'delivery_type': safeKey,
      });

      final response = await _apiClient.dio.post<dynamic>(
        '$_base/$projectId/stages/$stageNumber/documents',
        data: formData,
      );
      final map = _map(response.data);
      final doc = map['document'] ?? map['file'] ?? map;
      return HomeProjectDocument.fromJson(_map(doc));
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<List<int>> downloadDocumentBytes({
    required String projectId,
    required int documentId,
  }) async {
    try {
      final response = await _apiClient.dio.get<List<int>>(
        '$_base/$projectId/documents/$documentId/file',
        options: Options(responseType: ResponseType.bytes),
      );
      return response.data ?? [];
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<void> deleteDocument({
    required String projectId,
    required int documentId,
  }) async {
    try {
      await _apiClient.dio.delete<void>(
        '$_base/$projectId/documents/$documentId',
      );
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<HomeProject> advanceStage(String projectId) async {
    try {
      final response =
          await _apiClient.dio.post<dynamic>('$_base/$projectId/advance');
      return _projectFrom(response.data);
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<HomeProjectCommentsPage> listComments({
    required String projectId,
    required int sectionId,
    int limit = 50,
    int offset = 0,
  }) async {
    try {
      final response = await _apiClient.dio.get<dynamic>(
        '$_base/$projectId/sections/$sectionId/comments',
        queryParameters: {'limit': limit, 'offset': offset},
      );
      final map = _map(response.data);
      final list = map['comments'] ?? map['items'] ?? map['data'];
      final comments = list is List
          ? list
              .whereType<Map>()
              .map((e) => HomeProjectComment.fromJson(_map(e)))
              .toList()
          : <HomeProjectComment>[];
      final total = (map['total'] as num?)?.toInt() ?? comments.length;
      return HomeProjectCommentsPage(comments: comments, total: total);
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<HomeProject> addComment({
    required String projectId,
    required int sectionId,
    required String body,
  }) async {
    try {
      final response = await _apiClient.dio.post<dynamic>(
        '$_base/$projectId/sections/$sectionId/comments',
        data: {'body': body.trim()},
      );
      return _projectFrom(response.data);
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<HomeProject> deleteComment({
    required String projectId,
    required int sectionId,
    required int commentId,
  }) async {
    try {
      final response = await _apiClient.dio.delete<dynamic>(
        '$_base/$projectId/sections/$sectionId/comments/$commentId',
      );
      final map = _map(response.data);
      if (map.isEmpty) return getProject(projectId);
      return _projectFrom(map);
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<String> inviteMember({
    required String projectId,
    required String email,
    required String role,
  }) async {
    try {
      final response = await _apiClient.dio.post<dynamic>(
        '$_base/$projectId/members/invite',
        data: {
          'email': email.trim(),
          'role': role,
        },
      );
      final map = _map(response.data);
      return map['status']?.toString() ??
          map['message']?.toString() ??
          'Invitación enviada';
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<HomeProject> removeMember({
    required String projectId,
    required int userId,
  }) async {
    try {
      final response = await _apiClient.dio.delete<dynamic>(
        '$_base/$projectId/members/$userId',
      );
      return _projectFrom(response.data);
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<HomeProject> acceptInvite(String token) async {
    try {
      final response = await _apiClient.dio.post<dynamic>(
        '$_base/invites/accept',
        data: {'token': token.trim()},
      );
      return _projectFrom(response.data);
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<StageAssistResult> stageAssist({
    required String projectId,
    required int stageNumber,
    String question = '',
  }) async {
    try {
      final response = await _apiClient.dio.post<dynamic>(
        '$_base/$projectId/stages/$stageNumber/assist',
        data: {'question': question.trim()},
      );
      final map = _map(response.data);
      return StageAssistResult.fromJson(map);
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<List<LinkedAnalysisSummary>> analysesPicker({int limit = 30}) async {
    try {
      final response = await _apiClient.dio.get<dynamic>(
        '$_base/analyses-picker',
        queryParameters: {'limit': limit},
      );
      final map = _map(response.data);
      final list = map['analyses'] ?? map['items'] ?? response.data;
      if (list is! List) return [];
      return list
          .whereType<Map>()
          .map((e) => LinkedAnalysisSummary.fromJson(_map(e)))
          .toList();
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<HomeProject> linkStageAnalysis({
    required String projectId,
    required int stageNumber,
    required int analysisId,
  }) async {
    try {
      final response = await _apiClient.dio.patch<dynamic>(
        '$_base/$projectId/stages/$stageNumber',
        data: {'analysis_id': analysisId},
      );
      return _projectFrom(response.data);
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  /// Catálogo de 9 etapas (sin auth).
  Future<HomeProjectCatalog> getCatalog() async {
    try {
      final response = await _apiClient.dio.get<dynamic>('$_base/catalog');
      return HomeProjectCatalog.fromJson(_map(response.data));
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<HomeProjectEventsPage> listEvents({
    required String projectId,
    int limit = 50,
    int offset = 0,
  }) async {
    try {
      final response = await _apiClient.dio.get<dynamic>(
        '$_base/$projectId/events',
        queryParameters: {'limit': limit, 'offset': offset},
      );
      final map = _map(response.data);
      final list = map['events'] ?? map['items'] ?? map['data'];
      final events = list is List
          ? list
              .whereType<Map>()
              .map((e) => HomeProjectEvent.fromJson(_map(e)))
              .toList()
          : <HomeProjectEvent>[];
      final total = (map['total'] as num?)?.toInt() ?? events.length;
      return HomeProjectEventsPage(events: events, total: total);
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<HomeProject> createSection({
    required String projectId,
    required int stageNumber,
    required String title,
    String? description,
  }) async {
    try {
      final response = await _apiClient.dio.post<dynamic>(
        '$_base/$projectId/stages/$stageNumber/sections',
        data: {
          'title': title.trim(),
          if (description != null && description.trim().isNotEmpty)
            'description': description.trim(),
        },
      );
      return _projectFrom(response.data);
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<HomeProject> deleteSection({
    required String projectId,
    required int sectionId,
  }) async {
    try {
      final response = await _apiClient.dio.delete<dynamic>(
        '$_base/$projectId/sections/$sectionId',
      );
      final map = _map(response.data);
      if (map.isEmpty) return getProject(projectId);
      return _projectFrom(map);
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<HomeProject> createSlot({
    required String projectId,
    required int sectionId,
    required String title,
    String? accept,
    bool? required,
    bool? aiPlanReview,
  }) async {
    try {
      final response = await _apiClient.dio.post<dynamic>(
        '$_base/$projectId/sections/$sectionId/slots',
        data: {
          'title': title.trim(),
          'accept': ?accept,
          'required': ?required,
          'ai_plan_review': ?aiPlanReview,
        },
      );
      return _projectFrom(response.data);
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<HomeProject> deleteSlot({
    required String projectId,
    required int sectionId,
    required String slotKey,
  }) async {
    try {
      final response = await _apiClient.dio.delete<dynamic>(
        '$_base/$projectId/sections/$sectionId/slots/$slotKey',
      );
      final map = _map(response.data);
      if (map.isEmpty) return getProject(projectId);
      return _projectFrom(map);
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<HomeProjectAiReview> createAiReview({
    required String projectId,
    required int stageNumber,
    required int documentId,
    int? sectionId,
    String? message,
    Map<String, dynamic>? weights,
  }) async {
    try {
      final response = await _apiClient.dio.post<dynamic>(
        '$_base/$projectId/stages/$stageNumber/ai-reviews',
        data: {
          'document_id': documentId,
          'section_id': ?sectionId,
          if (message != null && message.trim().isNotEmpty)
            'message': message.trim(),
          'weights': ?weights,
        },
      );
      final map = _map(response.data);
      final review = map['review'] ?? map['ai_review'] ?? map;
      return HomeProjectAiReview.fromJson(_map(review));
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<HomeProjectAiReview> updateAiFinding({
    required String projectId,
    required int reviewId,
    required int findingId,
    required String action,
    String? note,
  }) async {
    try {
      final response = await _apiClient.dio.patch<dynamic>(
        '$_base/$projectId/ai-reviews/$reviewId/findings/$findingId',
        data: {
          'action': action,
          if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
        },
      );
      final map = _map(response.data);
      final review = map['review'] ?? map['ai_review'] ?? map;
      return HomeProjectAiReview.fromJson(_map(review));
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }
}
