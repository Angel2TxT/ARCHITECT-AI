import 'package:flutter/material.dart';
import 'package:movil_architect/controllers/home_project_controller.dart';
import 'package:movil_architect/core/app_services.dart';
import 'package:movil_architect/core/theme/architect_theme_tokens.dart';
import 'package:movil_architect/core/utils/app_notifications.dart';
import 'package:movil_architect/core/utils/date_utils.dart';
import 'package:movil_architect/models/home_project_models.dart';
import 'package:movil_architect/views/home_projects/slot_documents_view.dart';
import 'package:movil_architect/views/shared/app_states.dart';
import 'package:movil_architect/views/shared/attachment_picker_sheet.dart';

class SectionDetailView extends StatefulWidget {
  const SectionDetailView({
    super.key,
    required this.projectId,
    required this.stageNumber,
    required this.sectionId,
    required this.controller,
  });

  final String projectId;
  final int stageNumber;
  final int sectionId;
  final HomeProjectDetailController controller;

  @override
  State<SectionDetailView> createState() => _SectionDetailViewState();
}

class _SectionDetailViewState extends State<SectionDetailView> {
  final _commentController = TextEditingController();
  final _commentFocusNode = FocusNode();
  List<HomeProjectComment>? _extraComments;
  int? _commentsTotal;

  HomeProjectSection? get _section =>
      widget.controller.project?.sectionById(widget.sectionId);

  int? get _currentUserId => AppServices.instance.authService.currentUser?.id;

  @override
  void initState() {
    super.initState();
    _commentController.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _commentController.dispose();
    _commentFocusNode.dispose();
    super.dispose();
  }

  ButtonStyle _cancelButtonStyle(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return FilledButton.styleFrom(
      foregroundColor: Colors.white,
      backgroundColor: isDark
          ? const Color(0xFF3E3E44)
          : const Color(0xFF6B6B73),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      minimumSize: const Size(0, 42),
    );
  }

  ButtonStyle _dangerButtonStyle(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return FilledButton.styleFrom(
      foregroundColor: Colors.white,
      backgroundColor: isDark
          ? const Color(0xFFD9383A)
          : const Color(0xFFC8282A),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      minimumSize: const Size(0, 42),
    );
  }

  Future<bool?> _confirmDestructive({
    required String title,
    required String message,
    String confirmLabel = 'Eliminar',
  }) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            style: _cancelButtonStyle(dialogContext),
            child: Text(
              'Cancelar',
              style: ArchitectThemeTokens.appleText(
                color: Colors.white,
                fontSize: 14.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 4),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: _dangerButtonStyle(dialogContext),
            child: Text(
              confirmLabel,
              style: ArchitectThemeTokens.appleText(
                color: Colors.white,
                fontSize: 14.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _changeStatus() async {
    if (!widget.controller.permissions.canChangeSectionStatus) return;
    final tokens = ArchitectThemeTokens.of(context);
    final current = _section?.status ?? 'pending';

    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: tokens.surfaceSecondary,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetContext) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: tokens.borderStrong,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
                child: Row(
                  children: [
                    Text(
                      'Estado del apartado',
                      style: ArchitectThemeTokens.appleDisplay(
                        fontWeight: FontWeight.w500,
                        fontSize: 18,
                        color: tokens.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, thickness: 1, color: tokens.borderSubtle),
              for (final status in sectionStatusOptions)
                ListTile(
                  leading: _SemanticStatusDot(status: status),
                  title: Text(
                    homeProjectStatusLabel(status),
                    style: ArchitectThemeTokens.appleText(
                      fontWeight: status == current
                          ? FontWeight.w600
                          : FontWeight.w500,
                      fontSize: 15,
                      color: tokens.textPrimary,
                    ),
                  ),
                  trailing: status == current
                      ? Icon(
                          Icons.check_rounded,
                          color: tokens.accent,
                          size: 20,
                        )
                      : null,
                  onTap: () => Navigator.pop(sheetContext, status),
                ),
            ],
          ),
        ),
      ),
    );
    if (selected == null || selected == current || !mounted) return;

    final ok = await widget.controller.updateSectionStatus(
      sectionId: widget.sectionId,
      status: selected,
    );
    if (!mounted) return;
    AppNotifications.result(
      context,
      ok: ok,
      successMessage: 'Estado actualizado',
      errorMessage: widget.controller.actionError,
    );
  }

