import 'package:flutter/material.dart';
import 'package:movil_architect/controllers/home_project_controller.dart';
import 'package:movil_architect/core/utils/app_notifications.dart';
import 'package:movil_architect/models/home_project_models.dart';
import 'package:movil_architect/views/home_projects/home_project_team_view.dart';
import 'package:movil_architect/views/home_projects/section_detail_view.dart';
import 'package:movil_architect/views/home_projects/stage_detail_view.dart';
import 'package:movil_architect/views/home_projects/widgets/home_project_widgets.dart';
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
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final project = _controller.project;
        final selected = _selectedStage ?? project?.currentStage ?? 1;
        final selectedStage = project?.stageByNumber(selected);

        return Scaffold(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          appBar: AppBar(
            title: Text(
              project?.name ?? 'Proyecto',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            backgroundColor: Theme.of(context).scaffoldBackgroundColor,
            elevation: 0,
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
                onRefresh: () => _controller.load(refresh: true),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                      children: [
                    Row(
                      children: [
                        HomeStatusChip(status: project.status),
                        const Spacer(),
                        Text(
                          'Rol: ${project.myRole}',
                          style: TextStyle(
                            color: scheme.onSurfaceVariant,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    if (project.clientName.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        project.clientName,
                        style: TextStyle(
                          color: scheme.onSurface,
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                    ],
                    if (project.location.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        project.location,
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                    ],
                    if (project.description.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      _ExpandableDescription(
                        text: project.description,
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          height: 1.4,
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    Text(
                      'Progreso ${project.progressPercent.round()}% · '
                      'Etapa ${project.currentStage}/9 · '
                      '${project.stagesCompleted} completadas',
                      style: TextStyle(
                        color: scheme.onSurface,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        value: (project.progressPercent / 100).clamp(0.0, 1.0),
                        minHeight: 8,
                        backgroundColor: scheme.surfaceContainerHighest,
                        color: scheme.onSurface,
                      ),
                    ),
                    if (project.permissions.canAdvanceStage) ...[
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: _controller.busy ? null : _advance,
                        icon: _controller.busy
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.arrow_forward),
                        label: const Text('Avanzar etapa'),
                      ),
                    ],
                    const SizedBox(height: 24),
                    Text(
                      'Etapas',
                      style: TextStyle(
                        color: scheme.onSurface,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 44,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: project.stages.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 8),
                        itemBuilder: (context, index) {
                          final stage = project.stages[index];
                          final isSelected = stage.stageNumber == selected;
                          final isCurrent =
                              stage.stageNumber == project.currentStage;
                          return ChoiceChip(
                            label: Text('${stage.stageNumber}'),
                            selected: isSelected,
                            onSelected: (_) => setState(
                              () => _selectedStage = stage.stageNumber,
                            ),
                            avatar: isCurrent
                                ? const Icon(Icons.flag, size: 16)
                                : null,
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
                    for (final stage in project.stages)
                      if (stage.stageNumber == selected) ...[
                        Material(
                          color: Theme.of(context).cardColor,
                          borderRadius: BorderRadius.circular(20),
                          child: InkWell(
                            onTap: () => _openStage(stage),
                            borderRadius: BorderRadius.circular(20),
                            child: Padding(
                              padding: const EdgeInsets.all(18),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          '${stage.stageNumber}. ${stage.title}',
                                          style: TextStyle(
                                            color: scheme.onSurface,
                                            fontSize: 17,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ),
                                      HomeStatusChip(status: stage.status),
                                    ],
                                  ),
                                  if (stage.summary.isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    Text(
                                      stage.summary,
                                      style: TextStyle(
                                        color: scheme.onSurfaceVariant,
                                        height: 1.35,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Apartados',
                            style: TextStyle(
                              color: scheme.onSurface,
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        if (selectedStage != null)
                          Text(
                            '${selectedStage.sectionsProgress.done}/'
                            '${selectedStage.sectionsProgress.total}'
                            '${selectedStage.planReview ? ' · Planos' : ''}',
                            style: TextStyle(
                              color: scheme.onSurface,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (selectedStage == null ||
                        selectedStage.sections.isEmpty)
                      Text(
                        'Esta etapa no tiene apartados.',
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      )
                    else
                      for (final (index, section)
                          in selectedStage.sections.indexed)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Material(
                            color: Theme.of(context).cardColor,
                            borderRadius: BorderRadius.circular(14),
                            child: InkWell(
                              onTap: () =>
                                  _openSection(selectedStage, section),
                              borderRadius: BorderRadius.circular(14),
                              child: Ink(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border(
                                    left: BorderSide(
                                      color: _apartadoColor(index),
                                      width: 4,
                                    ),
                                  ),
                                ),
                                child: ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: _apartadoColor(index)
                                        .withValues(alpha: 0.16),
                                    child: Text(
                                      '${index + 1}',
                                      style: TextStyle(
                                        color: _apartadoColor(index),
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                  title: Text(
                                    section.title,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  subtitle: Padding(
                                    padding: const EdgeInsets.only(top: 6),
                                    child: Align(
                                      alignment: Alignment.centerLeft,
                                      child: HomeStatusChip(
                                        status: section.status,
                                      ),
                                    ),
                                  ),
                                  trailing: const Icon(Icons.chevron_right),
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

Color _apartadoColor(int index) {
  const colors = [
    Color(0xFF1B4D8A),
    Color(0xFF1B8A5A),
    Color(0xFFB07A00),
    Color(0xFF6B3FA0),
    Color(0xFFC45C26),
    Color(0xFF0E7C7B),
    Color(0xFF8A1B4D),
  ];
  return colors[index % colors.length];
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

