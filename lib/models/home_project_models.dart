class HomeProjectPermissions {
  const HomeProjectPermissions({
    required this.canView,
    required this.canEdit,
    required this.canUpload,
    required this.canComment,
    required this.canAdvanceStage,
    required this.canDeleteProject,
    required this.canDeleteDocuments,
    required this.canCreateSection,
    required this.canDeleteSection,
    required this.canManageTeam,
    required this.canReview,
    required this.canAssign,
    required this.canCompleteStage,
    required this.canReopenSection,
    required this.canReopenStage,
  });

  final bool canView;
  final bool canEdit;
  final bool canUpload;
  final bool canComment;
  final bool canAdvanceStage;
  final bool canDeleteProject;
  final bool canDeleteDocuments;
  final bool canCreateSection;
  final bool canDeleteSection;
  final bool canManageTeam;
  final bool canReview;
  final bool canAssign;
  final bool canCompleteStage;
  final bool canReopenSection;
  final bool canReopenStage;

  factory HomeProjectPermissions.fromJson(Map<String, dynamic>? json) {
    bool flag(String key) => json?[key] == true;
    return HomeProjectPermissions(
      canView: flag('can_view'),
      canEdit: flag('can_edit'),
      canUpload: flag('can_upload'),
      canComment: flag('can_comment'),
      canAdvanceStage: flag('can_advance_stage'),
      canDeleteProject: flag('can_delete_project'),
      canDeleteDocuments: flag('can_delete_documents'),
      canCreateSection: flag('can_create_section'),
      canDeleteSection: flag('can_delete_section'),
      canManageTeam: flag('can_manage_team'),
      canReview: flag('can_review'),
      canAssign: flag('can_assign'),
      canCompleteStage: flag('can_complete_stage'),
      canReopenSection: flag('can_reopen_section'),
      canReopenStage: flag('can_reopen_stage'),
    );
  }

  static const empty = HomeProjectPermissions(
    canView: false,
    canEdit: false,
    canUpload: false,
    canComment: false,
    canAdvanceStage: false,
    canDeleteProject: false,
    canDeleteDocuments: false,
    canCreateSection: false,
    canDeleteSection: false,
    canManageTeam: false,
    canReview: false,
    canAssign: false,
    canCompleteStage: false,
    canReopenSection: false,
    canReopenStage: false,
  );
}

class SectionsProgress {
  const SectionsProgress({
    required this.done,
    required this.total,
    required this.withFiles,
    required this.needsAction,
    required this.withoutDocs,
    required this.assigned,
  });

  final int done;
  final int total;
  final int withFiles;
  final int needsAction;
  final int withoutDocs;
  final int assigned;

  factory SectionsProgress.fromJson(Map<String, dynamic>? json) {
    int n(String key) => (json?[key] as num?)?.toInt() ?? 0;
    return SectionsProgress(
      done: n('done'),
      total: n('total'),
      withFiles: n('with_files'),
      needsAction: n('needs_action'),
      withoutDocs: n('without_docs'),
      assigned: n('assigned'),
    );
  }

  static const empty = SectionsProgress(
    done: 0,
    total: 0,
    withFiles: 0,
    needsAction: 0,
    withoutDocs: 0,
    assigned: 0,
  );
}

class HomeProjectDocument {
  const HomeProjectDocument({
    required this.id,
    required this.originalFilename,
    required this.mimeType,
    required this.fileSize,
    this.sectionId,
    this.stageNumber,
    this.slotKey,
    this.createdAt,
  });

  final int id;
  final String originalFilename;
  final String mimeType;
  final int fileSize;
  final int? sectionId;
  final int? stageNumber;
  final String? slotKey;
  final DateTime? createdAt;

  factory HomeProjectDocument.fromJson(Map<String, dynamic> json) {
    return HomeProjectDocument(
      id: (json['id'] as num?)?.toInt() ?? 0,
      originalFilename: json['original_filename'] as String? ??
          json['filename'] as String? ??
          'archivo',
      mimeType: json['mime_type'] as String? ??
          json['content_type'] as String? ??
          'application/octet-stream',
      fileSize: (json['file_size'] as num?)?.toInt() ??
          (json['size'] as num?)?.toInt() ??
          0,
      sectionId: (json['section_id'] as num?)?.toInt(),
      stageNumber: (json['stage_number'] as num?)?.toInt(),
      slotKey: json['slot_key'] as String? ??
          json['delivery_type'] as String? ??
          json['slot'] as String?,
      createdAt: parseHomeDate(json['created_at']),
    );
  }

