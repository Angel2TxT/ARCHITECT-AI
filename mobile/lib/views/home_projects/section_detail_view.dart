import 'package:flutter/material.dart';
import 'package:movil_architect/controllers/home_project_controller.dart';
import 'package:movil_architect/core/app_services.dart';
import 'package:movil_architect/core/utils/app_notifications.dart';
import 'package:movil_architect/core/utils/date_utils.dart';
import 'package:movil_architect/models/home_project_models.dart';
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sheetBg = isDark ? const Color(0xFF141417) : Colors.white;
    final primaryBlack = isDark ? Colors.white : const Color(0xFF111111);
    final borderColor = isDark ? const Color(0xFF3F3F46) : const Color(0xFFD1D5DB);
    final current = _section?.status ?? 'pending';

    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: sheetBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Row(
                  children: [
                    Text(
                      'Estado del apartado',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 17,
                        color: primaryBlack,
                      ),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: borderColor),
              for (final status in sectionStatusOptions)
                ListTile(
                  title: Text(
                    homeProjectStatusLabel(status),
                    style: TextStyle(
                      fontWeight: status == current ? FontWeight.w800 : FontWeight.w600,
                      color: primaryBlack,
                    ),
                  ),
                  trailing: status == current
                      ? Icon(Icons.check_circle_rounded, color: primaryBlack, size: 20)
                      : null,
                  onTap: () => Navigator.pop(context, status),
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

  Widget _buildStatusPill(
    String status,
    bool isDark,
    Color borderColor,
    Color primaryBlack,
    Color tagBg,
  ) {
    final label = homeProjectStatusLabel(status);
    final isDone = status == 'completed';

    if (isDone) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isDark ? Colors.white : const Color(0xFF111111),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.check_circle_rounded,
              size: 13,
              color: isDark ? const Color(0xFF111111) : Colors.white,
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                color: isDark ? const Color(0xFF111111) : Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 11,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: tagBg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: borderColor, width: 1.0),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: isDark ? const Color(0xFFA1A1AA) : const Color(0xFF52525B),
          fontWeight: FontWeight.w700,
          fontSize: 11,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF0C0C0E) : const Color(0xFFF7F7F8);
    final cardBg = isDark ? const Color(0xFF141417) : Colors.white;
    final borderColor = isDark ? const Color(0xFF3F3F46) : const Color(0xFFD1D5DB);
    final primaryBlack = isDark ? Colors.white : const Color(0xFF111111);
    final secondaryText = isDark ? const Color(0xFFA1A1AA) : const Color(0xFF52525B);
    final mutedText = isDark ? const Color(0xFF71717A) : const Color(0xFF8E8E93);
    final tagBg = isDark ? const Color(0xFF1E1E22) : const Color(0xFFF1F1F4);

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
          backgroundColor: bg,
          appBar: AppBar(
            backgroundColor: bg,
            foregroundColor: primaryBlack,
            elevation: 0,
            scrolledUnderElevation: 0,
            title: Text(
              section?.title ?? 'Apartado',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 17,
                color: primaryBlack,
              ),
            ),
          ),
          floatingActionButton: permissions.canUpload
              ? FloatingActionButton.extended(
                  onPressed: widget.controller.busy ? null : _upload,
                  backgroundColor: isDark ? Colors.white : const Color(0xFF111111),
                  foregroundColor: isDark ? const Color(0xFF111111) : Colors.white,
                  elevation: 4,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                  ),
                  icon: const Icon(Icons.upload_file_rounded, size: 18),
                  label: const Text(
                    'Subir archivo',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                )
              : null,
          body: section == null
              ? AppErrorView(
                  message: 'No se encontró el apartado',
                  onRetry: () => widget.controller.load(refresh: true),
                )
              : RefreshIndicator(
                  color: primaryBlack,
                  onRefresh: () async {
                    setState(() {
                      _extraComments = null;
                      _commentsTotal = null;
                    });
                    await widget.controller.load(refresh: true);
                  },
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
                    children: [
                      if (widget.controller.busy)
                        const LinearProgressIndicator(minHeight: 2),

                      // 1. TARJETA PRINCIPAL DEL APARTADO (HERO)
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: cardBg,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: borderColor, width: 1.4),
                          boxShadow: [
                            BoxShadow(
                              color: isDark
                                  ? Colors.black.withValues(alpha: 0.3)
                                  : Colors.black.withValues(alpha: 0.04),
                              blurRadius: 10,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                _buildStatusPill(
                                  section.status,
                                  isDark,
                                  borderColor,
                                  primaryBlack,
                                  tagBg,
                                ),
                                const Spacer(),
                                if (permissions.canEdit)
                                  OutlinedButton.icon(
                                    onPressed: widget.controller.busy
                                        ? null
                                        : _changeStatus,
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: primaryBlack,
                                      side: BorderSide(color: borderColor, width: 1.2),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(999),
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 6,
                                      ),
                                      visualDensity: VisualDensity.compact,
                                    ),
                                    icon: const Icon(Icons.edit_outlined, size: 14),
                                    label: const Text(
                                      'Cambiar estado',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            if (section.description.isNotEmpty) ...[
                              const SizedBox(height: 14),
                              Container(height: 1, color: borderColor),
                              const SizedBox(height: 12),
                              Text(
                                section.description,
                                style: TextStyle(
                                  color: secondaryText,
                                  fontSize: 13,
                                  height: 1.45,
                                ),
                              ),
                            ],
                            const SizedBox(height: 14),
                            // Progreso de entregas
                            Builder(
                              builder: (context) {
                                final totalSlots = section.slots.length;
                                final completedSlots = section.slots
                                    .where((s) =>
                                        s.filled ||
                                        section.documents
                                            .any((d) => d.slotKey == s.key))
                                    .length;
                                final progress = totalSlots == 0
                                    ? 0.0
                                    : (completedSlots / totalSlots);

                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          'Progreso de entregas',
                                          style: TextStyle(
                                            color: mutedText,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        Text(
                                          '$completedSlots de $totalSlots completadas',
                                          style: TextStyle(
                                            color: primaryBlack,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Container(
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(999),
                                        border: Border.all(
                                          color: borderColor,
                                          width: 1.0,
                                        ),
                                      ),
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(999),
                                        child: LinearProgressIndicator(
                                          value: progress,
                                          minHeight: 6,
                                          backgroundColor: isDark
                                              ? const Color(0xFF26262B)
                                              : const Color(0xFFEAEAED),
                                          valueColor:
                                              AlwaysStoppedAnimation<Color>(
                                            isDark
                                                ? Colors.white
                                                : const Color(0xFF111111),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                          ],
                        ),
                      ),

                      // 2. SECCIÓN DE ENTREGAS
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Text(
                            'Entregas (${section.slots.length})',
                            style: TextStyle(
                              color: primaryBlack,
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const Spacer(),
                          if (permissions.canEdit)
                            FilledButton.icon(
                              onPressed: widget.controller.busy
                                  ? null
                                  : _addCustomSlot,
                              style: FilledButton.styleFrom(
                                backgroundColor: isDark
                                    ? Colors.white
                                    : const Color(0xFF111111),
                                foregroundColor: isDark
                                    ? const Color(0xFF111111)
                                    : Colors.white,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 8,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(999),
                                ),
                              ),
                              icon: const Icon(Icons.add_rounded, size: 16),
                              label: const Text(
                                'Nueva entrega',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (section.slots.isEmpty)
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: cardBg,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: borderColor, width: 1.2),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: tagBg,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: borderColor),
                                ),
                                child: Icon(
                                  Icons.info_outline_rounded,
                                  size: 18,
                                  color: primaryBlack,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Sin entregas específicas configuradas. Puedes subir tus archivos con el botón flotante.',
                                  style: TextStyle(
                                    color: secondaryText,
                                    fontSize: 13,
                                    height: 1.35,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )
                      else
                        for (final slot in section.slots) ...[
                          _buildSlotCard(context, slot, section, permissions),
                          const SizedBox(height: 12),
                        ],

                      // 3. SECCIÓN DE DOCUMENTOS
                      const SizedBox(height: 24),
                      Text(
                        'Documentos (${section.documents.length})',
                        style: TextStyle(
                          color: primaryBlack,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (section.documents.isEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            vertical: 18,
                            horizontal: 16,
                          ),
                          decoration: BoxDecoration(
                            color: cardBg,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: borderColor, width: 1.2),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: tagBg,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: borderColor),
                                ),
                                child: Icon(
                                  Icons.folder_open_rounded,
                                  size: 18,
                                  color: primaryBlack,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Aún no hay documentos en este apartado.',
                                  style: TextStyle(
                                    color: secondaryText,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )
                      else
                        for (final doc in section.documents) ...[
                          _buildDocumentTile(
                            context,
                            doc,
                            section,
                            canDeleteDocs,
                          ),
                          const SizedBox(height: 10),
                        ],

                      // 4. SECCIÓN DE COMENTARIOS
                      const SizedBox(height: 28),
                      Text(
                        'Comentarios ($commentsCount)',
                        style: TextStyle(
                          color: primaryBlack,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (comments.isEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            vertical: 18,
                            horizontal: 16,
                          ),
                          decoration: BoxDecoration(
                            color: cardBg,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: borderColor, width: 1.2),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: tagBg,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: borderColor),
                                ),
                                child: Icon(
                                  Icons.chat_bubble_outline_rounded,
                                  size: 18,
                                  color: primaryBlack,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                'Sin comentarios todavía.',
                                style: TextStyle(
                                  color: secondaryText,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        )
                      else
                        for (final comment in comments) ...[
                          Container(
                            decoration: BoxDecoration(
                              color: cardBg,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: borderColor,
                                width: 1.4,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: isDark
                                      ? Colors.black.withValues(alpha: 0.2)
                                      : Colors.black.withValues(alpha: 0.02),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      width: 28,
                                      height: 28,
                                      decoration: BoxDecoration(
                                        color: tagBg,
                                        shape: BoxShape.circle,
                                        border: Border.all(color: borderColor),
                                      ),
                                      alignment: Alignment.center,
                                      child: Text(
                                        comment.authorName.isNotEmpty
                                            ? comment.authorName[0].toUpperCase()
                                            : 'U',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 12,
                                          color: primaryBlack,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        comment.authorName,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 13,
                                          color: primaryBlack,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      formatRelativeTime(comment.createdAt),
                                      style: TextStyle(
                                        color: mutedText,
                                        fontSize: 11,
                                      ),
                                    ),
                                    if (_canDeleteComment(comment)) ...[
                                      const SizedBox(width: 4),
                                      IconButton(
                                        tooltip: 'Eliminar',
                                        icon: const Icon(
                                          Icons.delete_outline_rounded,
                                          size: 16,
                                          color: Colors.redAccent,
                                        ),
                                        splashRadius: 16,
                                        onPressed: widget.controller.busy
                                            ? null
                                            : () => _deleteComment(comment),
                                      ),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  comment.body,
                                  style: TextStyle(
                                    color: secondaryText,
                                    fontSize: 13,
                                    height: 1.4,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),
                        ],
                      if (commentsCount > comments.length) ...[
                        const SizedBox(height: 4),
                        Align(
                          alignment: Alignment.center,
                          child: TextButton(
                            onPressed: _loadAllComments,
                            child: Text(
                              'Ver todos los comentarios ($commentsCount)',
                              style: TextStyle(
                                color: primaryBlack,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ],
                      if (permissions.canComment) ...[
                        const SizedBox(height: 16),
                        TextField(
                          controller: _commentController,
                          maxLength: 4000,
                          minLines: 2,
                          maxLines: 4,
                          style: TextStyle(color: primaryBlack, fontSize: 13),
                          decoration: InputDecoration(
                            labelText: 'Escribe un comentario',
                            labelStyle: TextStyle(color: mutedText, fontSize: 13),
                            hintText: 'Puedes mencionar con @correo',
                            hintStyle: TextStyle(color: mutedText, fontSize: 12),
                            filled: true,
                            fillColor: cardBg,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(color: borderColor),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(color: borderColor),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(
                                color: primaryBlack,
                                width: 1.5,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: FilledButton.icon(
                            onPressed:
                                widget.controller.busy ? null : _sendComment,
                            style: FilledButton.styleFrom(
                              backgroundColor: isDark
                                  ? Colors.white
                                  : const Color(0xFF111111),
                              foregroundColor: isDark
                                  ? const Color(0xFF111111)
                                  : Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 18,
                                vertical: 10,
                              ),
                            ),
                            icon: const Icon(Icons.send_rounded, size: 15),
                            label: const Text(
                              'Enviar',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF141417) : Colors.white;
    final borderColor = isDark ? const Color(0xFF3F3F46) : const Color(0xFFD1D5DB);
    final primaryBlack = isDark ? Colors.white : const Color(0xFF111111);
    final mutedText = isDark ? const Color(0xFF71717A) : const Color(0xFF8E8E93);
    final tagBg = isDark ? const Color(0xFF1E1E22) : const Color(0xFFF1F1F4);

    final slotDocs =
        section.documents.where((d) => d.slotKey == slot.key).toList();
    final isFilled = slot.filled || slotDocs.isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor, width: 1.4),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.25)
                : Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: isFilled
                      ? (isDark ? Colors.white : const Color(0xFF111111))
                      : tagBg,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: borderColor, width: 1.0),
                ),
                child: Icon(
                  isFilled
                      ? Icons.check_rounded
                      : (slot.required
                          ? Icons.assignment_late_outlined
                          : Icons.assignment_outlined),
                  color: isFilled
                      ? (isDark ? const Color(0xFF111111) : Colors.white)
                      : primaryBlack,
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
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        color: primaryBlack,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        if (slot.required)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: tagBg,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: isDark ? Colors.white24 : Colors.black26,
                                width: 1.0,
                              ),
                            ),
                            child: Text(
                              'Requerido',
                              style: TextStyle(
                                color: primaryBlack,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: isFilled
                                ? (isDark
                                    ? Colors.white12
                                    : Colors.black.withValues(alpha: 0.05))
                                : tagBg,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: borderColor, width: 1.0),
                          ),
                          child: Text(
                            isFilled
                                ? 'Entregado (${slotDocs.length})'
                                : 'Pendiente',
                            style: TextStyle(
                              color: isFilled ? primaryBlack : mutedText,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (slot.accept.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: tagBg,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: borderColor, width: 1.0),
                            ),
                            child: Text(
                              slot.accept.join(', '),
                              style: TextStyle(
                                color: mutedText,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
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
                  icon: Icon(Icons.close_rounded, size: 18, color: mutedText),
                  splashRadius: 18,
                  onPressed: widget.controller.busy
                      ? null
                      : () => _deleteSlot(slot),
                ),
            ],
          ),
          if (permissions.canUpload) ...[
            const SizedBox(height: 14),
            Container(height: 1, color: borderColor),
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
                style: OutlinedButton.styleFrom(
                  foregroundColor: primaryBlack,
                  side: BorderSide(color: borderColor, width: 1.2),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                icon: const Icon(Icons.upload_file_rounded, size: 18),
                label: Text(
                  isFilled
                      ? 'Subir otro archivo para esta entrega'
                      : 'Subir esta entrega',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF141417) : Colors.white;
    final borderColor = isDark ? const Color(0xFF3F3F46) : const Color(0xFFD1D5DB);
    final primaryBlack = isDark ? Colors.white : const Color(0xFF111111);
    final mutedText = isDark ? const Color(0xFF71717A) : const Color(0xFF8E8E93);
    final tagBg = isDark ? const Color(0xFF1E1E22) : const Color(0xFFF1F1F4);

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

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: 1.4),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.25)
                : Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: tagBg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: borderColor, width: 1.0),
            ),
            child: Icon(docIcon, color: primaryBlack, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  doc.originalFilename,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: primaryBlack,
                  ),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      _formatSize(doc.fileSize),
                      style: TextStyle(color: mutedText, fontSize: 12),
                    ),
                    if (slotDisplay != null && slotDisplay.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: tagBg,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: borderColor, width: 1.0),
                        ),
                        child: Text(
                          slotDisplay,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: primaryBlack,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Abrir',
            icon: Icon(Icons.open_in_new_rounded, size: 18, color: primaryBlack),
            splashRadius: 18,
            onPressed: () => _openDoc(doc),
          ),
          if (canDeleteDocs)
            IconButton(
              tooltip: 'Eliminar',
              icon: const Icon(
                Icons.delete_outline_rounded,
                size: 18,
                color: Colors.redAccent,
              ),
              splashRadius: 18,
              onPressed: widget.controller.busy
                  ? null
                  : () => _deleteDoc(doc),
            ),
        ],
      ),
    );
  }
}
