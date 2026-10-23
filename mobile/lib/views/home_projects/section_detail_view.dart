import 'package:flutter/material.dart';
import 'package:movil_architect/controllers/home_project_controller.dart';
import 'package:movil_architect/core/app_services.dart';
import 'package:movil_architect/core/utils/app_notifications.dart';
import 'package:movil_architect/core/utils/date_utils.dart';
import 'package:movil_architect/models/home_project_models.dart';
import 'package:movil_architect/views/home_projects/widgets/home_project_widgets.dart';
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
  List<HomeProjectComment>? _extraComments;
  int? _commentsTotal;

  HomeProjectSection? get _section =>
      widget.controller.project?.sectionById(widget.sectionId);

  int? get _currentUserId =>
      AppServices.instance.authService.currentUser?.id;

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _changeStatus() async {
    if (!widget.controller.permissions.canEdit) return;
    final current = _section?.status ?? 'pending';
    final selected = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              title: Text(
                'Estado del apartado',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            for (final status in sectionStatusOptions)
              ListTile(
                title: Text(homeProjectStatusLabel(status)),
                trailing: status == current ? const Icon(Icons.check) : null,
                onTap: () => Navigator.pop(context, status),
              ),
          ],
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

  Future<void> _upload({String? preselectedSlotKey, String? preselectedSlotTitle}) async {
    if (!widget.controller.permissions.canUpload) return;
    final section = _section;
    if (section == null) return;

    final pick = await showAttachmentPickerSheet(context);
    if (pick == null || !mounted) return;

    final file = pick.file;
    final size = await file.length();
    if (size > 25 * 1024 * 1024) {
      if (!mounted) return;
      AppNotifications.error(
        context,
        'El archivo supera el límite de 25 MB',
      );
      return;
    }

    final slotKey = (preselectedSlotKey != null && preselectedSlotKey.trim().isNotEmpty)
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

    // 1. Si el apartado tiene entregables definidos, asociar al primer entregable pendiente
    if (section.slots.isNotEmpty) {
      final pendingSlot = section.slots.where((slot) {
        final isFilled = slot.filled ||
            section.documents.any((doc) => doc.slotKey == slot.key);
        return !isFilled;
      }).firstOrNull;

      if (pendingSlot != null) {
        return pendingSlot.key;
      }
      return section.slots.first.key;
    }

    // 2. Si no hay entregas preconfiguradas, clasificar por extensión
    if (lower.endsWith('.pdf')) {
      return 'documento';
    } else if (lower.endsWith('.doc') || lower.endsWith('.docx')) {
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
    final titleController = TextEditingController();
    var isRequired = false;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Nueva entrega requerida'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleController,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Título de la entrega',
                    hintText: 'Ej. Plano estructural',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('¿Es obligatorio?'),
                  value: isRequired,
                  onChanged: (val) => setDialogState(() => isRequired = val),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogCtx, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () {
                  if (titleController.text.trim().isNotEmpty) {
                    Navigator.pop(dialogCtx, true);
                  }
                },
                child: const Text('Crear'),
              ),
            ],
          );
        },
      ),
    );

    if (confirmed != true || !mounted) return;
    final ok = await widget.controller.createSlot(
      sectionId: widget.sectionId,
      title: titleController.text.trim(),
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar tipo de entrega'),
        content: Text('¿Eliminar la entrega "${slot.title}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
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
    final canDelete = widget.controller.permissions.canDeleteDocuments ||
        widget.controller.permissions.canEdit;
    if (!canDelete) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar documento'),
        content: Text('¿Eliminar "${doc.originalFilename}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar comentario'),
        content: const Text('¿Eliminar este comentario?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
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
    final scheme = Theme.of(context).colorScheme;

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
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          appBar: AppBar(
            title: Text(
              section?.title ?? 'Apartado',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            backgroundColor: Theme.of(context).scaffoldBackgroundColor,
            elevation: 0,
          ),
          floatingActionButton: permissions.canUpload
              ? FloatingActionButton.extended(
                  onPressed: widget.controller.busy ? null : _upload,
                  icon: const Icon(Icons.upload_file),
                  label: const Text('Subir archivo'),
                )
              : null,
          body: section == null
              ? AppErrorView(
                  message: 'No se encontró el apartado',
                  onRetry: () => widget.controller.load(refresh: true),
                )
              : RefreshIndicator(
                  onRefresh: () async {
                    setState(() {
                      _extraComments = null;
                      _commentsTotal = null;
                    });
                    await widget.controller.load(refresh: true);
                  },
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
                    children: [
                      if (widget.controller.busy)
                        const LinearProgressIndicator(minHeight: 2),
                      Row(
                        children: [
                          HomeStatusChip(status: section.status),
                          const Spacer(),
                          if (permissions.canEdit)
                            TextButton.icon(
                              onPressed:
                                  widget.controller.busy ? null : _changeStatus,
                              icon: const Icon(Icons.edit_outlined, size: 18),
                              label: const Text('Cambiar estado'),
                            ),
                        ],
                      ),
                      if (section.description.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        Text(
                          section.description,
                          style: TextStyle(
                            color: scheme.onSurfaceVariant,
                            height: 1.4,
                          ),
                        ),
                      ],
                      const SizedBox(height: 22),
                      Row(
                        children: [
                          Text(
                            'Entregas (${section.slots.length})',
                            style: TextStyle(
                              color: scheme.onSurface,
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const Spacer(),
                          if (permissions.canEdit)
                            TextButton.icon(
                              onPressed: widget.controller.busy ? null : _addCustomSlot,
                              icon: const Icon(Icons.add, size: 18),
                              label: const Text('Nueva entrega'),
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      if (section.slots.isEmpty)
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Theme.of(context).cardColor,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: scheme.outlineVariant.withAlpha(60),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.info_outline, color: scheme.primary, size: 20),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Sin entregas específicas configuradas. Puedes subir tus archivos con el botón de abajo.',
                                  style: TextStyle(
                                    color: scheme.onSurfaceVariant,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )
                      else
                        for (final slot in section.slots) ...[
                          _buildSlotCard(context, slot, section, permissions),
                          const SizedBox(height: 10),
                        ],
                      const SizedBox(height: 22),
                      Text(
                        'Documentos (${section.documents.length})',
                        style: TextStyle(
                          color: scheme.onSurface,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (section.documents.isEmpty)
                        Text(
                          'Aún no hay documentos en este apartado.',
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        )
                      else
                        for (final doc in section.documents) ...[
                          _buildDocumentTile(context, doc, section, canDeleteDocs),
                          const SizedBox(height: 8),
                        ],
                      const SizedBox(height: 28),
                      Text(
                        'Comentarios ($commentsCount)',
                        style: TextStyle(
                          color: scheme.onSurface,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (comments.isEmpty)
                        Text(
                          'Sin comentarios todavía.',
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        )
                      else
                        for (final comment in comments) ...[
                          Material(
                            color: Theme.of(context).cardColor,
                            borderRadius: BorderRadius.circular(16),
                            child: ListTile(
                              title: Text(
                                comment.authorName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(comment.body),
                                    const SizedBox(height: 4),
                                    Text(
                                      formatRelativeTime(comment.createdAt),
                                      style: TextStyle(
                                        color: scheme.onSurfaceVariant,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              trailing: _canDeleteComment(comment)
                                  ? IconButton(
                                      tooltip: 'Eliminar',
                                      onPressed: widget.controller.busy
                                          ? null
                                          : () => _deleteComment(comment),
                                      icon: const Icon(
                                        Icons.delete_outline,
                                        color: Colors.redAccent,
                                      ),
                                    )
                                  : null,
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],
                      if (commentsCount > comments.length) ...[
                        const SizedBox(height: 4),
                        TextButton(
                          onPressed: _loadAllComments,
                          child: Text(
                            'Ver todos ($commentsCount)',
                          ),
                        ),
                      ],
                      if (permissions.canComment) ...[
                        const SizedBox(height: 12),
                        TextField(
                          controller: _commentController,
                          maxLength: 4000,
                          minLines: 2,
                          maxLines: 4,
                          decoration: const InputDecoration(
                            labelText: 'Escribe un comentario',
                            hintText: 'Puedes mencionar con @correo',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: FilledButton.icon(
                            onPressed:
                                widget.controller.busy ? null : _sendComment,
                            icon: const Icon(Icons.send),
                            label: const Text('Enviar'),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
        );
      },
    );
  }

  Widget _buildSlotCard(
    BuildContext context,
    HomeProjectSlot slot,
    HomeProjectSection section,
    HomeProjectPermissions permissions,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final slotDocs =
        section.documents.where((d) => d.slotKey == slot.key).toList();
    final isFilled = slot.filled || slotDocs.isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isFilled
              ? (isDark ? const Color(0xFF1E3A2F) : const Color(0xFFD1FADF))
              : (isDark ? const Color(0xFF2E2E34) : const Color(0xFFE4E7EC)),
          width: 1.2,
        ),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: isFilled
                      ? const Color(0xFFECFDF3)
                      : (slot.required
                          ? const Color(0xFFFEF3F2)
                          : scheme.surfaceContainerHighest),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isFilled
                      ? Icons.check
                      : (slot.required
                          ? Icons.assignment_late_outlined
                          : Icons.assignment_outlined),
                  color: isFilled
                      ? const Color(0xFF12B76A)
                      : (slot.required
                          ? const Color(0xFFF04438)
                          : scheme.onSurfaceVariant),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      slot.title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        if (slot.required)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFEF3F2),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'Requerido',
                              style: TextStyle(
                                color: Color(0xFFB42318),
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: isFilled
                                ? const Color(0xFFECFDF3)
                                : const Color(0xFFF2F4F7),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            isFilled
                                ? 'Entregado (${slotDocs.length})'
                                : 'Pendiente',
                            style: TextStyle(
                              color: isFilled
                                  ? const Color(0xFF027A48)
                                  : const Color(0xFF475467),
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (slot.accept.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: scheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              slot.accept.join(', '),
                              style: TextStyle(
                                color: scheme.onSurfaceVariant,
                                fontSize: 11,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              if (permissions.canEdit)
                IconButton(
                  tooltip: 'Eliminar entrega',
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: widget.controller.busy
                      ? null
                      : () => _deleteSlot(slot),
                ),
            ],
          ),
          if (permissions.canUpload) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: widget.controller.busy
                    ? null
                    : () => _upload(
                          preselectedSlotKey: slot.key,
                          preselectedSlotTitle: slot.title,
                        ),
                icon: const Icon(Icons.upload_file, size: 18),
                label: Text(
                  isFilled
                      ? 'Subir otro archivo para esta entrega'
                      : 'Subir esta entrega',
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDocumentTile(
    BuildContext context,
    HomeProjectDocument doc,
    HomeProjectSection section,
    bool canDeleteDocs,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final matchingSlot =
        section.slots.where((s) => s.key == doc.slotKey).firstOrNull;
    final slotDisplay = matchingSlot?.title ?? doc.slotKey;

    final name = doc.originalFilename.toLowerCase();
    final IconData docIcon;
    if (doc.isImage) {
      docIcon = Icons.image_outlined;
    } else if (name.endsWith('.pdf')) {
      docIcon = Icons.picture_as_pdf_outlined;
    } else if (name.endsWith('.doc') || name.endsWith('.docx')) {
      docIcon = Icons.article_outlined;
    } else {
      docIcon = Icons.description_outlined;
    }

    return Material(
      color: Theme.of(context).cardColor,
      borderRadius: BorderRadius.circular(16),
      child: ListTile(
        leading: Icon(
          docIcon,
          color: scheme.primary,
        ),
        title: Text(
          doc.originalFilename,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Wrap(
            spacing: 6,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(_formatSize(doc.fileSize)),
              if (slotDisplay != null && slotDisplay.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.primary.withAlpha(25),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    slotDisplay,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: scheme.primary,
                    ),
                  ),
                ),
            ],
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Abrir',
              onPressed: () => _openDoc(doc),
              icon: const Icon(Icons.open_in_new),
            ),
            if (canDeleteDocs)
              IconButton(
                tooltip: 'Eliminar',
                onPressed: widget.controller.busy
                    ? null
                    : () => _deleteDoc(doc),
                icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
              ),
          ],
        ),
      ),
    );
  }
}