  Future<void> _upload({
    String? preselectedSlotKey,
    String? preselectedSlotTitle,
  }) async {
    if (!widget.controller.permissions.canUpload) return;
    final section = _section;
    if (section == null) return;

    final pick = await showAttachmentPickerSheet(
      context,
      allowedExtensions: projectDocumentAttachmentExtensions,
      invalidFileMessage:
          'Solo se permiten imágenes (PNG, JPG, WEBP), PDF, Word (.doc/.docx) o Excel (.xls/.xlsx).',
    );
    if (pick == null || !mounted) return;

    final file = pick.file;
    final size = await file.length();
    if (size > 25 * 1024 * 1024) {
      if (!mounted) return;
      AppNotifications.error(context, 'El archivo supera el límite de 25 MB');
      return;
    }

    final slotKey =
        (preselectedSlotKey != null && preselectedSlotKey.trim().isNotEmpty)
        ? preselectedSlotKey.trim()
        : _resolveAutoSlotKey(file.path, section);

    final ok = await widget.controller.uploadDocument(
      stageNumber: widget.stageNumber,
      sectionId: widget.sectionId,
      file: file,
      slotKey: slotKey,
    );
    if (!mounted) return;
    AppNotifications.result(
      context,
      ok: ok,
      successMessage: 'Documento subido',
      errorMessage: widget.controller.actionError,
    );
  }

  String _resolveAutoSlotKey(String filePath, HomeProjectSection section) {
    final lower = filePath.toLowerCase();

    if (section.slots.isNotEmpty) {
      final pendingSlot = section.slots.where((slot) {
        final isFilled =
            slot.filled ||
            section.documents.any((doc) => doc.slotKey == slot.key);
        return !isFilled;
      }).firstOrNull;

      if (pendingSlot != null) {
        return pendingSlot.key;
      }
      return section.slots.first.key;
    }

    if (lower.endsWith('.pdf') ||
        lower.endsWith('.doc') ||
        lower.endsWith('.docx') ||
        lower.endsWith('.xls') ||
        lower.endsWith('.xlsx')) {
      return 'documento';
    } else if (lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.webp')) {
      return 'imagen';
    } else if (lower.endsWith('.dwg') || lower.endsWith('.dxf')) {
      return 'plano';
    }
    return 'general';
  }

