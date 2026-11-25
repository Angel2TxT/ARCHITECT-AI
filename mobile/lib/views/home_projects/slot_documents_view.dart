import 'package:flutter/material.dart';
import 'package:movil_architect/controllers/home_project_controller.dart';
import 'package:movil_architect/core/utils/app_notifications.dart';
import 'package:movil_architect/models/home_project_models.dart';
import 'package:movil_architect/views/shared/attachment_picker_sheet.dart';

enum _DocTypeFilter { all, pdf, word, excel, image, other }

enum _DocDateFilter { all, today, last7Days, custom }

/// Vista dedicada de archivos para una entrega específica de un apartado.
class SlotDocumentsView extends StatefulWidget {
  const SlotDocumentsView({
    super.key,
    required this.controller,
    required this.stageNumber,
    required this.sectionId,
    required this.slot,
  });

  final HomeProjectDetailController controller;
  final int stageNumber;
  final int sectionId;
  final HomeProjectSlot slot;

  @override
  State<SlotDocumentsView> createState() => _SlotDocumentsViewState();
}

class _SlotDocumentsViewState extends State<SlotDocumentsView> {
  _DocTypeFilter _typeFilter = _DocTypeFilter.all;
  _DocDateFilter _dateFilter = _DocDateFilter.all;
  DateTime? _customDate;
  bool _newestFirst = true;

  HomeProjectSection? get _section =>
      widget.controller.project?.sectionById(widget.sectionId);

  _DocTypeFilter _classifyDoc(HomeProjectDocument doc) {
    final name = doc.originalFilename.toLowerCase();
    if (name.endsWith('.pdf')) return _DocTypeFilter.pdf;
    if (name.endsWith('.doc') || name.endsWith('.docx')) {
      return _DocTypeFilter.word;
    }
    if (name.endsWith('.xls') || name.endsWith('.xlsx')) {
      return _DocTypeFilter.excel;
    }
    if (doc.isImage ||
        name.endsWith('.png') ||
        name.endsWith('.jpg') ||
        name.endsWith('.jpeg') ||
        name.endsWith('.webp')) {
      return _DocTypeFilter.image;
    }
    return _DocTypeFilter.other;
  }

  String _typeLabel(_DocTypeFilter filter) => switch (filter) {
    _DocTypeFilter.all => 'Todos',
    _DocTypeFilter.pdf => 'PDF',
    _DocTypeFilter.word => 'Word',
    _DocTypeFilter.excel => 'Excel',
    _DocTypeFilter.image => 'Imagen',
    _DocTypeFilter.other => 'Otros',
  };

  IconData _typeIcon(_DocTypeFilter filter) => switch (filter) {
    _DocTypeFilter.all => Icons.filter_list_rounded,
    _DocTypeFilter.pdf => Icons.picture_as_pdf_outlined,
    _DocTypeFilter.word => Icons.article_outlined,
    _DocTypeFilter.excel => Icons.table_chart_outlined,
    _DocTypeFilter.image => Icons.image_outlined,
    _DocTypeFilter.other => Icons.description_outlined,
  };

  String _dateLabel(_DocDateFilter filter) => switch (filter) {
    _DocDateFilter.all => 'Todas',
    _DocDateFilter.today => 'Hoy',
    _DocDateFilter.last7Days => '7 días',
    _DocDateFilter.custom =>
      _customDate == null
          ? 'Fecha'
          : '${_customDate!.day.toString().padLeft(2, '0')}/${_customDate!.month.toString().padLeft(2, '0')}/${_customDate!.year}',
  };

  bool _matchesDate(HomeProjectDocument doc, DateTime now) {
    if (_dateFilter == _DocDateFilter.all) return true;
    final dt = doc.createdAt?.toLocal();
    if (dt == null) return false;
    final todayStart = DateTime(now.year, now.month, now.day);
    return switch (_dateFilter) {
      _DocDateFilter.all => true,
      _DocDateFilter.today => !dt.isBefore(todayStart),
      _DocDateFilter.last7Days => !dt.isBefore(
        now.subtract(const Duration(days: 7)),
      ),
      _DocDateFilter.custom =>
        _customDate == null ||
            (dt.year == _customDate!.year &&
                dt.month == _customDate!.month &&
                dt.day == _customDate!.day),
    };
  }

