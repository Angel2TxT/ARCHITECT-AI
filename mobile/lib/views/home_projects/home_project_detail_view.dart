import 'package:flutter/material.dart';
import 'package:movil_architect/controllers/home_project_controller.dart';
import 'package:movil_architect/core/utils/app_notifications.dart';
import 'package:movil_architect/models/home_project_models.dart';
import 'package:movil_architect/views/home_projects/home_project_team_view.dart';
import 'package:movil_architect/views/home_projects/section_detail_view.dart';
import 'package:movil_architect/views/home_projects/stage_detail_view.dart';
import 'package:movil_architect/views/shared/app_states.dart';
import 'package:movil_architect/views/shared/skeleton.dart';

class HomeProjectDetailView extends StatefulWidget {
  const HomeProjectDetailView({super.key, required this.projectId});

  final String projectId;

  @override
  State<HomeProjectDetailView> createState() => _HomeProjectDetailViewState();
}

class _HomeProjectDetailViewState extends State<HomeProjectDetailView> {
  late final HomeProjectDetailController _controller;
  int? _selectedStage;

  @override
  void initState() {
    super.initState();
    _controller = HomeProjectDetailController(projectId: widget.projectId);
    _controller.load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _advance() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Avanzar etapa'),
        content: const Text(
          '¿Confirmas avanzar a la siguiente etapa del proyecto?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Avanzar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final ok = await _controller.advanceStage();
    if (!mounted) return;
    AppNotifications.result(
      context,
      ok: ok,
      successMessage: 'Etapa avanzada correctamente',
      errorMessage: _controller.actionError,
    );
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar proyecto'),
        content: const Text(
          'Esta acción no se puede deshacer. ¿Eliminar el proyecto?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Eliminar',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final ok = await _controller.deleteProject();
    if (!mounted) return;
    if (ok) {
      AppNotifications.success(context, 'Proyecto eliminado');
      Navigator.of(context).pop(true);
      return;
    }
    AppNotifications.error(
      context,
      _controller.actionError ?? 'No se pudo eliminar',
    );
  }

  Future<void> _openStage(HomeProjectStage stage) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => StageDetailView(
          projectId: widget.projectId,
          stageNumber: stage.stageNumber,
          controller: _controller,
        ),
      ),
    );
    if (mounted) await _controller.load(refresh: true);
  }

  Future<void> _openSection(
    HomeProjectStage stage,
    HomeProjectSection section,
  ) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SectionDetailView(
          projectId: widget.projectId,
          stageNumber: stage.stageNumber,
          sectionId: section.id,
          controller: _controller,
        ),
      ),
    );
    if (mounted) await _controller.load(refresh: true);
  }  Widget _buildStatusBadge(
    String status,
    bool isDark,
    Color borderColor,
    Color primaryBlack,
    Color tagBg,
  ) {
    final label = homeProjectStatusLabel(status);
    final isDone = status == 'completed';
    final isActive = status == 'active' || status == 'in_progress';

    if (isDone) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isDark ? Colors.white : const Color(0xFF111111),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.check_circle_rounded,
              size: 12,
              color: isDark ? const Color(0xFF111111) : Colors.white,
            ),
            const SizedBox(width: 4),
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: tagBg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: borderColor, width: 1.0),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isActive
                  ? primaryBlack
                  : (isDark ? Colors.white54 : Colors.black38),
            ),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: primaryBlack,
              fontWeight: FontWeight.w600,
              fontSize: 11,
            ),
          ),
        ],
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
      listenable: _controller,
      builder: (context, _) {
        final project = _controller.project;
        final selected = _selectedStage ?? project?.currentStage ?? 1;
        final selectedStage = project?.stageByNumber(selected);

        return Scaffold(
          backgroundColor: bg,
          appBar: AppBar(
            backgroundColor: bg,
            foregroundColor: primaryBlack,
            elevation: 0,
            scrolledUnderElevation: 0,
            title: Text(
              project?.name ?? 'Proyecto',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 17,
                color: primaryBlack,
              ),
            ),
            actions: [
              IconButton(
                tooltip: 'Equipo',
                onPressed: project == null
                    ? null
                    : () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                HomeProjectTeamView(controller: _controller),
                          ),
                        );
                      },
                icon: const Icon(Icons.groups_outlined),
              ),
              if (project?.permissions.canDeleteProject == true)
                IconButton(
                  tooltip: 'Eliminar',
                  onPressed: _controller.busy ? null : _delete,
                  icon: const Icon(Icons.delete_outline),
                ),
            ],
          ),
          body: switch (_controller.state) {
            HomeProjectsState.loading => const HomeProjectDetailSkeleton(),
            HomeProjectsState.error => AppErrorView(
                message: _controller.errorMessage ?? 'Error',
                onRetry: () => _controller.load(),
              ),
            _ when project == null => const HomeProjectDetailSkeleton(),
            _ => RefreshIndicator(
                color: primaryBlack,
                onRefresh: () => _controller.load(refresh: true),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                  children: [
                    // 1. HERO CARD: Información del proyecto
                    Container(
                      padding: const EdgeInsets.all(20),
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
                              _buildStatusBadge(
                                project.status,
                                isDark,
                                borderColor,
                                primaryBlack,
                                tagBg,
                              ),
                              const Spacer(),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: tagBg,
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(color: borderColor, width: 1.0),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.shield_outlined,
                                      size: 12,
                                      color: primaryBlack,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Rol: ${project.myRole}',
                                      style: TextStyle(
                                        color: primaryBlack,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          if (project.clientName.isNotEmpty) ...[
                            const SizedBox(height: 14),
                            Row(
                              children: [
                                Icon(Icons.person_outline, size: 16, color: secondaryText),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    project.clientName,
                                    style: TextStyle(
                                      color: primaryBlack,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 16,
                                      letterSpacing: -0.2,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                          if (project.location.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Icon(Icons.place_outlined, size: 15, color: mutedText),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    project.location,
                                    style: TextStyle(
                                      color: secondaryText,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                          if (project.description.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            Container(
                              height: 1,
                              color: borderColor.withValues(alpha: 0.6),
                            ),
                            const SizedBox(height: 12),
                            _ExpandableDescription(
                              text: project.description,
                              style: TextStyle(
                                color: secondaryText,
                                fontSize: 13,
                                height: 1.4,
                              ),
                            ),
                          ],
                          const SizedBox(height: 16),
                          Container(
                            height: 1,
                            color: borderColor.withValues(alpha: 0.6),
                          ),
                          const SizedBox(height: 14),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    'Progreso general',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: primaryBlack,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 7,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isDark
                                          ? const Color(0xFF27272A)
                                          : const Color(0xFFE4E4E7),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      '${project.progressPercent.round()}%',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                        color: primaryBlack,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              Text(
                                'Etapa ${project.currentStage}/9 · ${project.stagesCompleted} completadas',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: mutedText,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(999),
                            child: LinearProgressIndicator(
                              value: (project.progressPercent / 100).clamp(0.0, 1.0),
                              minHeight: 7,
                              backgroundColor: isDark
                                  ? const Color(0xFF27272A)
                                  : const Color(0xFFE4E4E7),
                              valueColor: AlwaysStoppedAnimation<Color>(primaryBlack),
                            ),
                          ),
                          if (project.permissions.canAdvanceStage) ...[
                            const SizedBox(height: 16),
                            SizedBox(
                              width: double.infinity,
                              height: 46,
                              child: ElevatedButton.icon(
                                onPressed: _controller.busy ? null : _advance,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: isDark
                                      ? Colors.white
                                      : const Color(0xFF111111),
                                  foregroundColor: isDark
                                      ? const Color(0xFF111111)
                                      : Colors.white,
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                                icon: _controller.busy
                                    ? SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor: AlwaysStoppedAnimation<Color>(
                                            isDark
                                                ? const Color(0xFF111111)
                                                : Colors.white,
                                          ),
                                        ),
                                      )
                                    : const Icon(Icons.arrow_forward_rounded, size: 18),
                                label: const Text(
                                  'Avanzar etapa',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),

                    // 2. SECCIÓN ETAPAS
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Text(
                          'Etapas',
                          style: TextStyle(
                            color: primaryBlack,
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: tagBg,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: borderColor, width: 1),
                          ),
                          child: Text(
                            '${project.stages.length}',
                            style: TextStyle(
                              color: primaryBlack,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 48,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: project.stages.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 8),
                        itemBuilder: (context, index) {
                          final stage = project.stages[index];
                          final isSelected = stage.stageNumber == selected;
                          final isCurrent =
                              stage.stageNumber == project.currentStage;
                          final isDone = stage.status == 'completed';

                          return Material(
                            color: isSelected
                                ? (isDark ? Colors.white : const Color(0xFF111111))
                                : cardBg,
                            borderRadius: BorderRadius.circular(14),
                            child: InkWell(
                              onTap: () => setState(
                                () => _selectedStage = stage.stageNumber,
                              ),
                              borderRadius: BorderRadius.circular(14),
                              child: Container(
                                constraints: const BoxConstraints(minWidth: 48),
                                padding: const EdgeInsets.symmetric(horizontal: 14),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: isSelected
                                        ? (isDark
                                            ? Colors.white
                                            : const Color(0xFF111111))
                                        : borderColor,
                                    width: isSelected ? 1.5 : 1.2,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    if (isCurrent) ...[
                                      Icon(
                                        Icons.flag_rounded,
                                        size: 15,
                                        color: isSelected
                                            ? (isDark
                                                ? const Color(0xFF111111)
                                                : Colors.white)
                                            : primaryBlack,
                                      ),
                                      const SizedBox(width: 6),
                                    ] else if (isDone) ...[
                                      Icon(
                                        Icons.check_rounded,
                                        size: 15,
                                        color: isSelected
                                            ? (isDark
                                                ? const Color(0xFF111111)
                                                : Colors.white)
                                            : primaryBlack,
                                      ),
                                      const SizedBox(width: 6),
                                    ],
                                    Text(
                                      '${stage.stageNumber}',
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w800,
                                        color: isSelected
                                            ? (isDark
                                                ? const Color(0xFF111111)
                                                : Colors.white)
                                            : primaryBlack,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 14),
                    for (final stage in project.stages)
                      if (stage.stageNumber == selected) ...[
                        Material(
                          color: cardBg,
                          borderRadius: BorderRadius.circular(18),
                          child: InkWell(
                            onTap: () => _openStage(stage),
                            borderRadius: BorderRadius.circular(18),
                            child: Container(
                              padding: const EdgeInsets.all(18),
                              decoration: BoxDecoration(
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
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              '${stage.stageNumber}. ${stage.title}',
                                              style: TextStyle(
                                                color: primaryBlack,
                                                fontSize: 16,
                                                fontWeight: FontWeight.w800,
                                                letterSpacing: -0.2,
                                              ),
                                            ),
                                            if (stage.summary.isNotEmpty) ...[
                                              const SizedBox(height: 6),
                                              Text(
                                                stage.summary,
                                                style: TextStyle(
                                                  color: secondaryText,
                                                  fontSize: 13,
                                                  height: 1.35,
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      _buildStatusBadge(
                                        stage.status,
                                        isDark,
                                        borderColor,
                                        primaryBlack,
                                        tagBg,
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 14),
                                  Container(
                                    height: 1,
                                    color: borderColor.withValues(alpha: 0.6),
                                  ),
                                  const SizedBox(height: 10),
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        'Ver detalle de la etapa',
                                        style: TextStyle(
                                          color: primaryBlack,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      Icon(
                                        Icons.arrow_forward_rounded,
                                        size: 16,
                                        color: primaryBlack,
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],

                    // 3. SECCIÓN APARTADOS
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Text(
                          'Apartados',
                          style: TextStyle(
                            color: primaryBlack,
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (selectedStage != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: tagBg,
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(color: borderColor, width: 1),
                            ),
                            child: Text(
                              '${selectedStage.sectionsProgress.done}/${selectedStage.sectionsProgress.total}${selectedStage.planReview ? ' · Planos' : ''}',
                              style: TextStyle(
                                color: primaryBlack,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (selectedStage == null || selectedStage.sections.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: cardBg,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: borderColor, width: 1.4),
                        ),
                        child: Center(
                          child: Text(
                            'Esta etapa no tiene apartados.',
                            style: TextStyle(color: mutedText, fontSize: 13),
                          ),
                        ),
                      )
                    else
                      for (final (index, section)
                          in selectedStage.sections.indexed)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Material(
                            color: cardBg,
                            borderRadius: BorderRadius.circular(16),
                            child: InkWell(
                              onTap: () =>
                                  _openSection(selectedStage, section),
                              borderRadius: BorderRadius.circular(16),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(16),
                                  border:
                                      Border.all(color: borderColor, width: 1.4),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 38,
                                      height: 38,
                                      decoration: BoxDecoration(
                                        color: tagBg,
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                            color: borderColor, width: 1),
                                      ),
                                      alignment: Alignment.center,
                                      child: Text(
                                        '${index + 1}',
                                        style: TextStyle(
                                          color: primaryBlack,
                                          fontWeight: FontWeight.w800,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            section.title,
                                            style: TextStyle(
                                              color: primaryBlack,
                                              fontWeight: FontWeight.w700,
                                              fontSize: 14,
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          Row(
                                            children: [
                                              _buildStatusBadge(
                                                section.status,
                                                isDark,
                                                borderColor,
                                                primaryBlack,
                                                tagBg,
                                              ),
                                              if (section.slots.isNotEmpty) ...[
                                                const SizedBox(width: 8),
                                                Text(
                                                  '${section.slots.where((s) => s.filled || section.documents.any((d) => d.slotKey == s.key)).length}/${section.slots.length} entregas',
                                                  style: TextStyle(
                                                    color: mutedText,
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                    Icon(
                                      Icons.chevron_right_rounded,
                                      color: mutedText,
                                      size: 20,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                  ],
                ),
              ),
          },
        );
      },
    );
  }
}

class _ExpandableDescription extends StatefulWidget {
  const _ExpandableDescription({
    required this.text,
    required this.style,
  });

  final String text;
  final TextStyle style;

  static const int _maxLines = 2;

  @override
  State<_ExpandableDescription> createState() => _ExpandableDescriptionState();
}

class _ExpandableDescriptionState extends State<_ExpandableDescription> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final textSpan = TextSpan(text: widget.text, style: widget.style);
        final textPainter = TextPainter(
          text: textSpan,
          maxLines: _ExpandableDescription._maxLines,
          textDirection: Directionality.of(context),
        )..layout(maxWidth: constraints.maxWidth);

        final exceeds = textPainter.didExceedMaxLines || widget.text.length > 70;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
              alignment: Alignment.topLeft,
              child: Text(
                widget.text,
                maxLines: _expanded ? null : _ExpandableDescription._maxLines,
                overflow: _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
                style: widget.style,
              ),
            ),
            if (exceeds) ...[
              const SizedBox(height: 4),
              InkWell(
                onTap: () => setState(() => _expanded = !_expanded),
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _expanded ? 'Ver menos' : 'Ver más',
                        style: TextStyle(
                          color: scheme.primary,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(width: 2),
                      Icon(
                        _expanded
                            ? Icons.keyboard_arrow_up
                            : Icons.keyboard_arrow_down,
                        size: 16,
                        color: scheme.primary,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