  Future<void> _addCustomSlot() async {
    if (!widget.controller.permissions.canEdit) return;
    final tokens = ArchitectThemeTokens.of(context);
    final titleController = TextEditingController();
    var isRequired = false;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text(
              'Nueva entrega requerida',
              style: ArchitectThemeTokens.appleDisplay(
                color: tokens.textPrimary,
                fontWeight: FontWeight.w500,
                fontSize: 18,
              ),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleController,
                  autofocus: true,
                  textCapitalization: TextCapitalization.sentences,
                  style: ArchitectThemeTokens.appleText(
                    color: tokens.textPrimary,
                    fontSize: 14,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Título de la entrega',
                    hintText: 'Ej. Plano estructural',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    '¿Es obligatorio?',
                    style: ArchitectThemeTokens.appleText(
                      color: tokens.textPrimary,
                      fontWeight: FontWeight.w500,
                      fontSize: 14,
                    ),
                  ),
                  value: isRequired,
                  onChanged: (val) => setDialogState(() => isRequired = val),
                ),
              ],
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(dialogCtx, false),
                style: _cancelButtonStyle(dialogCtx),
                child: Text(
                  'Cancelar',
                  style: ArchitectThemeTokens.appleText(
                    color: Colors.white,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              FilledButton(
                onPressed: () {
                  if (titleController.text.trim().isNotEmpty) {
                    Navigator.pop(dialogCtx, true);
                  }
                },
                style: FilledButton.styleFrom(
                  backgroundColor: tokens.primaryActionBg,
                  foregroundColor: tokens.primaryActionFg,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 10,
                  ),
                  minimumSize: const Size(0, 42),
                ),
                child: Text(
                  'Crear',
                  style: ArchitectThemeTokens.appleText(
                    color: tokens.primaryActionFg,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );

    final trimmedTitle = titleController.text.trim();
    titleController.dispose();

    if (confirmed != true || trimmedTitle.isEmpty || !mounted) return;
    final ok = await widget.controller.createSlot(
      sectionId: widget.sectionId,
      title: trimmedTitle,
      required: isRequired,
    );
    if (!mounted) return;
    AppNotifications.result(
      context,
      ok: ok,
      successMessage: 'Tipo de entrega creado',
      errorMessage: widget.controller.actionError,
    );
  }

  Future<void> _deleteSlot(HomeProjectSlot slot) async {
    if (!widget.controller.permissions.canEdit) return;
    final confirmed = await _confirmDestructive(
      title: 'Eliminar tipo de entrega',
      message: '¿Eliminar la entrega "${slot.title}"?',
    );
    if (confirmed != true || !mounted) return;
    final ok = await widget.controller.deleteSlot(
      sectionId: widget.sectionId,
      slotKey: slot.key,
    );
    if (!mounted) return;
    AppNotifications.result(
      context,
      ok: ok,
      successMessage: 'Entrega eliminada',
      errorMessage: widget.controller.actionError,
    );
  }

  Future<void> _openDoc(HomeProjectDocument doc) async {
    final error = await widget.controller.openDocument(doc);
    if (!mounted || error == null) return;
    AppNotifications.error(context, error);
  }

  Future<void> _deleteDoc(HomeProjectDocument doc) async {
    final canDelete =
        widget.controller.permissions.canDeleteDocuments ||
        widget.controller.permissions.canEdit;
    if (!canDelete) return;

    final confirmed = await _confirmDestructive(
      title: 'Eliminar documento',
      message: '¿Eliminar "${doc.originalFilename}"?',
    );
    if (confirmed != true || !mounted) return;

    final ok = await widget.controller.deleteDocument(doc.id);
    if (!mounted) return;
    AppNotifications.result(
      context,
      ok: ok,
      successMessage: 'Documento eliminado',
      errorMessage: widget.controller.actionError,
    );
  }

  Future<void> _sendComment() async {
    final text = _commentController.text.trim();
    if (text.isEmpty) return;
    final ok = await widget.controller.addComment(
      sectionId: widget.sectionId,
      body: text,
    );
    if (!mounted) return;
    if (ok) {
      _commentController.clear();
      _commentFocusNode.unfocus();
      setState(() {
        _extraComments = null;
        _commentsTotal = null;
      });
    }
    AppNotifications.result(
      context,
      ok: ok,
      successMessage: 'Comentario publicado',
      errorMessage: widget.controller.actionError,
    );
  }

  Future<void> _loadAllComments() async {
    final page = await widget.controller.loadAllComments(
      sectionId: widget.sectionId,
    );
    if (!mounted || page == null) return;
    setState(() {
      _extraComments = page.comments;
      _commentsTotal = page.total;
    });
  }

  Future<void> _deleteComment(HomeProjectComment comment) async {
    final confirmed = await _confirmDestructive(
      title: 'Eliminar comentario',
      message: '¿Eliminar este comentario?',
    );
    if (confirmed != true || !mounted) return;
    final ok = await widget.controller.deleteComment(
      sectionId: widget.sectionId,
      commentId: comment.id,
    );
    if (!mounted) return;
    if (ok) {
      setState(() {
        _extraComments = null;
        _commentsTotal = null;
      });
    }
    AppNotifications.result(
      context,
      ok: ok,
      successMessage: 'Comentario eliminado',
      errorMessage: widget.controller.actionError,
    );
  }

  bool _canDeleteComment(HomeProjectComment comment) {
    final permissions = widget.controller.permissions;
    if (permissions.canEdit) return true;
    if (!permissions.canComment) return false;
    final uid = _currentUserId;
    return uid != null && comment.userId == uid;
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final tokens = ArchitectThemeTokens.of(context);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        if (widget.controller.isDisposed) {
          return const Scaffold(body: SizedBox.shrink());
        }
        final section = _section;
        final permissions = widget.controller.permissions;
        final canDeleteDocs =
            permissions.canDeleteDocuments || permissions.canEdit;
        final comments = _extraComments ?? section?.comments ?? const [];
        final commentsCount = _commentsTotal ?? section?.commentsCount ?? 0;

        return Scaffold(
          backgroundColor: tokens.drawerBackground,
          resizeToAvoidBottomInset: true,
          appBar: AppBar(
            backgroundColor: tokens.drawerBackground,
            foregroundColor: tokens.textPrimary,
            elevation: 0,
            scrolledUnderElevation: 0,
            centerTitle: true,
            leading: Semantics(
              button: true,
              label: 'Regresar',
              child: IconButton(
                icon: Icon(
                  Icons.arrow_back_rounded,
                  size: 22,
                  color: tokens.textPrimary,
                ),
                tooltip: 'Regresar',
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ),
            title: Semantics(
              header: true,
              child: Text(
                section?.title ?? 'Apartado',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: ArchitectThemeTokens.appleDisplay(
                  fontWeight: FontWeight.w500,
                  fontSize: 19,
                  letterSpacing: -0.3,
                  color: tokens.textPrimary,
                ),
              ),
            ),
          ),
          body: section == null
              ? AppErrorView(
                  message: 'No se encontró el apartado',
                  onRetry: () => widget.controller.load(refresh: true),
                )
              : Column(
                  children: [
                    if (widget.controller.busy)
                      LinearProgressIndicator(
                        minHeight: 2,
                        color: tokens.accent,
                        backgroundColor: tokens.borderSubtle,
                      ),
                    Expanded(
                      child: RefreshIndicator(
                        color: tokens.accent,
                        onRefresh: () async {
                          setState(() {
                            _extraComments = null;
                            _commentsTotal = null;
                          });
                          await widget.controller.load(refresh: true);
                        },
                        child: ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          keyboardDismissBehavior:
                              ScrollViewKeyboardDismissBehavior.onDrag,
                          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                          children: [
                            // 1. TARJETA PRINCIPAL DEL APARTADO
                            _SectionOverviewCard(
                              section: section,
                              canChangeStatus:
                                  permissions.canChangeSectionStatus,
                              canEdit: permissions.canEdit,
                              busy: widget.controller.busy,
                              onChangeStatus: _changeStatus,
                            ),

                            // 2. SECCIÓN DE ENTREGAS
                            const SizedBox(height: 28),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Expanded(
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.baseline,
                                    textBaseline: TextBaseline.alphabetic,
                                    children: [
                                      Text(
                                        'Entregas',
                                        style:
                                            ArchitectThemeTokens.appleDisplay(
                                              color: tokens.textPrimary,
                                              fontSize: 18,
                                              fontWeight: FontWeight.w500,
                                              letterSpacing: -0.25,
                                            ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        '${section.slots.length}',
                                        style: ArchitectThemeTokens.appleText(
                                          color: tokens.textSecondary,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                          fontFeatures: const [
                                            FontFeature.tabularFigures(),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (permissions.canEdit) ...[
                                  const SizedBox(width: 12),
                                  _NewSlotButton(
                                    enabled: !widget.controller.busy,
                                    reduceMotion: reduceMotion,
                                    onTap: _addCustomSlot,
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 12),
                            if (section.slots.isEmpty)
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: tokens.surfaceSecondary,
                                  borderRadius: BorderRadius.circular(
                                    ArchitectThemeTokens.radiusLg,
                                  ),
                                  border: Border.all(
                                    color: tokens.borderSubtle,
                                    width: 1,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.info_outline_rounded,
                                      size: 18,
                                      color: tokens.textSecondary,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        'Sin entregas específicas configuradas.',
                                        style: ArchitectThemeTokens.appleText(
                                          color: tokens.textSecondary,
                                          fontSize: 14,
                                          height: 1.4,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            else
                              for (final slot in section.slots) ...[
                                _SlotCard(
                                  slot: slot,
                                  section: section,
                                  canEdit: permissions.canEdit,
                                  canUpload: permissions.canUpload,
                                  busy: widget.controller.busy,
                                  onDelete: () => _deleteSlot(slot),
                                  onOpenFiles: () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => SlotDocumentsView(
                                          controller: widget.controller,
                                          stageNumber: widget.stageNumber,
                                          sectionId: widget.sectionId,
                                          slot: slot,
                                        ),
                                      ),
                                    );
                                  },
                                  onUpload: () => _upload(
                                    preselectedSlotKey: slot.key,
                                    preselectedSlotTitle: slot.title,
                                  ),
                                ),
                                const SizedBox(height: 10),
                              ],

                            // 3. OTROS DOCUMENTOS
                            _LooseDocumentsSection(
                              section: section,
                              canDeleteDocs: canDeleteDocs,
                              busy: widget.controller.busy,
                              formatSize: _formatSize,
                              onOpenDoc: _openDoc,
                              onDeleteDoc: _deleteDoc,
                            ),

                            // 4. SECCIÓN DE COMENTARIOS
                            const SizedBox(height: 28),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.baseline,
                              textBaseline: TextBaseline.alphabetic,
                              children: [
                                Text(
                                  'Comentarios',
                                  style: ArchitectThemeTokens.appleDisplay(
                                    color: tokens.textPrimary,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w500,
                                    letterSpacing: -0.25,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '$commentsCount',
                                  style: ArchitectThemeTokens.appleText(
                                    color: tokens.textSecondary,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            if (comments.isEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                  horizontal: 16,
                                ),
                                decoration: BoxDecoration(
                                  color: tokens.surfaceSecondary,
                                  borderRadius: BorderRadius.circular(
                                    ArchitectThemeTokens.radiusLg,
                                  ),
                                  border: Border.all(
                                    color: tokens.borderSubtle,
                                    width: 1,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.chat_bubble_outline_rounded,
                                      size: 18,
                                      color: tokens.textSecondary,
                                    ),
                                    const SizedBox(width: 12),
                                    Text(
                                      'Sin comentarios todavía.',
                                      style: ArchitectThemeTokens.appleText(
                                        color: tokens.textSecondary,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            else
                              for (final comment in comments) ...[
                                _CommentCard(
                                  comment: comment,
                                  canDelete: _canDeleteComment(comment),
                                  busy: widget.controller.busy,
                                  onDelete: () => _deleteComment(comment),
                                ),
                                const SizedBox(height: 10),
                              ],
                            if (commentsCount > comments.length) ...[
                              const SizedBox(height: 4),
                              Center(
                                child: TextButton(
                                  onPressed: _loadAllComments,
                                  child: Text(
                                    'Ver todos los comentarios ($commentsCount)',
                                    style: ArchitectThemeTokens.appleText(
                                      color: tokens.accent,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    if (permissions.canComment)
                      _CommentComposerBar(
                        controller: _commentController,
                        focusNode: _commentFocusNode,
                        busy: widget.controller.busy,
                        onSend: _sendComment,
                      ),
                  ],
                ),
        );
      },
    );
  }
}

class _SectionOverviewCard extends StatelessWidget {
  const _SectionOverviewCard({
    required this.section,
    required this.canChangeStatus,
    required this.canEdit,
    required this.busy,
    required this.onChangeStatus,
  });

  final HomeProjectSection section;
  final bool canChangeStatus;
  final bool canEdit;
  final bool busy;
  final VoidCallback onChangeStatus;

  @override
  Widget build(BuildContext context) {
    final tokens = ArchitectThemeTokens.of(context);
    final totalSlots = section.slots.length;
    final completedSlots = section.slots
        .where(
          (s) => s.filled || section.documents.any((d) => d.slotKey == s.key),
        )
        .length;
    final progress = totalSlots == 0
        ? 0.0
        : (completedSlots / totalSlots).clamp(0.0, 1.0);
    final percent = (progress * 100).round();
    final isComplete = totalSlots > 0 && completedSlots >= totalSlots;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tokens.surfaceSecondary,
        borderRadius: BorderRadius.circular(ArchitectThemeTokens.radiusLg),
        border: Border.all(color: tokens.borderSubtle, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _SemanticStatusIndicator(status: section.status),
              const Spacer(),
              if (canChangeStatus)
                Semantics(
                  button: true,
                  label: 'Cambiar estado del apartado',
                  child: InkWell(
                    onTap: busy ? null : onChangeStatus,
                    borderRadius: BorderRadius.circular(
                      ArchitectThemeTokens.radiusSm,
                    ),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 36),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 4,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.edit_outlined,
                              size: 14,
                              color: tokens.accent,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Cambiar estado',
                              style: ArchitectThemeTokens.appleText(
                                color: tokens.accent,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                )
              else if (canEdit)
                Text(
                  'Espera confirmación',
                  style: ArchitectThemeTokens.appleText(
                    color: tokens.textSecondary,
                    fontSize: 12,
                  ),
                ),
            ],
          ),
          if (section.description.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              section.description,
              style: ArchitectThemeTokens.appleText(
                color: tokens.textSecondary,
                fontSize: 14,
                fontWeight: FontWeight.w400,
                height: 1.45,
              ),
            ),
          ],
          const SizedBox(height: 16),
          Text(
            'Progreso de entregas',
            style: ArchitectThemeTokens.appleText(
              color: tokens.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Text(
                '$completedSlots/$totalSlots',
                style: ArchitectThemeTokens.appleDisplay(
                  color: tokens.textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.w500,
                  letterSpacing: -0.3,
                ).copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Semantics(
                  label:
                      'Progreso de entregas: $completedSlots de $totalSlots completadas',
                  value: '$percent%',
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 4.5,
                      backgroundColor: tokens.borderSubtle,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        isComplete ? tokens.statusPositive : tokens.accent,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _NewSlotButton extends StatefulWidget {
  const _NewSlotButton({
    required this.enabled,
    required this.reduceMotion,
    required this.onTap,
  });

  final bool enabled;
  final bool reduceMotion;
  final VoidCallback onTap;

  @override
  State<_NewSlotButton> createState() => _NewSlotButtonState();
}

class _NewSlotButtonState extends State<_NewSlotButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final tokens = ArchitectThemeTokens.of(context);

    return Semantics(
      button: true,
      enabled: widget.enabled,
      label: 'Crear nueva entrega',
      child: AnimatedScale(
        scale: (_pressed && widget.enabled && !widget.reduceMotion)
            ? 0.97
            : 1.0,
        duration: widget.reduceMotion
            ? Duration.zero
            : const Duration(milliseconds: 110),
        curve: Curves.easeOutCubic,
        child: Material(
          color: widget.enabled
              ? tokens.primaryActionBg
              : tokens.primaryActionBg.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(ArchitectThemeTokens.radiusMd),
          child: InkWell(
            onTap: widget.enabled ? widget.onTap : null,
            onHighlightChanged: (value) {
              if (mounted) setState(() => _pressed = value);
            },
            borderRadius: BorderRadius.circular(ArchitectThemeTokens.radiusMd),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 40),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 9,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.add_rounded,
                      size: 17,
                      color: tokens.primaryActionFg,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Nueva entrega',
                      style: ArchitectThemeTokens.appleText(
                        color: tokens.primaryActionFg,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SlotCard extends StatelessWidget {
  const _SlotCard({
    required this.slot,
    required this.section,
    required this.canEdit,
    required this.canUpload,
    required this.busy,
    required this.onDelete,
    required this.onOpenFiles,
    required this.onUpload,
  });

  final HomeProjectSlot slot;
  final HomeProjectSection section;
  final bool canEdit;
  final bool canUpload;
  final bool busy;
  final VoidCallback onDelete;
  final VoidCallback onOpenFiles;
  final VoidCallback onUpload;

  @override
  Widget build(BuildContext context) {
    final tokens = ArchitectThemeTokens.of(context);
    final textScale = MediaQuery.textScalerOf(context).scale(1.0);
    final slotDocs = section.documents
        .where((d) => d.slotKey == slot.key)
        .toList();
    final isFilled = slot.filled || slotDocs.isNotEmpty;

    final Color leadingColor = isFilled
        ? tokens.statusPositive
        : (slot.required ? tokens.accent : tokens.textSecondary);
    final IconData leadingIcon = isFilled
        ? Icons.check_circle_outline_rounded
        : (slot.required
              ? Icons.assignment_late_outlined
              : Icons.assignment_outlined);

    return Container(
      decoration: BoxDecoration(
        color: tokens.surfaceSecondary,
        borderRadius: BorderRadius.circular(ArchitectThemeTokens.radiusLg),
        border: Border.all(color: tokens.borderSubtle, width: 1),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(leadingIcon, color: leadingColor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      slot.title,
                      maxLines: textScale > 1.3 ? 4 : 3,
                      overflow: TextOverflow.ellipsis,
                      style: ArchitectThemeTokens.appleText(
                        fontWeight: FontWeight.w500,
                        fontSize: 16,
                        color: tokens.textPrimary,
                        height: 1.25,
                      ),
                    ),
                    if (slot.required) ...[
                      const SizedBox(height: 5),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 5.5,
                            height: 5.5,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: tokens.accent,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Requerido',
                            style: ArchitectThemeTokens.appleText(
                              color: tokens.accent,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              if (canEdit)
                Semantics(
                  button: true,
                  label: 'Eliminar entrega ${slot.title}',
                  child: IconButton(
                    tooltip: 'Eliminar entrega',
                    constraints: const BoxConstraints(
                      minWidth: 44,
                      minHeight: 44,
                    ),
                    icon: Icon(
                      Icons.close_rounded,
                      size: 18,
                      color: tokens.textSecondary,
                    ),
                    onPressed: busy ? null : onDelete,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Semantics(
                    button: true,
                    label:
                        'Ver archivos de ${slot.title}, ${slotDocs.length} archivos',
                    child: InkWell(
                      onTap: onOpenFiles,
                      borderRadius: BorderRadius.circular(
                        ArchitectThemeTokens.radiusSm,
                      ),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 42),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 8,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.folder_open_rounded,
                                size: 17,
                                color: tokens.textSecondary,
                              ),
                              const SizedBox(width: 7),
                              Flexible(
                                child: Text(
                                  'Ver archivos (${slotDocs.length})',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: ArchitectThemeTokens.appleText(
                                    color: tokens.textPrimary,
                                    fontWeight: FontWeight.w500,
                                    fontSize: 14,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (canUpload) ...[
                const SizedBox(width: 8),
                Semantics(
                  button: true,
                  enabled: !busy,
                  label: 'Subir archivo para ${slot.title}',
                  child: Material(
                    color: busy
                        ? tokens.surfaceSelected.withValues(alpha: 0.5)
                        : tokens.surfaceSelected,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                        ArchitectThemeTokens.radiusMd,
                      ),
                      side: BorderSide(color: tokens.borderSubtle, width: 1),
                    ),
                    child: InkWell(
                      onTap: busy ? null : onUpload,
                      borderRadius: BorderRadius.circular(
                        ArchitectThemeTokens.radiusMd,
                      ),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 42),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.upload_file_rounded,
                                size: 17,
                                color: busy
                                    ? tokens.textSecondary
                                    : tokens.accent,
                              ),
                              const SizedBox(width: 7),
                              Text(
                                'Subir archivo',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: ArchitectThemeTokens.appleText(
                                  color: busy
                                      ? tokens.textSecondary
                                      : tokens.textPrimary,
                                  fontWeight: FontWeight.w500,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _LooseDocumentsSection extends StatelessWidget {
  const _LooseDocumentsSection({
    required this.section,
    required this.canDeleteDocs,
    required this.busy,
    required this.formatSize,
    required this.onOpenDoc,
    required this.onDeleteDoc,
  });

  final HomeProjectSection section;
  final bool canDeleteDocs;
  final bool busy;
  final String Function(int) formatSize;
  final ValueChanged<HomeProjectDocument> onOpenDoc;
  final ValueChanged<HomeProjectDocument> onDeleteDoc;

  @override
  Widget build(BuildContext context) {
    final tokens = ArchitectThemeTokens.of(context);
    final slotKeys = section.slots.map((s) => s.key).toSet();
    final visibleDocs = section.slots.isEmpty
        ? section.documents
        : section.documents
              .where((d) => d.slotKey == null || !slotKeys.contains(d.slotKey))
              .toList();

    if (section.slots.isNotEmpty && visibleDocs.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 28),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              section.slots.isEmpty ? 'Documentos' : 'Otros documentos',
              style: ArchitectThemeTokens.appleDisplay(
                color: tokens.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w500,
                letterSpacing: -0.25,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${visibleDocs.length}',
              style: ArchitectThemeTokens.appleText(
                color: tokens.textSecondary,
                fontSize: 14,
                fontWeight: FontWeight.w500,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (visibleDocs.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
            decoration: BoxDecoration(
              color: tokens.surfaceSecondary,
              borderRadius: BorderRadius.circular(
                ArchitectThemeTokens.radiusLg,
              ),
              border: Border.all(color: tokens.borderSubtle, width: 1),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.folder_open_rounded,
                  size: 18,
                  color: tokens.textSecondary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Aún no hay documentos en este apartado.',
                    style: ArchitectThemeTokens.appleText(
                      color: tokens.textSecondary,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
          )
        else
          for (final doc in visibleDocs) ...[
            _DocumentRowCard(
              doc: doc,
              section: section,
              canDeleteDocs: canDeleteDocs,
              busy: busy,
              formatSize: formatSize,
              onOpen: () => onOpenDoc(doc),
              onDelete: () => onDeleteDoc(doc),
            ),
            const SizedBox(height: 10),
          ],
      ],
    );
  }
}

class _DocumentRowCard extends StatelessWidget {
  const _DocumentRowCard({
    required this.doc,
    required this.section,
    required this.canDeleteDocs,
    required this.busy,
    required this.formatSize,
    required this.onOpen,
    required this.onDelete,
  });

  final HomeProjectDocument doc;
  final HomeProjectSection section;
  final bool canDeleteDocs;
  final bool busy;
  final String Function(int) formatSize;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final tokens = ArchitectThemeTokens.of(context);
    final matchingSlot = section.slots
        .where((s) => s.key == doc.slotKey)
        .firstOrNull;
    final slotDisplay = matchingSlot?.title ?? doc.slotKey;

    final name = doc.originalFilename.toLowerCase();
    final IconData docIcon;
    if (doc.isImage) {
      docIcon = Icons.image_outlined;
    } else if (name.endsWith('.pdf')) {
      docIcon = Icons.picture_as_pdf_outlined;
    } else if (name.endsWith('.doc') || name.endsWith('.docx')) {
      docIcon = Icons.article_outlined;
    } else if (name.endsWith('.xls') || name.endsWith('.xlsx')) {
      docIcon = Icons.table_chart_outlined;
    } else {
      docIcon = Icons.description_outlined;
    }

    return Container(
      decoration: BoxDecoration(
        color: tokens.surfaceSecondary,
        borderRadius: BorderRadius.circular(ArchitectThemeTokens.radiusLg),
        border: Border.all(color: tokens.borderSubtle, width: 1),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      child: Row(
        children: [
          Icon(docIcon, color: tokens.accent, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  doc.originalFilename,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: ArchitectThemeTokens.appleText(
                    fontWeight: FontWeight.w500,
                    fontSize: 14.5,
                    color: tokens.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  slotDisplay != null && slotDisplay.isNotEmpty
                      ? '${formatSize(doc.fileSize)} · $slotDisplay'
                      : formatSize(doc.fileSize),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: ArchitectThemeTokens.appleText(
                    color: tokens.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Abrir',
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            icon: Icon(
              Icons.open_in_new_rounded,
              size: 18,
              color: tokens.textPrimary,
            ),
            onPressed: onOpen,
          ),
          if (canDeleteDocs)
            IconButton(
              tooltip: 'Eliminar',
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
              icon: Icon(
                Icons.delete_outline_rounded,
                size: 18,
                color: tokens.statusError,
              ),
              onPressed: busy ? null : onDelete,
            ),
        ],
      ),
    );
  }
}

class _CommentCard extends StatelessWidget {
  const _CommentCard({
    required this.comment,
    required this.canDelete,
    required this.busy,
    required this.onDelete,
  });

  final HomeProjectComment comment;
  final bool canDelete;
  final bool busy;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final tokens = ArchitectThemeTokens.of(context);
    final initial = comment.authorName.trim().isNotEmpty
        ? comment.authorName.trim()[0].toUpperCase()
        : 'U';

    return Container(
      decoration: BoxDecoration(
        color: tokens.surfaceSecondary,
        borderRadius: BorderRadius.circular(ArchitectThemeTokens.radiusLg),
        border: Border.all(color: tokens.borderSubtle, width: 1),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: tokens.surfaceSelected,
                  shape: BoxShape.circle,
                  border: Border.all(color: tokens.borderStrong, width: 1),
                ),
                alignment: Alignment.center,
                child: Text(
                  initial,
                  style: ArchitectThemeTokens.appleDisplay(
                    fontWeight: FontWeight.w500,
                    fontSize: 12,
                    letterSpacing: 0,
                    color: tokens.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  comment.authorName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: ArchitectThemeTokens.appleText(
                    fontWeight: FontWeight.w500,
                    fontSize: 14,
                    color: tokens.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                formatRelativeTime(comment.createdAt),
                style: ArchitectThemeTokens.appleText(
                  color: tokens.textSecondary,
                  fontSize: 12,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              if (canDelete) ...[
                const SizedBox(width: 2),
                IconButton(
                  tooltip: 'Eliminar comentario',
                  constraints: const BoxConstraints(
                    minWidth: 40,
                    minHeight: 40,
                  ),
                  icon: Icon(
                    Icons.delete_outline_rounded,
                    size: 17,
                    color: tokens.statusError,
                  ),
                  onPressed: busy ? null : onDelete,
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Text(
            comment.body,
            style: ArchitectThemeTokens.appleText(
              color: tokens.textSecondary,
              fontSize: 14.5,
              fontWeight: FontWeight.w400,
              height: 1.42,
            ),
          ),
        ],
      ),
    );
  }
}

class _CommentComposerBar extends StatefulWidget {
  const _CommentComposerBar({
    required this.controller,
    required this.focusNode,
    required this.busy,
    required this.onSend,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool busy;
  final VoidCallback onSend;

  @override
  State<_CommentComposerBar> createState() => _CommentComposerBarState();
}

class _CommentComposerBarState extends State<_CommentComposerBar> {
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_handleFocus);
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_handleFocus);
    super.dispose();
  }

  void _handleFocus() {
    if (mounted) setState(() => _focused = widget.focusNode.hasFocus);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = ArchitectThemeTokens.of(context);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final hasText = widget.controller.text.trim().isNotEmpty;
    final canSend = hasText && !widget.busy;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.drawerBackground,
        border: Border(top: BorderSide(color: tokens.borderSubtle, width: 1)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: AnimatedContainer(
            duration: reduceMotion
                ? Duration.zero
                : const Duration(milliseconds: 160),
            decoration: BoxDecoration(
              color: tokens.surfaceSecondary,
              borderRadius: BorderRadius.circular(
                ArchitectThemeTokens.radiusLg,
              ),
              border: Border.all(
                color: _focused ? tokens.accent : tokens.borderSubtle,
                width: 1,
              ),
            ),
            padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: widget.controller,
                    focusNode: widget.focusNode,
                    enabled: !widget.busy,
                    minLines: 1,
                    maxLines: 5,
                    maxLength: 4000,
                    textCapitalization: TextCapitalization.sentences,
                    style: ArchitectThemeTokens.appleText(
                      color: tokens.textPrimary,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w400,
                      height: 1.35,
                    ),
                    decoration: InputDecoration(
                      isDense: true,
                      counterText: '',
                      hintText: 'Escribe un comentario...',
                      hintStyle: ArchitectThemeTokens.appleText(
                        color: tokens.textSecondary,
                        fontSize: 14.5,
                      ),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        vertical: 8,
                        horizontal: 2,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Semantics(
                  button: true,
                  enabled: canSend,
                  label: 'Enviar comentario',
                  child: Material(
                    color: canSend
                        ? tokens.primaryActionBg
                        : tokens.surfaceSelected,
                    borderRadius: BorderRadius.circular(10),
                    child: InkWell(
                      onTap: canSend ? widget.onSend : null,
                      borderRadius: BorderRadius.circular(10),
                      child: SizedBox(
                        width: 40,
                        height: 40,
                        child: Center(
                          child: widget.busy
                              ? SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: tokens.textSecondary,
                                  ),
                                )
                              : Icon(
                                  Icons.arrow_upward_rounded,
                                  size: 19,
                                  color: canSend
                                      ? tokens.primaryActionFg
                                      : tokens.textSecondary,
                                ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SemanticStatusDot extends StatelessWidget {
  const _SemanticStatusDot({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final tokens = ArchitectThemeTokens.of(context);
    final isCompleted = status == 'completed';
    final isInProgress = status == 'in_progress' || status == 'active';
    final isReview =
        status == 'needs_review' || status == 'in_review' || status == 'review';
    final isRejected = status == 'rejected' || status == 'error';

    final Color color = isCompleted
        ? tokens.statusPositive
        : (isInProgress
              ? tokens.accent
              : (isReview
                    ? tokens.statusWarning
                    : (isRejected
                          ? tokens.statusError
                          : tokens.textSecondary)));

    if (isCompleted) {
      return Icon(Icons.check_circle_outline_rounded, size: 16, color: color);
    }
    if (isRejected) {
      return Icon(Icons.error_outline_rounded, size: 16, color: color);
    }
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
  }
}

class _SemanticStatusIndicator extends StatelessWidget {
  const _SemanticStatusIndicator({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final tokens = ArchitectThemeTokens.of(context);
    final label = homeProjectStatusLabel(status);
    final isCompleted = status == 'completed';
    final isInProgress = status == 'in_progress' || status == 'active';
    final isReview =
        status == 'needs_review' || status == 'in_review' || status == 'review';
    final isRejected = status == 'rejected' || status == 'error';

    final Color color = isCompleted
        ? tokens.statusPositive
        : (isInProgress
              ? tokens.accent
              : (isReview
                    ? tokens.statusWarning
                    : (isRejected
                          ? tokens.statusError
                          : tokens.textSecondary)));

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _SemanticStatusDot(status: status),
        const SizedBox(width: 7),
        Text(
          label,
          style: ArchitectThemeTokens.appleText(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