  Future<void> _pickManualDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _customDate ?? now,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year + 1, 12, 31),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _customDate = picked;
      _dateFilter = _DocDateFilter.custom;
    });
  }

  Future<void> _upload() async {
    if (!widget.controller.permissions.canUpload) return;
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

    final ok = await widget.controller.uploadDocument(
      stageNumber: widget.stageNumber,
      sectionId: widget.sectionId,
      file: file,
      slotKey: widget.slot.key,
    );
    if (!mounted) return;
    AppNotifications.result(
      context,
      ok: ok,
      successMessage: 'Documento subido',
      errorMessage: widget.controller.actionError,
    );
  }

  Future<void> _openDoc(HomeProjectDocument doc) async {
    final error = await widget.controller.openDocument(doc);
    if (error != null && mounted) {
      AppNotifications.error(context, error);
    }
  }

  Future<void> _deleteDoc(HomeProjectDocument doc) async {
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

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String _formatDate(DateTime? dt) {
    if (dt == null) return 'Sin fecha';
    final local = dt.toLocal();
    final d = local.day.toString().padLeft(2, '0');
    final m = local.month.toString().padLeft(2, '0');
    final y = local.year.toString();
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '$d/$m/$y $hh:$mm';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF0A0A0C) : const Color(0xFFF6F6F8);
    final cardBg = isDark ? const Color(0xFF141417) : Colors.white;
    final borderColor = isDark
        ? const Color(0xFF3F3F46)
        : const Color(0xFFD1D5DB);
    final primaryBlack = isDark ? Colors.white : const Color(0xFF111111);
    final secondaryText = isDark
        ? const Color(0xFFA1A1AA)
        : const Color(0xFF52525B);
    final mutedText = isDark
        ? const Color(0xFF71717A)
        : const Color(0xFF8E8E93);
    final tagBg = isDark ? const Color(0xFF1E1E22) : const Color(0xFFF1F1F4);

    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final section = _section;
        final permissions = widget.controller.permissions;
        final canDeleteDocs =
            permissions.canDeleteDocuments || permissions.canEdit;
        final allSlotDocs =
            (section?.documents ?? const <HomeProjectDocument>[])
                .where((d) => d.slotKey == widget.slot.key)
                .toList();

        final now = DateTime.now();
        final filtered =
            allSlotDocs.where((doc) {
              if (_typeFilter != _DocTypeFilter.all &&
                  _classifyDoc(doc) != _typeFilter) {
                return false;
              }
              return _matchesDate(doc, now);
            }).toList()..sort((a, b) {
              final da = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
              final db = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
              return _newestFirst ? db.compareTo(da) : da.compareTo(db);
            });

        return Scaffold(
          backgroundColor: bg,
          appBar: AppBar(
            backgroundColor: bg,
            foregroundColor: primaryBlack,
            elevation: 0,
            scrolledUnderElevation: 0,
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.slot.title,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    color: primaryBlack,
                  ),
                ),
                Text(
                  '${allSlotDocs.length} archivo(s)',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: secondaryText,
                  ),
                ),
              ],
            ),
            actions: [
              PopupMenuButton<_DocTypeFilter>(
                tooltip: 'Filtrar por tipo (${_typeLabel(_typeFilter)})',
                initialValue: _typeFilter,
                onSelected: (value) => setState(() => _typeFilter = value),
                icon: Icon(_typeIcon(_typeFilter)),
                itemBuilder: (context) => [
                    for (final filter in [
                      _DocTypeFilter.all,
                      _DocTypeFilter.pdf,
                      _DocTypeFilter.word,
                      _DocTypeFilter.excel,
                      _DocTypeFilter.image,
                    ])
                      PopupMenuItem(
                        value: filter,
                        child: Row(
                          children: [
                            Icon(
                              _typeIcon(filter),
                              size: 18,
                              color: primaryBlack,
                            ),
                            const SizedBox(width: 10),
                            Text(
                              _typeLabel(filter),
                              style: TextStyle(
                                fontWeight: _typeFilter == filter
                                    ? FontWeight.w800
                                    : FontWeight.w500,
                                color: primaryBlack,
                              ),
                            ),
                          ],
                        ),
                      ),
                ],
              ),
              IconButton(
                tooltip: _newestFirst ? 'Más recientes' : 'Más antiguos',
                onPressed: () => setState(() => _newestFirst = !_newestFirst),
                icon: Icon(
                  _newestFirst
                      ? Icons.arrow_downward_rounded
                      : Icons.arrow_upward_rounded,
                ),
              ),
              if (permissions.canUpload)
                IconButton(
                  tooltip: 'Subir archivo',
                  onPressed: widget.controller.busy ? null : _upload,
                  icon: const Icon(Icons.upload_file_rounded),
                ),
            ],
          ),
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
                child: Row(
                  children: [
                    if (_typeFilter != _DocTypeFilter.all) ...[
                      InputChip(
                        avatar: Icon(
                          _typeIcon(_typeFilter),
                          size: 16,
                          color: isDark
                              ? const Color(0xFF111111)
                              : Colors.white,
                        ),
                        label: Text(_typeLabel(_typeFilter)),
                        onDeleted: () =>
                            setState(() => _typeFilter = _DocTypeFilter.all),
                        deleteIconColor: isDark
                            ? const Color(0xFF111111)
                            : Colors.white,
                        backgroundColor: primaryBlack,
                        labelStyle: TextStyle(
                          color: isDark
                              ? const Color(0xFF111111)
                              : Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            for (final df in [
                              _DocDateFilter.all,
                              _DocDateFilter.today,
                              _DocDateFilter.last7Days,
                            ]) ...[
                              ChoiceChip(
                                label: Text(_dateLabel(df)),
                                selected: _dateFilter == df,
                                onSelected: (_) => setState(() {
                                  _dateFilter = df;
                                  _customDate = null;
                                }),
                                selectedColor: primaryBlack,
                                backgroundColor: cardBg,
                                labelStyle: TextStyle(
                                  color: _dateFilter == df
                                      ? (isDark
                                            ? const Color(0xFF111111)
                                            : Colors.white)
                                      : primaryBlack,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12,
                                ),
                                side: BorderSide(color: borderColor),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(999),
                                ),
                              ),
                              const SizedBox(width: 8),
                            ],
                            ActionChip(
                              avatar: Icon(
                                Icons.calendar_today_rounded,
                                size: 15,
                                color: _dateFilter == _DocDateFilter.custom
                                    ? (isDark
                                          ? const Color(0xFF111111)
                                          : Colors.white)
                                    : primaryBlack,
                              ),
                              label: Text(_dateLabel(_DocDateFilter.custom)),
                              onPressed: _pickManualDate,
                              backgroundColor:
                                  _dateFilter == _DocDateFilter.custom
                                  ? primaryBlack
                                  : cardBg,
                              labelStyle: TextStyle(
                                color: _dateFilter == _DocDateFilter.custom
                                    ? (isDark
                                          ? const Color(0xFF111111)
                                          : Colors.white)
                                    : primaryBlack,
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                              ),
                              side: BorderSide(color: borderColor),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(999),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: filtered.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.folder_open_rounded,
                                size: 42,
                                color: mutedText,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                allSlotDocs.isEmpty
                                    ? 'Aún no hay archivos en esta entrega.'
                                    : 'No hay archivos que coincidan con los filtros.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: secondaryText,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                        itemCount: filtered.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final doc = filtered[index];
                          final type = _classifyDoc(doc);
                          final IconData docIcon = switch (type) {
                            _DocTypeFilter.image => Icons.image_outlined,
                            _DocTypeFilter.pdf => Icons.picture_as_pdf_outlined,
                            _DocTypeFilter.word => Icons.article_outlined,
                            _DocTypeFilter.excel => Icons.table_chart_outlined,
                            _ => Icons.description_outlined,
                          };
                          return Container(
                            decoration: BoxDecoration(
                              color: cardBg,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: borderColor,
                                width: 1.4,
                              ),
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
                                    border: Border.all(color: borderColor),
                                  ),
                                  child: Icon(
                                    docIcon,
                                    color: primaryBlack,
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        doc.originalFilename,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: primaryBlack,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 14,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${_formatSize(doc.fileSize)} · ${_formatDate(doc.createdAt)}',
                                        style: TextStyle(
                                          color: secondaryText,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Abrir',
                                  icon: Icon(
                                    Icons.open_in_new_rounded,
                                    size: 20,
                                    color: primaryBlack,
                                  ),
                                  onPressed: () => _openDoc(doc),
                                ),
                                if (canDeleteDocs)
                                  IconButton(
                                    tooltip: 'Eliminar',
                                    icon: const Icon(
                                      Icons.delete_outline_rounded,
                                      size: 20,
                                      color: Colors.redAccent,
                                    ),
                                    onPressed: widget.controller.busy
                                        ? null
                                        : () => _deleteDoc(doc),
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}