  bool get isImage =>
      mimeType.startsWith('image/') ||
      originalFilename.toLowerCase().endsWith('.png') ||
      originalFilename.toLowerCase().endsWith('.jpg') ||
      originalFilename.toLowerCase().endsWith('.jpeg') ||
      originalFilename.toLowerCase().endsWith('.webp');
}

class HomeProjectComment {
  const HomeProjectComment({
    required this.id,
    required this.body,
    required this.authorName,
    required this.authorEmail,
    this.userId,
    this.createdAt,
  });

  final int id;
  final String body;
  final String authorName;
  final String authorEmail;
  final int? userId;
  final DateTime? createdAt;

  factory HomeProjectComment.fromJson(Map<String, dynamic> json) {
    final author = json['author'] ?? json['user'];
    String name = json['full_name'] as String? ??
        json['author_name'] as String? ??
        '';
    String email = json['email'] as String? ??
        json['author_email'] as String? ??
        '';
    int? userId = (json['user_id'] as num?)?.toInt() ??
        (json['author_id'] as num?)?.toInt();

    if (author is Map) {
      final map = Map<String, dynamic>.from(author);
      name = name.isNotEmpty
          ? name
          : (map['full_name'] as String? ?? map['name'] as String? ?? '');
      email = email.isNotEmpty ? email : (map['email'] as String? ?? '');
      userId ??= (map['id'] as num?)?.toInt();
    }

    return HomeProjectComment(
      id: (json['id'] as num?)?.toInt() ?? 0,
      body: json['body'] as String? ?? json['text'] as String? ?? '',
      authorName: name.isNotEmpty ? name : (email.isNotEmpty ? email : 'Usuario'),
      authorEmail: email,
      userId: userId,
      createdAt: parseHomeDate(json['created_at']),
    );
  }
}

class HomeProjectCommentsPage {
  const HomeProjectCommentsPage({
    required this.comments,
    required this.total,
  });

  final List<HomeProjectComment> comments;
  final int total;
}

class HomeProjectMember {
  const HomeProjectMember({
    required this.userId,
    required this.email,
    required this.fullName,
    required this.role,
  });

  final int userId;
  final String email;
  final String fullName;
  final String role;

  bool get isOwner => role == 'owner';

  factory HomeProjectMember.fromJson(Map<String, dynamic> json) {
    return HomeProjectMember(
      userId: (json['user_id'] as num?)?.toInt() ??
          (json['id'] as num?)?.toInt() ??
          0,
      email: json['email'] as String? ?? '',
      fullName: json['full_name'] as String? ?? '',
      role: json['role'] as String? ?? 'viewer',
    );
  }
}

class LinkedAnalysisSummary {
  const LinkedAnalysisSummary({
    required this.id,
    required this.filename,
    this.createdAt,
    this.chatId,
    this.counts,
  });

  final int id;
  final String filename;
  final DateTime? createdAt;
  final String? chatId;
  final Map<String, dynamic>? counts;

  factory LinkedAnalysisSummary.fromJson(Map<String, dynamic> json) {
    return LinkedAnalysisSummary(
      id: (json['id'] as num?)?.toInt() ??
          (json['analysis_id'] as num?)?.toInt() ??
          0,
      filename: json['filename'] as String? ??
          json['original_filename'] as String? ??
          'Análisis #${json['id'] ?? ''}',
      createdAt: parseHomeDate(json['created_at']),
      chatId: json['chat_id']?.toString(),
      counts: json['counts'] is Map
          ? Map<String, dynamic>.from(json['counts'] as Map)
          : null,
    );
  }
}

class StageAssistResult {
  const StageAssistResult({
    required this.stageNumber,
    required this.guidance,
    required this.localSources,
    required this.webSources,
    required this.planReviewRecommended,
    this.thresholds,
  });

  final int stageNumber;
  final String guidance;
  final List<String> localSources;
  final List<String> webSources;
  final bool planReviewRecommended;
  final Map<String, dynamic>? thresholds;

