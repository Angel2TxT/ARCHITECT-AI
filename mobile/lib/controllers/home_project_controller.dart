import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:movil_architect/core/app_services.dart';
import 'package:movil_architect/core/network/api_exception.dart';
import 'package:movil_architect/core/storage/secure_storage_service.dart';
import 'package:movil_architect/models/home_project_models.dart';
import 'package:movil_architect/services/home_project_service.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

enum HomeProjectsState { loading, success, empty, error }

class HomeProjectsController extends ChangeNotifier {
  HomeProjectsController({
    HomeProjectService? service,
    SecureStorageService? secureStorage,
  })  : _service = service ?? AppServices.instance.homeProjectService,
        _secureStorage =
            secureStorage ?? AppServices.instance.secureStorage;

  final HomeProjectService _service;
  final SecureStorageService _secureStorage;
  bool _disposed = false;

  HomeProjectsState _state = HomeProjectsState.loading;
  String? _errorMessage;
  List<HomeProject> _projects = [];
  final Set<String> _pinnedIds = {};

  HomeProjectsState get state => _state;
  String? get errorMessage => _errorMessage;
  List<HomeProject> get projects => _projects;
  bool isPinned(String projectId) => _pinnedIds.contains(projectId);

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> load({bool refresh = false}) async {
    if (!refresh) {
      _state = HomeProjectsState.loading;
      _errorMessage = null;
      _notify();
    }

    try {
      final results = await Future.wait([
        _service.listProjects(),
        _secureStorage.getPinnedHomeProjectIds(),
      ]);
      if (_disposed) return;
      _projects = results[0] as List<HomeProject>;
      _pinnedIds
        ..clear()
        ..addAll(results[1] as List<String>);
      _pinnedIds.removeWhere(
        (id) => !_projects.any((project) => project.id == id),
      );
      _sortProjects();
      _state =
          _projects.isEmpty ? HomeProjectsState.empty : HomeProjectsState.success;
      _errorMessage = null;
    } on ApiException catch (error) {
      if (_disposed) return;
      _state = HomeProjectsState.error;
      _errorMessage = error.message;
    } catch (_) {
      if (_disposed) return;
      _state = HomeProjectsState.error;
      _errorMessage = 'No se pudieron cargar los proyectos.';
    }
    _notify();
  }

  Future<void> togglePin(String projectId) async {
    if (_pinnedIds.contains(projectId)) {
      _pinnedIds.remove(projectId);
    } else {
      _pinnedIds.add(projectId);
    }
    _sortProjects();
    _notify();
    try {
      await _secureStorage.savePinnedHomeProjectIds(_pinnedIds.toList());
    } catch (_) {}
  }

  Future<bool> deleteProject(String projectId) async {
    try {
      await _service.deleteProject(projectId);
      if (_disposed) return false;
      _projects = _projects.where((p) => p.id != projectId).toList();
      _pinnedIds.remove(projectId);
      await _secureStorage.savePinnedHomeProjectIds(_pinnedIds.toList());
      _state =
          _projects.isEmpty ? HomeProjectsState.empty : HomeProjectsState.success;
      _notify();
      return true;
    } on ApiException catch (error) {
      if (_disposed) return false;
      _errorMessage = error.message;
      _notify();
      return false;
    } catch (_) {
      if (_disposed) return false;
      _errorMessage = 'No se pudo eliminar el proyecto.';
      _notify();
      return false;
    }
  }

  Future<bool> updateProject(
    String projectId, {
    required String name,
    String? clientName,
    String? location,
    String? description,
  }) async {
    try {
      final updated = await _service.updateProject(
        projectId,
        name: name,
        clientName: clientName,
        location: location,
        description: description,
      );
      if (_disposed) return false;
      final index = _projects.indexWhere((p) => p.id == projectId);
      if (index >= 0) {
        _projects[index] = updated;
      }
      _sortProjects();
      _notify();
      return true;
    } on ApiException catch (error) {
      if (_disposed) return false;
      _errorMessage = error.message;
      _notify();
      return false;
    } catch (_) {
      if (_disposed) return false;
      _errorMessage = 'No se pudo actualizar el proyecto.';
      _notify();
      return false;
    }
  }

