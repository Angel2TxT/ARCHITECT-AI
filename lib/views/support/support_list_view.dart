import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:movil_architect/core/app_services.dart';
import 'package:movil_architect/core/network/api_exception.dart';
import 'package:movil_architect/core/theme/app_colors.dart';
import 'package:movil_architect/core/utils/app_notifications.dart';
import 'package:movil_architect/models/support_models.dart';
import 'package:movil_architect/views/support/support_ticket_view.dart';

class SupportListView extends StatefulWidget {
  const SupportListView({super.key});

  @override
  State<SupportListView> createState() => _SupportListViewState();
}

class _SupportListViewState extends State<SupportListView> {
  bool _loading = true;
  bool _creating = false;
  bool _showOpenTab = true;
  bool _pickingAttachment = false;
  String? _error;
  List<SupportTicket> _tickets = [];
  final _subject = TextEditingController();
  final _body = TextEditingController();
  String? _attachmentName;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _subject.dispose();
    _body.dispose();
    super.dispose();
  }

  bool _isResolved(SupportTicket ticket) {
    final status = ticket.status.toLowerCase().trim();
    return status == 'closed' ||
        status == 'resolved' ||
        status == 'done' ||
        status == 'resuelto' ||
        status == 'cerrado';
  }

  List<SupportTicket> get _openTickets =>
      _tickets.where((t) => !_isResolved(t)).toList();

  List<SupportTicket> get _resolvedTickets =>
      _tickets.where(_isResolved).toList();

  List<SupportTicket> get _visibleTickets =>
      _showOpenTab ? _openTickets : _resolvedTickets;

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _tickets =
          await AppServices.instance.supportService.listTickets(limit: 100);
    } on ApiException catch (error) {
      _error = error.message;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickAttachment() async {
    if (_pickingAttachment) return;
    _pickingAttachment = true;
    try {
      final picker = ImagePicker();
      final shot = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 2000,
        imageQuality: 85,
      );
      if (shot == null) return;
      final file = File(shot.path);
      final size = await file.length();
      if (size > 10 * 1024 * 1024) {
        if (!mounted) return;
        AppNotifications.error(context, 'La captura no puede superar 10 MB.');
        return;
      }
      if (mounted) {
        setState(() {
          _attachmentName = shot.name;
        });
      }
    } on PlatformException catch (e) {
      debugPrint('SupportListView: PlatformException ${e.code}: ${e.message}');
    } catch (e) {
      debugPrint('SupportListView: error picking attachment: $e');
    } finally {
      _pickingAttachment = false;
    }
  }

  void _clearAttachment() {
    setState(() {
      _attachmentName = null;
    });
  }

  Future<void> _create() async {
    final subject = _subject.text.trim();
    final body = _body.text.trim();
    if (subject.isEmpty) {
      AppNotifications.error(context, 'Escribe un asunto');
      return;
    }
    if (body.length < 5) {
      AppNotifications.error(context, 'Describe el problema con más detalle');
      return;
    }
    if (_creating) return;

    setState(() => _creating = true);
    try {
      final description = _attachmentName == null
          ? body
          : '$body\n\n[Adjunto seleccionado: $_attachmentName]';
      final ticket = await AppServices.instance.supportService.createTicket(
        subject: subject,
        body: description,
      );
      _subject.clear();
      _body.clear();
      _clearAttachment();
      await _load();
      if (!mounted) return;
      AppNotifications.success(context, 'Ticket enviado');
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => SupportTicketView(ticketId: ticket.id),
        ),
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      AppNotifications.error(context, error.message);
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<void> _confirmDeleteAll() async {
    if (_tickets.isEmpty) {
      AppNotifications.error(context, 'No hay tickets para eliminar');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar todos los tickets'),
        content: Text(
          '¿Borrar los ${_tickets.length} tickets?\n'
          'Esta acción no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Eliminar todo',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Eliminando tickets…'),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      await AppServices.instance.supportService.deleteAllTickets(
        _tickets.map((ticket) => ticket.id).toList(),
      );
      if (!mounted) return;
      Navigator.pop(context);
      await _load();
      if (!mounted) return;
      AppNotifications.success(context, 'Tickets eliminados');
    } on ApiException catch (error) {
      if (!mounted) return;
      Navigator.pop(context);
      AppNotifications.error(context, error.message);
    } catch (_) {
      if (!mounted) return;
      Navigator.pop(context);
      AppNotifications.error(context, 'No se pudieron eliminar los tickets');
    }
  }

  void _showHelpInfo() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Centro de ayuda',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Crea un ticket con el asunto y la descripción del problema. '
                  'Nuestro equipo suele responder en menos de 24 horas.',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = colorScheme.brightness == Brightness.dark;
    final pageBg = isDark ? colorScheme.surface : AppColors.dashboardSurface;

    return Scaffold(
      backgroundColor: pageBg,
      appBar: AppBar(
        title: const Text(
          'Ayuda y soporte',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        backgroundColor: pageBg,
        elevation: 0,
        scrolledUnderElevation: 0,
        actions: [
          IconButton(
            onPressed: _showHelpInfo,
            tooltip: 'Ayuda',
            icon: const Icon(Icons.help_outline_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                children: [
                  if (_error != null) ...[
                    Text(
                      _error!,
                      style: const TextStyle(color: Colors.redAccent),
                    ),
                    const SizedBox(height: 12),
                  ],
                  Text(
                    '¿En qué podemos ayudarte?',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: colorScheme.onSurface,
                          fontWeight: FontWeight.w800,
                          fontSize: 22,
                          height: 1.25,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Envíanos un mensaje y te responderemos a la brevedad.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          fontSize: 14,
                          height: 1.4,
                          fontWeight: FontWeight.w500,
                        ),
                  ),
                  const SizedBox(height: 28),
                  _NewTicketCard(
                    subjectController: _subject,
                    bodyController: _body,
                    attachmentName: _attachmentName,
                    isCreating: _creating,
                    onAttach: _pickAttachment,
                    onClearAttachment: _clearAttachment,
                    onSubmit: _create,
                  ),
                  const SizedBox(height: 28),
                  Row(
                    children: [
                      Text(
                        'Mis tickets',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              color: colorScheme.onSurface,
                              fontWeight: FontWeight.w800,
                              fontSize: 18,
                            ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        constraints: const BoxConstraints(minWidth: 24),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: isDark
                              ? colorScheme.surfaceContainerHighest
                              : const Color(0xFFE8E8EA),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '${_tickets.length}',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: colorScheme.onSurface,
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: _confirmDeleteAll,
                        tooltip: 'Eliminar todo',
                        icon: Icon(
                          Icons.delete_outline_rounded,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _TicketTabs(
                    openCount: _openTickets.length,
                    resolvedCount: _resolvedTickets.length,
                    showOpen: _showOpenTab,
                    onChanged: (open) => setState(() => _showOpenTab = open),
                  ),
                  const SizedBox(height: 14),
                  if (_visibleTickets.isEmpty)
                    const _EmptyTicketsState()
                  else
                    ..._visibleTickets.map(
                      (ticket) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _TicketCard(
                          ticket: ticket,
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) =>
                                    SupportTicketView(ticketId: ticket.id),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}

class _NewTicketCard extends StatelessWidget {
  const _NewTicketCard({
    required this.subjectController,
    required this.bodyController,
    required this.attachmentName,
    required this.isCreating,
    required this.onAttach,
    required this.onClearAttachment,
    required this.onSubmit,
  });

  final TextEditingController subjectController;
  final TextEditingController bodyController;
  final String? attachmentName;
  final bool isCreating;
  final VoidCallback onAttach;
  final VoidCallback onClearAttachment;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = colorScheme.brightness == Brightness.dark;
    final cardBg =
        isDark ? colorScheme.surfaceContainerHighest : Colors.white;
    final fieldBg =
        isDark ? colorScheme.surfaceContainerHigh : const Color(0xFFF7F7F8);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.06)
              : const Color(0xFFE8E8EC),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: colorScheme.onSurface,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'NUEVO TICKET',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: colorScheme.onSurface,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                      letterSpacing: 0.6,
                    ),
              ),
              const Spacer(),
              Text(
                'Respuesta < 24h',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            'ASUNTO',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: subjectController,
            textInputAction: TextInputAction.next,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
            decoration: _fieldDecoration(
              context,
              fieldBg,
              'Ej. Problema con la suscripción',
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'DESCRIPCIÓN',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: bodyController,
            minLines: 4,
            maxLines: 6,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
            decoration: _fieldDecoration(
              context,
              fieldBg,
              'Describe con detalle lo que sucede o cómo podemos apoyarte...',
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(
                Icons.attach_file_rounded,
                size: 18,
                color: colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: InkWell(
                  onTap: onAttach,
                  child: Text(
                    attachmentName ?? 'Adjuntar captura',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colorScheme.onSurface,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
              if (attachmentName != null)
                IconButton(
                  onPressed: onClearAttachment,
                  icon: const Icon(Icons.close_rounded, size: 18),
                  visualDensity: VisualDensity.compact,
                )
              else
                Text(
                  'Máx. 10MB',
                  style: TextStyle(
                    color: colorScheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton(
              onPressed: isCreating ? null : onSubmit,
              style: FilledButton.styleFrom(
                backgroundColor: isDark ? Colors.white : AppColors.ink,
                foregroundColor: isDark ? AppColors.ink : Colors.white,
                disabledBackgroundColor:
                    (isDark ? Colors.white : AppColors.ink)
                        .withValues(alpha: 0.45),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              child: isCreating
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: isDark ? AppColors.ink : Colors.white,
                      ),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Enviar ticket',
                          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              ),
                        ),
                        const SizedBox(width: 8),
                        const Icon(Icons.arrow_forward_rounded, size: 18),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _fieldDecoration(
    BuildContext context,
    Color fill,
    String hint,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    return InputDecoration(
      hintText: hint,
      hintStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.75),
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
      filled: true,
      fillColor: fill,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: colorScheme.onSurface, width: 1.2),
      ),
    );
  }
}

class _TicketTabs extends StatelessWidget {
  const _TicketTabs({
    required this.openCount,
    required this.resolvedCount,
    required this.showOpen,
    required this.onChanged,
  });

  final int openCount;
  final int resolvedCount;
  final bool showOpen;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = colorScheme.brightness == Brightness.dark;
    final track = isDark
        ? colorScheme.surfaceContainerHigh
        : const Color(0xFFE8E8EA);

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: track,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: _TabChip(
              label: 'Abiertos ($openCount)',
              selected: showOpen,
              onTap: () => onChanged(true),
            ),
          ),
          Expanded(
            child: _TabChip(
              label: 'Resueltos ($resolvedCount)',
              selected: !showOpen,
              onTap: () => onChanged(false),
            ),
          ),
        ],
      ),
    );
  }
}

class _TabChip extends StatelessWidget {
  const _TabChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = colorScheme.brightness == Brightness.dark;

    return Material(
      color: selected
          ? (isDark ? colorScheme.surfaceContainerHighest : Colors.white)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(11),
      elevation: selected && !isDark ? 1 : 0,
      shadowColor: const Color(0x14000000),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(11),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child:           Text(
            label,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: colorScheme.onSurface,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  fontSize: 13,
                ),
          ),
        ),
      ),
    );
  }
}

class _EmptyTicketsState extends StatelessWidget {
  const _EmptyTicketsState();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 36, 20, 36),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.55),
        ),
      ),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: colorScheme.outlineVariant,
              ),
            ),
            child: Icon(
              Icons.confirmation_number_outlined,
              color: colorScheme.onSurfaceVariant,
              size: 28,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Aún no tienes tickets',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Tus solicitudes de asistencia técnica y seguimiento de consultas aparecerán aquí.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  height: 1.4,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
          ),
        ],
      ),
    );
  }
}

class _TicketCard extends StatelessWidget {
  const _TicketCard({
    required this.ticket,
    required this.onTap,
  });

  final SupportTicket ticket;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = colorScheme.brightness == Brightness.dark;

    return Material(
      color: isDark ? colorScheme.surfaceContainerHighest : Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.06)
                  : const Color(0xFFE8E8EC),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ticket.subject,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            color: colorScheme.onSurface,
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      ticket.status,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