  factory StageAssistResult.fromJson(Map<String, dynamic> json) {
    List<String> sources(dynamic value) {
      if (value is! List) return const [];
      return value.map((e) {
        if (e is String) return e;
        if (e is Map) {
          return (e['title'] ?? e['url'] ?? e['name'] ?? e.toString())
              .toString();
        }
        return e.toString();
      }).toList();
    }

    return StageAssistResult(
      stageNumber: (json['stage_number'] as num?)?.toInt() ?? 0,
      guidance: json['guidance'] as String? ??
          json['ai_guidance'] as String? ??
          '',
      localSources: sources(json['local_sources']),
      webSources: sources(json['web_sources']),
      planReviewRecommended: json['plan_review_recommended'] == true,
      thresholds: json['thresholds'] is Map
          ? Map<String, dynamic>.from(json['thresholds'] as Map)
          : null,
    );
  }
}

class HomeProjectSection {
  const HomeProjectSection({
    required this.id,
    required this.stageNumber,
    required this.title,
    required this.description,
    required this.status,
    required this.sortOrder,
    required this.isCatalog,
    required this.hasDocuments,
    required this.documents,
    required this.comments,
    this.assignedToUserId,
    this.commentsCount = 0,
    this.slots = const [],
  });

  final int id;
  final int stageNumber;
  final String title;
  final String description;
  final String status;
  final int sortOrder;
  final bool isCatalog;
  final bool hasDocuments;
  final List<HomeProjectDocument> documents;
  final List<HomeProjectComment> comments;
  final int? assignedToUserId;
  final int commentsCount;
  final List<HomeProjectSlot> slots;

  factory HomeProjectSection.fromJson(Map<String, dynamic> json) {
    final docs = json['documents'];
    final comments = json['comments'];
    final slots = json['slots'];
    final parsedComments = comments is List
        ? comments
            .whereType<Map>()
            .map((e) =>
                HomeProjectComment.fromJson(Map<String, dynamic>.from(e)))
            .toList()
        : const <HomeProjectComment>[];
    final parsedSlots = slots is List
        ? slots
            .whereType<Map>()
            .map((e) =>
                HomeProjectSlot.fromJson(Map<String, dynamic>.from(e)))
            .toList()
        : const <HomeProjectSlot>[];
    return HomeProjectSection(
      id: (json['id'] as num?)?.toInt() ?? 0,
      stageNumber: (json['stage_number'] as num?)?.toInt() ?? 0,
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      status: json['status'] as String? ?? 'pending',
      sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
      isCatalog: json['is_catalog'] == true,
      hasDocuments: json['has_documents'] == true ||
          (docs is List && docs.isNotEmpty),
      documents: docs is List
          ? docs
              .whereType<Map>()
              .map((e) =>
                  HomeProjectDocument.fromJson(Map<String, dynamic>.from(e)))
              .toList()
          : const [],
      comments: parsedComments,
      assignedToUserId: (json['assigned_to_user_id'] as num?)?.toInt(),
      commentsCount: (json['comments_count'] as num?)?.toInt() ??
          parsedComments.length,
      slots: parsedSlots,
    );
  }
}

class HomeProjectStage {
  const HomeProjectStage({
    required this.stageNumber,
    required this.slug,
    required this.title,
    required this.summary,
    required this.status,
    required this.sections,
    required this.sectionsProgress,
    required this.planReview,
    required this.notes,
    required this.documents,
    required this.aiGuidance,
    this.analysisId,
    this.analysis,
  });

  final int stageNumber;
  final String slug;
  final String title;
  final String summary;
  final String status;
  final List<HomeProjectSection> sections;
  final SectionsProgress sectionsProgress;
  final bool planReview;
  final String notes;
  final List<HomeProjectDocument> documents;
  final String aiGuidance;
  final int? analysisId;
  final LinkedAnalysisSummary? analysis;

