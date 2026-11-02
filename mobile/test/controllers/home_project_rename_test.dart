import 'package:flutter_test/flutter_test.dart';
import 'package:movil_architect/controllers/home_project_controller.dart';
import 'package:movil_architect/models/home_project_models.dart';
import 'package:movil_architect/services/home_project_service.dart';

class MockHomeProjectService implements HomeProjectService {
  String? renamedProjectId;
  String? renamedNewName;
  HomeProject? projectToReturn;

  @override
  Future<HomeProject> renameProject({
    required String projectId,
    required String name,
  }) async {
    renamedProjectId = projectId;
    renamedNewName = name;
    return projectToReturn ??
        HomeProject(
          id: projectId,
          name: name,
          code: 'HP-001',
          status: 'active',
          currentStage: 1,
          stagesCompleted: 0,
          totalBudget: 100000,
          spentBudget: 25000,
          progressPercent: 25.0,
          clientName: 'Juan Pérez',
          location: 'Tuxtla Gutiérrez, Chiapas',
          description: 'Proyecto demo',
          stages: const [],
          myRole: 'owner',
          permissions: const HomeProjectPermissions(
            canView: true,
            canEdit: true,
            canRenameProject: true,
            canUpload: true,
            canComment: true,
            canAdvanceStage: true,
            canDeleteProject: true,
            canDeleteDocuments: true,
            canCreateSection: true,
            canDeleteSection: true,
            canManageTeam: true,
            canReview: true,
            canAssign: true,
            canCompleteStage: true,
            canReopenSection: true,
            canReopenStage: true,
          ),
        );
  }

  @override
  Future<HomeProject> getProject(String projectId) async {
    return projectToReturn ??
        HomeProject(
          id: projectId,
          name: 'Casa Hogar Inicial',
          code: 'HP-001',
          status: 'active',
          currentStage: 1,
          stagesCompleted: 0,
          totalBudget: 100000,
          spentBudget: 25000,
          progressPercent: 25.0,
          clientName: 'Juan Pérez',
          location: 'Tuxtla Gutiérrez, Chiapas',
          description: 'Proyecto demo',
          stages: const [],
          myRole: 'owner',
          permissions: const HomeProjectPermissions(
            canView: true,
            canEdit: true,
            canRenameProject: true,
            canUpload: true,
            canComment: true,
            canAdvanceStage: true,
            canDeleteProject: true,
            canDeleteDocuments: true,
            canCreateSection: true,
            canDeleteSection: true,
            canManageTeam: true,
            canReview: true,
            canAssign: true,
            canCompleteStage: true,
            canReopenSection: true,
            canReopenStage: true,
          ),
        );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('HomeProjectPermissions', () {
    test('parses can_rename_project from JSON and falls back to can_edit', () {
      final jsonWithRename = {
        'can_view': true,
        'can_edit': false,
        'can_rename_project': true,
      };
      final perms1 = HomeProjectPermissions.fromJson(jsonWithRename);
      expect(perms1.canRenameProject, isTrue);

      final jsonWithEdit = {
        'can_view': true,
        'can_edit': true,
        'can_rename_project': false,
      };
      final perms2 = HomeProjectPermissions.fromJson(jsonWithEdit);
      expect(perms2.canRenameProject, isTrue);

      final jsonReadOnly = {
        'can_view': true,
        'can_edit': false,
        'can_rename_project': false,
      };
      final perms3 = HomeProjectPermissions.fromJson(jsonReadOnly);
      expect(perms3.canRenameProject, isFalse);
    });
  });

  group('HomeProjectDetailController rename', () {
    test('validates name length and invokes rename service', () async {
      final mockService = MockHomeProjectService();
      final controller = HomeProjectDetailController(
        projectId: 'proj-123',
        service: mockService,
      );

      // Cargar proyecto inicial
      await controller.load();
      expect(controller.project?.name, 'Casa Hogar Inicial');

      // Nombre demasiado corto
      final shortOk = await controller.renameProject('A');
      expect(shortOk, isFalse);
      expect(controller.actionError, contains('al menos 2 caracteres'));

      // Nombre válido
      final ok = await controller.renameProject('Residencia Los Pinos');
      expect(ok, isTrue);
      expect(mockService.renamedProjectId, 'proj-123');
      expect(mockService.renamedNewName, 'Residencia Los Pinos');
      expect(controller.project?.name, 'Residencia Los Pinos');
    });
  });
}