  void _sortProjects() {
    _projects.sort((a, b) {
      return a.name.trim().toLowerCase().compareTo(b.name.trim().toLowerCase());
    });
  }

  Future<HomeProjectCatalog?> loadCatalog() async {
    try {
      return await _service.getCatalog();
    } on ApiException catch (error) {
      _errorMessage = error.message;
      _notify();
      return null;
    } catch (_) {
      _errorMessage = 'No se pudo cargar el catálogo de etapas.';
      _notify();
      return null;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

class HomeProjectDetailController extends ChangeNotifier {
  HomeProjectDetailController({
    required this.projectId,
    HomeProjectService? service,
  }) : _service = service ?? AppServices.instance.homeProjectService;

  final String projectId;
  final HomeProjectService _service;
  bool _disposed = false;

  HomeProjectsState _state = HomeProjectsState.loading;
  String? _errorMessage;
  HomeProject? _project;
  bool _busy = false;
  String? _actionError;

  HomeProjectsState get state => _state;
  String? get errorMessage => _errorMessage;
  HomeProject? get project => _project;
  bool get busy => _busy;
  String? get actionError => _actionError;
  bool get isDisposed => _disposed;
  HomeProjectPermissions get permissions =>
      _project?.permissions ?? HomeProjectPermissions.empty;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> load({bool refresh = false}) async {
    if (_disposed) return;
    if (!refresh) {
      _state = HomeProjectsState.loading;
      _errorMessage = null;
      _notify();
    }

    try {
      final project = await _service.getProject(projectId);
      if (_disposed) return;
      _project = project;
      _state = HomeProjectsState.success;
      _errorMessage = null;
    } on ApiException catch (error) {
      if (_disposed) return;
      _state = HomeProjectsState.error;
      _errorMessage = error.message;
    } catch (_) {
      if (_disposed) return;
      _state = HomeProjectsState.error;
      _errorMessage = 'No se pudo cargar el proyecto.';
    }
    _notify();
  }

  Future<bool> advanceStage() async {
    if (_disposed || _busy || !permissions.canAdvanceStage) return false;
    _busy = true;
    _actionError = null;
    _notify();
    try {
      final project = await _service.advanceStage(projectId);
      if (_disposed) return false;
      _project = project;
      return true;
    } on ApiException catch (error) {
      if (_disposed) return false;
      _actionError = error.message;
      return false;
    } catch (_) {
      if (_disposed) return false;
      _actionError = 'No se pudo avanzar de etapa.';
      return false;
    } finally {
      if (!_disposed) {
        _busy = false;
        _notify();
      }
    }
  }

  Future<bool> deleteProject() async {
    if (_disposed || _busy || !permissions.canDeleteProject) return false;
    _busy = true;
    _actionError = null;
    _notify();
    try {
      await _service.deleteProject(projectId);
      return !_disposed;
    } on ApiException catch (error) {
      if (_disposed) return false;
      _actionError = error.message;
      return false;
    } catch (_) {
      if (_disposed) return false;
      _actionError = 'No se pudo eliminar el proyecto.';
      return false;
    } finally {
      if (!_disposed) {
        _busy = false;
        _notify();
      }
    }
  }

  Future<bool> updateSectionStatus({
    required int sectionId,
    required String status,
  }) async {
    if (_disposed || _busy || !permissions.canEdit) return false;
    _busy = true;
    _actionError = null;
    _notify();
    try {
      final project = await _service.updateSection(
        projectId: projectId,
        sectionId: sectionId,
        status: status,
      );
      if (_disposed) return false;
      _project = project;
      return true;
    } on ApiException catch (error) {
      if (_disposed) return false;
      _actionError = error.message;
      return false;
    } catch (_) {
      if (_disposed) return false;
      _actionError = 'No se pudo actualizar el apartado.';
      return false;
    } finally {
      if (!_disposed) {
        _busy = false;
        _notify();
      }
    }
  }

  Future<bool> uploadDocument({
    required int stageNumber,
    required int sectionId,
    required File file,
    String? slotKey,
  }) async {
    if (_disposed || _busy || !permissions.canUpload) return false;
    _busy = true;
    _actionError = null;
    _notify();
    try {
      await _service.uploadDocument(
        projectId: projectId,
        stageNumber: stageNumber,
        file: file,
        sectionId: sectionId,
        slotKey: slotKey,
      );
      if (_disposed) return false;
      await load(refresh: true);
      return !_disposed;
    } on ApiException catch (error) {
      if (_disposed) return false;
      _actionError = error.message;
      return false;
    } catch (_) {
      if (_disposed) return false;
      _actionError = 'No se pudo subir el documento.';
      return false;
    } finally {
      if (!_disposed) {
        _busy = false;
        _notify();
      }
    }
  }

  Future<bool> deleteDocument(int documentId) async {
    if (_disposed || _busy) return false;
    if (!permissions.canDeleteDocuments && !permissions.canEdit) return false;
    _busy = true;
    _actionError = null;
    _notify();
    try {
      await _service.deleteDocument(
        projectId: projectId,
        documentId: documentId,
      );
      if (_disposed) return false;
      await load(refresh: true);
      return !_disposed;
    } on ApiException catch (error) {
      if (_disposed) return false;
      _actionError = error.message;
      return false;
    } catch (_) {
      if (_disposed) return false;
      _actionError = 'No se pudo eliminar el documento.';
      return false;
    } finally {
      if (!_disposed) {
        _busy = false;
        _notify();
      }
    }
  }

  Future<String?> openDocument(HomeProjectDocument document) async {
    if (_disposed) return 'Proyecto cerrado.';
    try {
      final bytes = await _service.downloadDocumentBytes(
        projectId: projectId,
        documentId: document.id,
      );
      if (_disposed) return null;
      if (bytes.isEmpty) return 'El archivo está vacío.';

      final dir = await getTemporaryDirectory();
      final safeName = document.originalFilename.replaceAll(
        RegExp(r'[\\/:*?"<>|]'),
        '_',
      );
      final file = File('${dir.path}/casa_hogar_${document.id}_$safeName');
      await file.writeAsBytes(bytes, flush: true);
      if (_disposed) return null;
      final result = await OpenFilex.open(file.path);
      if (result.type != ResultType.done) {
        return result.message.isNotEmpty
            ? result.message
            : 'No se pudo abrir el archivo.';
      }
      return null;
    } on ApiException catch (error) {
      return error.message;
    } catch (_) {
      return 'No se pudo descargar el archivo.';
    }
  }

  Future<HomeProjectCommentsPage?> loadAllComments({
    required int sectionId,
    int limit = 50,
  }) async {
    if (_disposed) return null;
    try {
      return await _service.listComments(
        projectId: projectId,
        sectionId: sectionId,
        limit: limit,
      );
    } on ApiException catch (error) {
      _actionError = error.message;
      _notify();
      return null;
    } catch (_) {
      _actionError = 'No se pudieron cargar los comentarios.';
      _notify();
      return null;
    }
  }

  Future<bool> addComment({
    required int sectionId,
    required String body,
  }) async {
    if (_disposed || _busy || !permissions.canComment) return false;
    final text = body.trim();
    if (text.isEmpty || text.length > 4000) {
      _actionError = 'El comentario debe tener entre 1 y 4000 caracteres.';
      _notify();
      return false;
    }
    _busy = true;
    _actionError = null;
    _notify();
    try {
      final project = await _service.addComment(
        projectId: projectId,
        sectionId: sectionId,
        body: text,
      );
      if (_disposed) return false;
      _project = project;
      return true;
    } on ApiException catch (error) {
      if (_disposed) return false;
      _actionError = error.message;
      return false;
    } catch (_) {
      if (_disposed) return false;
      _actionError = 'No se pudo publicar el comentario.';
      return false;
    } finally {
      if (!_disposed) {
        _busy = false;
        _notify();
      }
    }
  }

  Future<bool> deleteComment({
    required int sectionId,
    required int commentId,
  }) async {
    if (_disposed || _busy) return false;
    _busy = true;
    _actionError = null;
    _notify();
    try {
      final project = await _service.deleteComment(
        projectId: projectId,
        sectionId: sectionId,
        commentId: commentId,
      );
      if (_disposed) return false;
      _project = project;
      return true;
    } on ApiException catch (error) {
      if (_disposed) return false;
      _actionError = error.message;
      return false;
    } catch (_) {
      if (_disposed) return false;
      _actionError = 'No se pudo eliminar el comentario.';
      return false;
    } finally {
      if (!_disposed) {
        _busy = false;
        _notify();
      }
    }
  }

  Future<String?> inviteMember({
    required String email,
    required String role,
  }) async {
    if (_disposed || _busy || !permissions.canManageTeam) {
      return 'Sin permiso para invitar.';
    }
    _busy = true;
    _actionError = null;
    _notify();
    try {
      final status = await _service.inviteMember(
        projectId: projectId,
        email: email,
        role: role,
      );
      if (_disposed) return null;
      await load(refresh: true);
      return status;
    } on ApiException catch (error) {
      if (_disposed) return null;
      _actionError = error.message;
      return null;
    } catch (_) {
      if (_disposed) return null;
      _actionError = 'No se pudo enviar la invitación.';
      return null;
    } finally {
      if (!_disposed) {
        _busy = false;
        _notify();
      }
    }
  }

  Future<bool> removeMember(int userId) async {
    if (_disposed || _busy || !permissions.canManageTeam) return false;
    _busy = true;
    _actionError = null;
    _notify();
    try {
      final project = await _service.removeMember(
        projectId: projectId,
        userId: userId,
      );
      if (_disposed) return false;
      _project = project;
      return true;
    } on ApiException catch (error) {
      if (_disposed) return false;
      _actionError = error.message;
      return false;
    } catch (_) {
      if (_disposed) return false;
      _actionError = 'No se pudo quitar al miembro.';
      return false;
    } finally {
      if (!_disposed) {
        _busy = false;
        _notify();
      }
    }
  }

  Future<StageAssistResult?> requestAssist({
    required int stageNumber,
    String question = '',
  }) async {
    if (_disposed || _busy || !permissions.canEdit) return null;
    _busy = true;
    _actionError = null;
    _notify();
    try {
      final result = await _service.stageAssist(
        projectId: projectId,
        stageNumber: stageNumber,
        question: question,
      );
      if (_disposed) return null;
      await load(refresh: true);
      return result;
    } on ApiException catch (error) {
      if (_disposed) return null;
      _actionError = error.message;
      return null;
    } catch (_) {
      if (_disposed) return null;
      _actionError = 'No se pudo obtener asistencia IA.';
      return null;
    } finally {
      if (!_disposed) {
        _busy = false;
        _notify();
      }
    }
  }

  Future<List<LinkedAnalysisSummary>> loadAnalysesPicker() async {
    try {
      return await _service.analysesPicker();
    } on ApiException catch (error) {
      _actionError = error.message;
      _notify();
      return [];
    } catch (_) {
      _actionError = 'No se pudieron cargar los análisis.';
      _notify();
      return [];
    }
  }

  Future<bool> linkStageAnalysis({
    required int stageNumber,
    required int analysisId,
  }) async {
    if (_disposed || _busy || !permissions.canEdit) return false;
    _busy = true;
    _actionError = null;
    _notify();
    try {
      final project = await _service.linkStageAnalysis(
        projectId: projectId,
        stageNumber: stageNumber,
        analysisId: analysisId,
      );
      if (_disposed) return false;
      _project = project;
      return true;
    } on ApiException catch (error) {
      if (_disposed) return false;
      _actionError = error.message;
      return false;
    } catch (_) {
      if (_disposed) return false;
      _actionError = 'No se pudo vincular el plano.';
      return false;
    } finally {
      if (!_disposed) {
        _busy = false;
        _notify();
      }
    }
  }

  Future<HomeProjectEventsPage?> loadEvents({
    int limit = 50,
    int offset = 0,
  }) async {
    try {
      return await _service.listEvents(
        projectId: projectId,
        limit: limit,
        offset: offset,
      );
    } on ApiException catch (error) {
      _actionError = error.message;
      _notify();
      return null;
    } catch (_) {
      _actionError = 'No se pudo cargar la actividad.';
      _notify();
      return null;
    }
  }

  Future<bool> createSection({
    required int stageNumber,
    required String title,
    String? description,
  }) async {
    if (_disposed || _busy || !permissions.canCreateSection) return false;
    _busy = true;
    _actionError = null;
    _notify();
    try {
      final project = await _service.createSection(
        projectId: projectId,
        stageNumber: stageNumber,
        title: title,
        description: description,
      );
      if (_disposed) return false;
      _project = project;
      return true;
    } on ApiException catch (error) {
      if (_disposed) return false;
      _actionError = error.message;
      return false;
    } catch (_) {
      if (_disposed) return false;
      _actionError = 'No se pudo crear el apartado.';
      return false;
    } finally {
      if (!_disposed) {
        _busy = false;
        _notify();
      }
    }
  }

  Future<bool> deleteSection(int sectionId) async {
    if (_disposed || _busy || !permissions.canDeleteSection) return false;
    _busy = true;
    _actionError = null;
    _notify();
    try {
      final project = await _service.deleteSection(
        projectId: projectId,
        sectionId: sectionId,
      );
      if (_disposed) return false;
      _project = project;
      return true;
    } on ApiException catch (error) {
      if (_disposed) return false;
      _actionError = error.message;
      return false;
    } catch (_) {
      if (_disposed) return false;
      _actionError = 'No se pudo eliminar el apartado.';
      return false;
    } finally {
      if (!_disposed) {
        _busy = false;
        _notify();
      }
    }
  }

  Future<bool> createSlot({
    required int sectionId,
    required String title,
    String? accept,
    bool? required,
    bool? aiPlanReview,
  }) async {
    if (_disposed || _busy || !permissions.canEdit) return false;
    _busy = true;
    _actionError = null;
    _notify();
    try {
      final project = await _service.createSlot(
        projectId: projectId,
        sectionId: sectionId,
        title: title,
        accept: accept,
        required: required,
        aiPlanReview: aiPlanReview,
      );
      if (_disposed) return false;
      _project = project;
      return true;
    } on ApiException catch (error) {
      if (_disposed) return false;
      _actionError = error.message;
      return false;
    } catch (_) {
      if (_disposed) return false;
      _actionError = 'No se pudo crear el slot.';
      return false;
    } finally {
      if (!_disposed) {
        _busy = false;
        _notify();
      }
    }
  }

  Future<bool> deleteSlot({
    required int sectionId,
    required String slotKey,
  }) async {
    if (_disposed || _busy || !permissions.canEdit) return false;
    _busy = true;
    _actionError = null;
    _notify();
    try {
      final project = await _service.deleteSlot(
        projectId: projectId,
        sectionId: sectionId,
        slotKey: slotKey,
      );
      if (_disposed) return false;
      _project = project;
      return true;
    } on ApiException catch (error) {
      if (_disposed) return false;
      _actionError = error.message;
      return false;
    } catch (_) {
      if (_disposed) return false;
      _actionError = 'No se pudo eliminar el slot.';
      return false;
    } finally {
      if (!_disposed) {
        _busy = false;
        _notify();
      }
    }
  }

  Future<HomeProjectAiReview?> createAiReview({
    required int stageNumber,
    required int documentId,
    int? sectionId,
    String? message,
    Map<String, dynamic>? weights,
  }) async {
    if (_disposed || _busy || !permissions.canReview) return null;
    _busy = true;
    _actionError = null;
    _notify();
    try {
      final review = await _service.createAiReview(
        projectId: projectId,
        stageNumber: stageNumber,
        documentId: documentId,
        sectionId: sectionId,
        message: message,
        weights: weights,
      );
      if (_disposed) return null;
      await load(refresh: true);
      return review;
    } on ApiException catch (error) {
      if (_disposed) return null;
      _actionError = error.message;
      return null;
    } catch (_) {
      if (_disposed) return null;
      _actionError = 'No se pudo iniciar la revisión IA.';
      return null;
    } finally {
      if (!_disposed) {
        _busy = false;
        _notify();
      }
    }
  }

  Future<HomeProjectAiReview?> updateAiFinding({
    required int reviewId,
    required int findingId,
    required String action,
    String? note,
  }) async {
    if (_disposed || _busy || !permissions.canReview) return null;
    _busy = true;
    _actionError = null;
    _notify();
    try {
      final review = await _service.updateAiFinding(
        projectId: projectId,
        reviewId: reviewId,
        findingId: findingId,
        action: action,
        note: note,
      );
      if (_disposed) return null;
      return review;
    } on ApiException catch (error) {
      if (_disposed) return null;
      _actionError = error.message;
      return null;
    } catch (_) {
      if (_disposed) return null;
      _actionError = 'No se pudo actualizar el hallazgo.';
      return null;
    } finally {
      if (!_disposed) {
        _busy = false;
        _notify();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

class CreateHomeProjectController extends ChangeNotifier {
  CreateHomeProjectController({HomeProjectService? service})
      : _service = service ?? AppServices.instance.homeProjectService;

  final HomeProjectService _service;
  bool _disposed = false;

  bool _isLoading = false;
  String? _errorMessage;

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<HomeProject?> create({
    required String name,
    String? clientName,
    String? location,
    String? description,
  }) async {
    final trimmed = name.trim();
    if (trimmed.length < 2) {
      _errorMessage = 'El nombre debe tener al menos 2 caracteres.';
      _notify();
      return null;
    }
    if (trimmed.length > 160) {
      _errorMessage = 'El nombre no puede superar 160 caracteres.';
      _notify();
      return null;
    }
    if ((clientName ?? '').trim().length > 120) {
      _errorMessage = 'El cliente no puede superar 120 caracteres.';
      _notify();
      return null;
    }
    if ((location ?? '').trim().length > 200) {
      _errorMessage = 'La ubicación no puede superar 200 caracteres.';
      _notify();
      return null;
    }
    if ((description ?? '').trim().length > 4000) {
      _errorMessage = 'La descripción no puede superar 4000 caracteres.';
      _notify();
      return null;
    }

    _isLoading = true;
    _errorMessage = null;
    _notify();

    try {
      final project = await _service.createProject(
        name: trimmed,
        clientName: clientName,
        location: location,
        description: description,
      );
      if (_disposed) return null;
      _isLoading = false;
      // No notify: la pantalla navega de inmediato al detalle.
      return project;
    } on ApiException catch (error) {
      if (_disposed) return null;
      _errorMessage = error.message;
      _isLoading = false;
      _notify();
      return null;
    } catch (_) {
      if (_disposed) return null;
      _errorMessage = 'No se pudo crear el proyecto.';
      _isLoading = false;
      _notify();
      return null;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