  factory HomeProjectStage.fromJson(Map<String, dynamic> json) {
    final sections = json['sections'];
    final docs = json['documents'];
    final analysis = json['analysis'];
    return HomeProjectStage(
      stageNumber: (json['stage_number'] as num?)?.toInt() ?? 0,
      slug: json['slug'] as String? ?? '',
      title: json['title'] as String? ?? '',
      summary: json['summary'] as String? ?? '',
      status: json['status'] as String? ?? 'pending',
      sections: sections is List
          ? sections
              .whereType<Map>()
              .map((e) =>
                  HomeProjectSection.fromJson(Map<String, dynamic>.from(e)))
              .toList()
          : const [],
      sectionsProgress: SectionsProgress.fromJson(
        json['sections_progress'] is Map
            ? Map<String, dynamic>.from(json['sections_progress'] as Map)
            : null,
      ),
      planReview: json['plan_review'] == true,
      notes: json['notes'] as String? ?? '',
      documents: docs is List
          ? docs
              .whereType<Map>()
              .map((e) =>
                  HomeProjectDocument.fromJson(Map<String, dynamic>.from(e)))
              .toList()
          : const [],
      aiGuidance: json['ai_guidance'] as String? ?? '',
      analysisId: (json['analysis_id'] as num?)?.toInt(),
      analysis: analysis is Map
          ? LinkedAnalysisSummary.fromJson(Map<String, dynamic>.from(analysis))
          : null,
    );
  }
}

class HomeProject {
  const HomeProject({
    required this.id,
    required this.name,
    required this.clientName,
    required this.location,
    required this.description,
    required this.status,
    required this.currentStage,
    required this.progressPercent,
    required this.stagesCompleted,
    required this.stages,
    required this.members,
    required this.myRole,
    required this.permissions,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String name;
  final String clientName;
  final String location;
  final String description;
  final String status;
  final int currentStage;
  final double progressPercent;
  final int stagesCompleted;
  final List<HomeProjectStage> stages;
  final List<HomeProjectMember> members;
  final String myRole;
  final HomeProjectPermissions permissions;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  HomeProjectStage? stageByNumber(int number) {
    for (final stage in stages) {
      if (stage.stageNumber == number) return stage;
    }
    return null;
  }

  HomeProjectSection? sectionById(int sectionId) {
    for (final stage in stages) {
      for (final section in stage.sections) {
        if (section.id == sectionId) return section;
      }
    }
    return null;
  }

  factory HomeProject.fromJson(Map<String, dynamic> json) {
    final stages = json['stages'];
    final members = json['members'];
    return HomeProject(
      id: json['id']?.toString() ?? '',
      name: json['name'] as String? ?? '',
      clientName: json['client_name'] as String? ?? '',
      location: json['location'] as String? ?? '',
      description: json['description'] as String? ?? '',
      status: json['status'] as String? ?? 'active',
      currentStage: (json['current_stage'] as num?)?.toInt() ?? 1,
      progressPercent: (json['progress_percent'] as num?)?.toDouble() ?? 0,
      stagesCompleted: (json['stages_completed'] as num?)?.toInt() ?? 0,
      stages: stages is List
          ? stages
              .whereType<Map>()
              .map((e) =>
                  HomeProjectStage.fromJson(Map<String, dynamic>.from(e)))
              .toList()
          : const [],
      members: members is List
          ? members
              .whereType<Map>()
              .map((e) =>
                  HomeProjectMember.fromJson(Map<String, dynamic>.from(e)))
              .toList()
          : const [],
      myRole: json['my_role'] as String? ?? 'viewer',
      permissions: HomeProjectPermissions.fromJson(
        json['permissions'] is Map
            ? Map<String, dynamic>.from(json['permissions'] as Map)
            : null,
      ),
      createdAt: parseHomeDate(json['created_at']),
      updatedAt: parseHomeDate(json['updated_at']),
    );
  }
}

/// Catálogo estático de 9 etapas (GET /api/home-projects/catalog).
class HomeProjectCatalogStage {
  const HomeProjectCatalogStage({
    required this.stageNumber,
    required this.slug,
    required this.title,
    required this.summary,
    required this.planReview,
    required this.sections,
  });

  final int stageNumber;
  final String slug;
  final String title;
  final String summary;
  final bool planReview;
  final List<HomeProjectCatalogSection> sections;

  factory HomeProjectCatalogStage.fromJson(Map<String, dynamic> json) {
    final sections = json['sections'];
    return HomeProjectCatalogStage(
      stageNumber: (json['stage_number'] as num?)?.toInt() ?? 0,
      slug: json['slug'] as String? ?? '',
      title: json['title'] as String? ?? '',
      summary: json['summary'] as String? ?? '',
      planReview: json['plan_review'] == true,
      sections: sections is List
          ? sections
              .whereType<Map>()
              .map((e) => HomeProjectCatalogSection.fromJson(
                    Map<String, dynamic>.from(e),
                  ))
              .toList()
          : const [],
    );
  }
}

class HomeProjectCatalogSection {
  const HomeProjectCatalogSection({
    required this.title,
    required this.description,
    required this.sortOrder,
    this.slots = const [],
  });

  final String title;
  final String description;
  final int sortOrder;
  final List<HomeProjectSlot> slots;

  factory HomeProjectCatalogSection.fromJson(Map<String, dynamic> json) {
    final slots = json['slots'];
    return HomeProjectCatalogSection(
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
      slots: slots is List
          ? slots
              .whereType<Map>()
              .map((e) =>
                  HomeProjectSlot.fromJson(Map<String, dynamic>.from(e)))
              .toList()
          : const [],
    );
  }
}

class HomeProjectCatalog {
  const HomeProjectCatalog({required this.stages});

  final List<HomeProjectCatalogStage> stages;

  factory HomeProjectCatalog.fromJson(Map<String, dynamic> json) {
    final stages = json['stages'];
    return HomeProjectCatalog(
      stages: stages is List
          ? stages
              .whereType<Map>()
              .map((e) => HomeProjectCatalogStage.fromJson(
                    Map<String, dynamic>.from(e),
                  ))
              .toList()
          : const [],
    );
  }
}

class HomeProjectEvent {
  const HomeProjectEvent({
    required this.id,
    required this.type,
    required this.message,
    this.actorName,
    this.actorEmail,
    this.stageNumber,
    this.sectionId,
    this.createdAt,
    this.meta,
  });

  final int id;
  final String type;
  final String message;
  final String? actorName;
  final String? actorEmail;
  final int? stageNumber;
  final int? sectionId;
  final DateTime? createdAt;
  final Map<String, dynamic>? meta;

  factory HomeProjectEvent.fromJson(Map<String, dynamic> json) {
    final actor = json['actor'] ?? json['user'] ?? json['author'];
    String? name = json['actor_name'] as String? ?? json['full_name'] as String?;
    String? email = json['actor_email'] as String? ?? json['email'] as String?;
    if (actor is Map) {
      final map = Map<String, dynamic>.from(actor);
      name ??= map['full_name'] as String? ?? map['name'] as String?;
      email ??= map['email'] as String?;
    }
    return HomeProjectEvent(
      id: (json['id'] as num?)?.toInt() ?? 0,
      type: json['type'] as String? ??
          json['event_type'] as String? ??
          json['action'] as String? ??
          '',
      message: json['message'] as String? ??
          json['summary'] as String? ??
          json['description'] as String? ??
          '',
      actorName: name,
      actorEmail: email,
      stageNumber: (json['stage_number'] as num?)?.toInt(),
      sectionId: (json['section_id'] as num?)?.toInt(),
      createdAt: parseHomeDate(json['created_at']),
      meta: json['meta'] is Map
          ? Map<String, dynamic>.from(json['meta'] as Map)
          : (json['payload'] is Map
              ? Map<String, dynamic>.from(json['payload'] as Map)
              : null),
    );
  }
}

class HomeProjectEventsPage {
  const HomeProjectEventsPage({
    required this.events,
    required this.total,
  });

  final List<HomeProjectEvent> events;
  final int total;
}

class HomeProjectSlot {
  const HomeProjectSlot({
    required this.key,
    required this.title,
    required this.accept,
    required this.required,
    required this.aiPlanReview,
    this.filled = false,
  });

  final String key;
  final String title;
  final List<String> accept;
  final bool required;
  final bool aiPlanReview;
  final bool filled;

  factory HomeProjectSlot.fromJson(Map<String, dynamic> json) {
    final rawAccept = json['accept'];
    List<String> acceptList = [];
    if (rawAccept is List) {
      acceptList = rawAccept.map((e) => e.toString()).toList();
    } else if (rawAccept is String && rawAccept.isNotEmpty) {
      acceptList = [rawAccept];
    }
    final title = json['title'] as String? ?? '';
    final rawKey = json['key']?.toString() ??
        json['slot_key']?.toString() ??
        json['id']?.toString();
    final key = (rawKey != null && rawKey.trim().isNotEmpty)
        ? rawKey.trim()
        : (title.isNotEmpty
            ? title.toLowerCase().trim().replaceAll(RegExp(r'\s+'), '_')
            : 'general');
    return HomeProjectSlot(
      key: key,
      title: title.isNotEmpty ? title : key,
      accept: acceptList,
      required: json['required'] == true,
      aiPlanReview: json['ai_plan_review'] == true,
      filled: json['filled'] == true,
    );
  }
}

class HomeProjectAiFinding {
  const HomeProjectAiFinding({
    required this.id,
    required this.title,
    required this.status,
    this.severity,
    this.reviewNote,
    this.reviewedAt,
  });

  final int id;
  final String title;
  final String status;
  final String? severity;
  final String? reviewNote;
  final DateTime? reviewedAt;

  factory HomeProjectAiFinding.fromJson(Map<String, dynamic> json) {
    return HomeProjectAiFinding(
      id: (json['id'] as num?)?.toInt() ??
          (json['finding_id'] as num?)?.toInt() ??
          0,
      title: json['title'] as String? ??
          json['label'] as String? ??
          json['message'] as String? ??
          '',
      status: json['status'] as String? ??
          json['review_status'] as String? ??
          'open',
      severity: json['severity'] as String?,
      reviewNote: json['note'] as String? ?? json['review_note'] as String?,
      reviewedAt: parseHomeDate(json['reviewed_at']),
    );
  }
}

class HomeProjectAiReview {
  const HomeProjectAiReview({
    required this.id,
    required this.documentId,
    required this.stageNumber,
    required this.status,
    required this.findings,
    this.sectionId,
    this.message,
    this.createdAt,
  });

  final int id;
  final int documentId;
  final int stageNumber;
  final String status;
  final List<HomeProjectAiFinding> findings;
  final int? sectionId;
  final String? message;
  final DateTime? createdAt;

  factory HomeProjectAiReview.fromJson(Map<String, dynamic> json) {
    final findings = json['findings'] ?? json['items'];
    return HomeProjectAiReview(
      id: (json['id'] as num?)?.toInt() ??
          (json['review_id'] as num?)?.toInt() ??
          0,
      documentId: (json['document_id'] as num?)?.toInt() ?? 0,
      stageNumber: (json['stage_number'] as num?)?.toInt() ?? 0,
      status: json['status'] as String? ?? 'pending',
      findings: findings is List
          ? findings
              .whereType<Map>()
              .map((e) => HomeProjectAiFinding.fromJson(
                    Map<String, dynamic>.from(e),
                  ))
              .toList()
          : const [],
      sectionId: (json['section_id'] as num?)?.toInt(),
      message: json['message'] as String?,
      createdAt: parseHomeDate(json['created_at']),
    );
  }
}

DateTime? parseHomeDate(dynamic value) {
  if (value is! String || value.isEmpty) return null;
  return DateTime.tryParse(value);
}

String homeProjectStatusLabel(String status) {
  switch (status) {
    case 'active':
      return 'Activo';
    case 'on_hold':
      return 'En pausa';
    case 'completed':
      return 'Completado';
    case 'canceled':
      return 'Cancelado';
    case 'pending':
      return 'Pendiente';
    case 'in_progress':
      return 'En progreso';
    case 'blocked':
      return 'Bloqueado';
    case 'needs_details':
      return 'Requiere detalles';
    case 'needs_correction':
      return 'Requiere corrección';
    default:
      return status;
  }
}

String homeProjectRoleLabel(String role) {
  switch (role) {
    case 'owner':
      return 'Propietario';
    case 'admin':
      return 'Admin';
    case 'editor':
      return 'Editor';
    case 'viewer':
      return 'Viewer';
    default:
      return role;
  }
}

const sectionStatusOptions = <String>[
  'pending',
  'in_progress',
  'needs_details',
  'needs_correction',
  'completed',
];
