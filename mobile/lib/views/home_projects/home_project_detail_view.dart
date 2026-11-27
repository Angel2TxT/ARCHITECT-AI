import 'package:flutter/material.dart';
import 'package:movil_architect/controllers/home_project_controller.dart';
import 'package:movil_architect/core/theme/architect_theme_tokens.dart';
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

  ButtonStyle _dialogCancelStyle(BuildContext context) {
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

  ButtonStyle _dialogDangerStyle(BuildContext context) {
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

  ButtonStyle _dialogPrimaryStyle(BuildContext context) {
    final tokens = ArchitectThemeTokens.of(context);
    return FilledButton.styleFrom(
      foregroundColor: tokens.primaryActionFg,
      backgroundColor: tokens.primaryActionBg,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      minimumSize: const Size(0, 42),
    );
  }

  Future<void> _promptRename(HomeProject project) async {
    final textController = TextEditingController(text: project.name);
    final formKey = GlobalKey<FormState>();
    final tokens = ArchitectThemeTokens.of(context);
    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Editar nombre del proyecto'),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: textController,
            autofocus: true,
            maxLength: 160,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            decoration: const InputDecoration(
              labelText: 'Nombre del proyecto',
              hintText: 'Ingresa el nuevo nombre',
            ),
            validator: (value) {
              final trimmed = (value ?? '').trim();
              if (trimmed.isEmpty) {
                return 'Ingresa el nombre del proyecto';
              }
              if (trimmed.length < 2) {
                return 'Debe tener al menos 2 caracteres';
              }
              return null;
            },
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            style: _dialogCancelStyle(context),
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
              if (formKey.currentState?.validate() == true) {
                Navigator.pop(context, textController.text.trim());
              }
            },
            style: _dialogPrimaryStyle(context),
            child: Text(
              'Guardar',
              style: ArchitectThemeTokens.appleText(
                color: tokens.primaryActionFg,
                fontSize: 14.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );

    if (newName == null ||
        newName.isEmpty ||
        newName == project.name ||
        !mounted) {
      return;
    }

    final ok = await _controller.renameProject(newName);
    if (!mounted) return;
    if (ok) {
      AppNotifications.success(context, 'Nombre del proyecto actualizado');
    } else {
      AppNotifications.error(
        context,
        _controller.actionError ?? 'No se pudo actualizar el nombre',
      );
    }
  }

  Future<void> _advance() async {
    final tokens = ArchitectThemeTokens.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Avanzar etapa'),
        content: const Text(
          '¿Confirmas avanzar a la siguiente etapa del proyecto?',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context, false),
            style: _dialogCancelStyle(context),
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
            onPressed: () => Navigator.pop(context, true),
            style: _dialogPrimaryStyle(context),
            child: Text(
              'Avanzar',
              style: ArchitectThemeTokens.appleText(
                color: tokens.primaryActionFg,
                fontSize: 14.5,
                fontWeight: FontWeight.w500,
              ),
            ),
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
          FilledButton(
            onPressed: () => Navigator.pop(context, false),
            style: _dialogCancelStyle(context),
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
            onPressed: () => Navigator.pop(context, true),
            style: _dialogDangerStyle(context),
            child: Text(
              'Eliminar',
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

  Future<void> _confirmLeave(HomeProject project) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Darse de baja'),
        content: Text(
          '¿Seguro que deseas salir de "${project.name}"? Ya no tendrás acceso a sus etapas ni documentos.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context, false),
            style: _dialogCancelStyle(context),
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
            onPressed: () => Navigator.pop(context, true),
            style: _dialogDangerStyle(context),
            child: Text(
              'Darse de baja',
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
    if (confirmed != true || !mounted) return;
    final ok = await _controller.leaveProject();
    if (!mounted) return;
    if (ok) {
      AppNotifications.success(context, 'Te diste de baja del proyecto');
      Navigator.of(context).pop(true);
      return;
    }
    AppNotifications.error(
      context,
      _controller.actionError ?? 'No se pudo dar de baja',
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

  Future<void> _showStagePickerSheet(HomeProject project, int selected) async {
    final tokens = ArchitectThemeTokens.of(context);
    final chosen = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: tokens.surfaceSecondary,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.72,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: tokens.borderStrong,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Etapas del proyecto',
                          style: ArchitectThemeTokens.appleDisplay(
                            color: tokens.textPrimary,
                            fontSize: 18,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Cerrar',
                        constraints: const BoxConstraints(
                          minWidth: 44,
                          minHeight: 44,
                        ),
                        onPressed: () => Navigator.of(sheetContext).pop(),
                        icon: Icon(
                          Icons.close_rounded,
                          size: 20,
                          color: tokens.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, thickness: 1, color: tokens.borderSubtle),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                    itemCount: project.stages.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 6),
                    itemBuilder: (context, index) {
                      final stage = project.stages[index];
                      final isSelected = stage.stageNumber == selected;
                      final isCurrent =
                          stage.stageNumber == project.currentStage;
                      final isDone = stage.status == 'completed';

                      final Color accentColor = isDone
                          ? tokens.statusPositive
                          : (isCurrent ? tokens.accent : tokens.textSecondary);

                      return Semantics(
                        button: true,
                        selected: isSelected,
                        label:
                            'Etapa ${stage.stageNumber}: ${stage.title}, ${homeProjectStatusLabel(stage.status)}',
                        child: Material(
                          color: isSelected
                              ? tokens.surfaceSelected
                              : Colors.transparent,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              ArchitectThemeTokens.radiusMd,
                            ),
                            side: isSelected
                                ? BorderSide(
                                    color: isCurrent
                                        ? tokens.accent
                                        : tokens.borderStrong,
                                    width: 1,
                                  )
                                : BorderSide.none,
                          ),
                          child: InkWell(
                            onTap: () => Navigator.of(
                              sheetContext,
                            ).pop(stage.stageNumber),
                            borderRadius: BorderRadius.circular(
                              ArchitectThemeTokens.radiusMd,
                            ),
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(minHeight: 52),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                child: Row(
                                  children: [
                                    SizedBox(
                                      width: 26,
                                      child: Text(
                                        stage.stageNumber.toString().padLeft(
                                          2,
                                          '0',
                                        ),
                                        style: ArchitectThemeTokens.appleText(
                                          color: accentColor,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w500,
                                          fontFeatures: const [
                                            FontFeature.tabularFigures(),
                                          ],
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            stage.title,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style:
                                                ArchitectThemeTokens.appleText(
                                                  color: tokens.textPrimary,
                                                  fontSize: 15,
                                                  fontWeight: isSelected
                                                      ? FontWeight.w600
                                                      : FontWeight.w500,
                                                ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            isCurrent
                                                ? 'Etapa actual'
                                                : homeProjectStatusLabel(
                                                    stage.status,
                                                  ),
                                            style:
                                                ArchitectThemeTokens.appleText(
                                                  color: accentColor,
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (isDone)
                                      Icon(
                                        Icons.check_circle_rounded,
                                        size: 18,
                                        color: tokens.statusPositive,
                                      )
                                    else if (isSelected)
                                      Icon(
                                        Icons.check_rounded,
                                        size: 18,
                                        color: isCurrent
                                            ? tokens.accent
                                            : tokens.textPrimary,
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (chosen != null && mounted) {
      setState(() => _selectedStage = chosen);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = ArchitectThemeTokens.of(context);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final project = _controller.project;
        final selected = _selectedStage ?? project?.currentStage ?? 1;
        final selectedStage = project?.stageByNumber(selected);

        return Scaffold(
          backgroundColor: tokens.drawerBackground,
          appBar: AppBar(
            backgroundColor: tokens.drawerBackground,
            foregroundColor: tokens.textPrimary,
            elevation: 0,
            scrolledUnderElevation: 0,
            centerTitle: true,
            title: Semantics(
              header: true,
              child: Text(
                project?.name ?? 'Proyecto',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: ArchitectThemeTokens.appleDisplay(
                  color: tokens.textPrimary,
                  fontSize: 19,
                  fontWeight: FontWeight.w500,
                  letterSpacing: -0.3,
                ),
              ),
            ),
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
            actions: [
              if (project != null && project.permissions.canRenameProject)
                Semantics(
                  button: true,
                  label: 'Editar nombre del proyecto',
                  child: IconButton(
                    tooltip: 'Editar nombre',
                    constraints: const BoxConstraints(
                      minWidth: 44,
                      minHeight: 44,
                    ),
                    onPressed: _controller.busy
                        ? null
                        : () => _promptRename(project),
                    icon: Icon(
                      Icons.edit_outlined,
                      size: 21,
                      color: tokens.textPrimary,
                    ),
                  ),
                ),
              Semantics(
                button: true,
                label: 'Gestionar equipo',
                child: IconButton(
                  tooltip: 'Equipo',
                  constraints: const BoxConstraints(
                    minWidth: 44,
                    minHeight: 44,
                  ),
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
                  icon: Icon(
                    Icons.groups_outlined,
                    size: 22,
                    color: tokens.textPrimary,
                  ),
                ),
              ),
              if (project?.permissions.canDeleteProject == true)
                Semantics(
                  button: true,
                  label: 'Eliminar proyecto',
                  child: IconButton(
                    tooltip: 'Eliminar',
                    constraints: const BoxConstraints(
                      minWidth: 44,
                      minHeight: 44,
                    ),
                    onPressed: _controller.busy ? null : _delete,
                    icon: Icon(
                      Icons.delete_outline_rounded,
                      size: 21,
                      color: tokens.statusError,
                    ),
                  ),
                ),
              if (project != null &&
                  project.myRole != 'owner' &&
                  !project.permissions.canDeleteProject)
                Semantics(
                  button: true,
                  label: 'Darse de baja del proyecto',
                  child: IconButton(
                    tooltip: 'Darse de baja',
                    constraints: const BoxConstraints(
                      minWidth: 44,
                      minHeight: 44,
                    ),
                    onPressed: _controller.busy
                        ? null
                        : () => _confirmLeave(project),
                    icon: Icon(
                      Icons.exit_to_app_rounded,
                      size: 21,
                      color: tokens.statusError,
                    ),
                  ),
                ),
              const SizedBox(width: 4),
            ],
          ),
          body: SafeArea(
            top: false,
            child: switch (_controller.state) {
              HomeProjectsState.loading => const HomeProjectDetailSkeleton(),
              HomeProjectsState.error => AppErrorView(
                message: _controller.errorMessage ?? 'Error',
                onRetry: () => _controller.load(),
              ),
              _ when project == null => const HomeProjectDetailSkeleton(),
              _ => RefreshIndicator(
                color: tokens.accent,
                onRefresh: () => _controller.load(refresh: true),
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 36),
                  children: [
                    // 1. HERO CARD: Información general y progreso
                    _ProjectOverviewCard(
                      project: project,
                      busy: _controller.busy,
                      reduceMotion: reduceMotion,
                      onAdvance: _advance,
                    ),

                    // 2. SECCIÓN ETAPAS
                    const SizedBox(height: 28),
                    Row(
                      children: [
                        Expanded(
                          child: _DetailSectionHeader(
                            title: 'Etapas',
                            trailing: '${project.stages.length}',
                          ),
                        ),
                        Semantics(
                          button: true,
                          label:
                              'Cambiar etapa, actualmente viendo etapa $selected de ${project.stages.length}',
                          child: Material(
                            color: tokens.surfaceSecondary,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                ArchitectThemeTokens.radiusMd,
                              ),
                              side: BorderSide(
                                color: tokens.borderSubtle,
                                width: 1,
                              ),
                            ),
                            child: InkWell(
                              onTap: () =>
                                  _showStagePickerSheet(project, selected),
                              borderRadius: BorderRadius.circular(
                                ArchitectThemeTokens.radiusMd,
                              ),
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  minHeight: 40,
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.layers_outlined,
                                        size: 16,
                                        color: selected == project.currentStage
                                            ? tokens.accent
                                            : tokens.textPrimary,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        'Etapa $selected/${project.stages.length}',
                                        style: ArchitectThemeTokens.appleText(
                                          color: tokens.textPrimary,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w500,
                                          fontFeatures: const [
                                            FontFeature.tabularFigures(),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      Icon(
                                        Icons.unfold_more_rounded,
                                        size: 16,
                                        color: tokens.textSecondary,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (selectedStage != null)
                      AnimatedSwitcher(
                        duration: reduceMotion
                            ? Duration.zero
                            : const Duration(milliseconds: 180),
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeInCubic,
                        child: _SelectedStageCard(
                          key: ValueKey(selectedStage.stageNumber),
                          stage: selectedStage,
                          isCurrent:
                              selectedStage.stageNumber == project.currentStage,
                          onTap: () => _openStage(selectedStage),
                        ),
                      ),

                    // 3. SECCIÓN APARTADOS Y ENTREGABLES
                    const SizedBox(height: 28),
                    Row(
                      children: [
                        Expanded(
                          child: _DetailSectionHeader(
                            title: 'Apartados',
                            trailing: selectedStage == null
                                ? null
                                : '${selectedStage.sectionsProgress.done}/${selectedStage.sectionsProgress.total}${selectedStage.planReview ? ' · Planos' : ''}',
                          ),
                        ),
                        if (selectedStage != null &&
                            project.permissions.canCreateSection)
                          NewSectionButton(
                            enabled: !_controller.busy,
                            onTap: () => showCreateSectionDialog(
                              context: context,
                              controller: _controller,
                              stageNumber: selectedStage.stageNumber,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (selectedStage == null || selectedStage.sections.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(24),
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
                        child: Center(
                          child: Text(
                            'Esta etapa no tiene apartados.',
                            style: ArchitectThemeTokens.appleText(
                              color: tokens.textSecondary,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      )
                    else
                      for (final (index, section)
                          in selectedStage.sections.indexed) ...[
                        _SectionDeliverableCard(
                          index: index + 1,
                          section: section,
                          onTap: () => _openSection(selectedStage, section),
                        ),
                        const SizedBox(height: 10),
                      ],
                  ],
                ),
              ),
            },
          ),
        );
      },
    );
  }
}

class _DetailSectionHeader extends StatelessWidget {
  const _DetailSectionHeader({required this.title, this.trailing});

  final String title;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final tokens = ArchitectThemeTokens.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          title,
          style: ArchitectThemeTokens.appleDisplay(
            color: tokens.textPrimary,
            fontSize: 19,
            fontWeight: FontWeight.w500,
            letterSpacing: -0.25,
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 8),
          Text(
            trailing!,
            style: ArchitectThemeTokens.appleText(
              color: tokens.textSecondary,
              fontSize: 14,
              fontWeight: FontWeight.w500,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ],
    );
  }
}

class _ProjectOverviewCard extends StatelessWidget {
  const _ProjectOverviewCard({
    required this.project,
    required this.busy,
    required this.reduceMotion,
    required this.onAdvance,
  });

  final HomeProject project;
  final bool busy;
  final bool reduceMotion;
  final VoidCallback onAdvance;

  @override
  Widget build(BuildContext context) {
    final tokens = ArchitectThemeTokens.of(context);
    final progress = (project.progressPercent / 100).clamp(0.0, 1.0);
    final progressInt = project.progressPercent.round();
    final isComplete = progressInt >= 100;

    final canAdvance =
        project.permissions.canAdvanceStage && project.currentStage < 9;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: tokens.surfaceSecondary,
        borderRadius: BorderRadius.circular(ArchitectThemeTokens.radiusLg),
        border: Border.all(color: tokens.borderSubtle, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (project.myRole != 'owner') ...[
            Row(
              children: [
                Icon(
                  Icons.shield_outlined,
                  size: 14,
                  color: tokens.textSecondary,
                ),
                const SizedBox(width: 6),
                Text(
                  'Colaborador',
                  style: ArchitectThemeTokens.appleText(
                    color: tokens.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          if (project.clientName.isNotEmpty || project.location.isNotEmpty)
            Wrap(
              spacing: 16,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (project.clientName.isNotEmpty)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.person_outline_rounded,
                        size: 16,
                        color: tokens.textSecondary,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          project.clientName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: ArchitectThemeTokens.appleText(
                            color: tokens.textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                if (project.location.isNotEmpty)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.location_on_outlined,
                        size: 16,
                        color: tokens.textSecondary,
                      ),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          project.location,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: ArchitectThemeTokens.appleText(
                            color: tokens.textSecondary,
                            fontSize: 14,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          if (project.description.isNotEmpty) ...[
            const SizedBox(height: 12),
            _ExpandableDescription(
              text: project.description,
              style: ArchitectThemeTokens.appleText(
                color: tokens.textSecondary,
                fontSize: 14,
                fontWeight: FontWeight.w400,
                height: 1.45,
              ),
            ),
          ],
          const SizedBox(height: 18),

          // Etapa actual + Avanzar etapa en la misma fila
          if (canAdvance)
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Etapa actual',
                        style: ArchitectThemeTokens.appleText(
                          color: tokens.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${project.currentStage}/9',
                        style:
                            ArchitectThemeTokens.appleDisplay(
                              color: tokens.textPrimary,
                              fontSize: 24,
                              fontWeight: FontWeight.w500,
                              letterSpacing: -0.4,
                            ).copyWith(
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                _AdvanceStageButton(
                  busy: busy,
                  reduceMotion: reduceMotion,
                  onPressed: onAdvance,
                ),
              ],
            )
          else
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  'Etapa actual',
                  style: ArchitectThemeTokens.appleText(
                    color: tokens.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  '${project.currentStage}/9',
                  style:
                      ArchitectThemeTokens.appleDisplay(
                        color: tokens.textPrimary,
                        fontSize: 22,
                        fontWeight: FontWeight.w500,
                        letterSpacing: -0.3,
                      ).copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                ),
              ],
            ),
          const SizedBox(height: 12),
          Semantics(
            label: 'Progreso del proyecto: $progressInt por ciento',
            value: '$progressInt%',
            child: ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 4,
                backgroundColor: tokens.borderSubtle,
                valueColor: AlwaysStoppedAnimation<Color>(
                  isComplete ? tokens.statusPositive : tokens.accent,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AdvanceStageButton extends StatefulWidget {
  const _AdvanceStageButton({
    required this.busy,
    required this.reduceMotion,
    required this.onPressed,
  });

  final bool busy;
  final bool reduceMotion;
  final VoidCallback onPressed;

  @override
  State<_AdvanceStageButton> createState() => _AdvanceStageButtonState();
}

class _AdvanceStageButtonState extends State<_AdvanceStageButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final tokens = ArchitectThemeTokens.of(context);
    final disabled = widget.busy;

    return Semantics(
      button: true,
      enabled: !disabled,
      label: 'Avanzar a la siguiente etapa',
      child: AnimatedScale(
        scale: (_pressed && !disabled && !widget.reduceMotion) ? 0.98 : 1.0,
        duration: widget.reduceMotion
            ? Duration.zero
            : const Duration(milliseconds: 110),
        curve: Curves.easeOutCubic,
        child: Material(
          color: disabled
              ? tokens.primaryActionBg.withValues(alpha: 0.45)
              : tokens.primaryActionBg,
          borderRadius: BorderRadius.circular(ArchitectThemeTokens.radiusMd),
          child: InkWell(
            onTap: disabled ? null : widget.onPressed,
            onHighlightChanged: (value) {
              if (mounted) setState(() => _pressed = value);
            },
            borderRadius: BorderRadius.circular(ArchitectThemeTokens.radiusMd),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (widget.busy)
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            tokens.primaryActionFg,
                          ),
                        ),
                      )
                    else
                      Icon(
                        Icons.arrow_forward_rounded,
                        size: 18,
                        color: tokens.primaryActionFg,
                      ),
                    const SizedBox(width: 8),
                    Text(
                      widget.busy ? 'Avanzando...' : 'Avanzar etapa',
                      style: ArchitectThemeTokens.appleText(
                        color: tokens.primaryActionFg,
                        fontSize: 15,
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

class _SelectedStageCard extends StatelessWidget {
  const _SelectedStageCard({
    super.key,
    required this.stage,
    required this.isCurrent,
    required this.onTap,
  });

  final HomeProjectStage stage;
  final bool isCurrent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = ArchitectThemeTokens.of(context);
    final isDone = stage.status == 'completed';

    return Semantics(
      button: true,
      label: 'Etapa ${stage.stageNumber}: ${stage.title}. Ver detalle',
      child: Material(
        color: tokens.surfaceSecondary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ArchitectThemeTokens.radiusLg),
          side: BorderSide(color: tokens.borderSubtle, width: 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          hoverColor: tokens.interactionOverlay,
          splashColor: tokens.interactionOverlay,
          borderRadius: BorderRadius.circular(ArchitectThemeTokens.radiusLg),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (isCurrent || isDone)
                      Container(
                        width: 2.5,
                        height: 20,
                        margin: const EdgeInsets.only(top: 2, right: 10),
                        decoration: BoxDecoration(
                          color: isDone ? tokens.statusPositive : tokens.accent,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${stage.stageNumber}. ${stage.title}',
                            style: ArchitectThemeTokens.appleText(
                              color: tokens.textPrimary,
                              fontSize: 17,
                              fontWeight: FontWeight.w500,
                              height: 1.25,
                            ),
                          ),
                          if (stage.summary.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(
                              stage.summary,
                              style: ArchitectThemeTokens.appleText(
                                color: tokens.textSecondary,
                                fontSize: 14,
                                fontWeight: FontWeight.w400,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    _CompactStatusLabel(status: stage.status),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Ver detalle de la etapa',
                      style: ArchitectThemeTokens.appleText(
                        color: isCurrent ? tokens.accent : tokens.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Icon(
                      Icons.arrow_forward_rounded,
                      size: 16,
                      color: isCurrent ? tokens.accent : tokens.textPrimary,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CompactStatusLabel extends StatelessWidget {
  const _CompactStatusLabel({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final tokens = ArchitectThemeTokens.of(context);
    final label = homeProjectStatusLabel(status);
    final isDone = status == 'completed';
    final isInProgress = status == 'active' || status == 'in_progress';
    final isWarning = status == 'paused' || status == 'pending';

    final Color color = isDone
        ? tokens.statusPositive
        : (isInProgress
              ? tokens.accent
              : (isWarning ? tokens.statusWarning : tokens.textSecondary));

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(ArchitectThemeTokens.radiusSm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isDone)
            Icon(Icons.check_rounded, size: 12, color: color)
          else
            Container(
              width: 5.5,
              height: 5.5,
              decoration: BoxDecoration(shape: BoxShape.circle, color: color),
            ),
          const SizedBox(width: 5),
          Text(
            label,
            style: ArchitectThemeTokens.appleText(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionDeliverableCard extends StatelessWidget {
  const _SectionDeliverableCard({
    required this.index,
    required this.section,
    required this.onTap,
  });

  final int index;
  final HomeProjectSection section;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = ArchitectThemeTokens.of(context);
    final textScale = MediaQuery.textScalerOf(context).scale(1.0);
    final filledCount = section.slots
        .where(
          (s) => s.filled || section.documents.any((d) => d.slotKey == s.key),
        )
        .length;
    final totalCount = section.slots.length;
    final isDone = section.status == 'completed';
    final isInProgress =
        section.status == 'active' || section.status == 'in_progress';
    final statusColor = isDone
        ? tokens.statusPositive
        : (isInProgress ? tokens.accent : tokens.textSecondary);

    return Semantics(
      button: true,
      label:
          'Apartado $index: ${section.title}, ${homeProjectStatusLabel(section.status)}${totalCount > 0 ? ', $filledCount de $totalCount entregas' : ''}',
      child: Material(
        color: tokens.surfaceSecondary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ArchitectThemeTokens.radiusLg),
          side: BorderSide(color: tokens.borderSubtle, width: 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          hoverColor: tokens.interactionOverlay,
          splashColor: tokens.interactionOverlay,
          borderRadius: BorderRadius.circular(ArchitectThemeTokens.radiusLg),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 62),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 24,
                    child: Text(
                      index.toString().padLeft(2, '0'),
                      style: ArchitectThemeTokens.appleText(
                        color: isDone
                            ? tokens.statusPositive
                            : tokens.textSecondary,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          section.title,
                          maxLines: textScale > 1.3 ? 3 : 2,
                          overflow: TextOverflow.ellipsis,
                          style: ArchitectThemeTokens.appleText(
                            color: tokens.textPrimary,
                            fontSize: 15.5,
                            fontWeight: FontWeight.w500,
                            height: 1.25,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (isDone)
                                  Icon(
                                    Icons.check_rounded,
                                    size: 13,
                                    color: statusColor,
                                  )
                                else
                                  Container(
                                    width: 5.5,
                                    height: 5.5,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: statusColor,
                                    ),
                                  ),
                                const SizedBox(width: 5),
                                Text(
                                  homeProjectStatusLabel(section.status),
                                  style: ArchitectThemeTokens.appleText(
                                    color: statusColor,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                            if (totalCount > 0)
                              Text(
                                '$filledCount/$totalCount entregas',
                                style: ArchitectThemeTokens.appleText(
                                  color: tokens.textSecondary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w400,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: tokens.textSecondary,
                    size: 19,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ExpandableDescription extends StatefulWidget {
  const _ExpandableDescription({required this.text, required this.style});

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
    final tokens = ArchitectThemeTokens.of(context);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final textSpan = TextSpan(text: widget.text, style: widget.style);
        final textPainter = TextPainter(
          text: textSpan,
          maxLines: _ExpandableDescription._maxLines,
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout(maxWidth: constraints.maxWidth);

        final exceeds =
            textPainter.didExceedMaxLines || widget.text.length > 70;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedSize(
              duration: reduceMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
              alignment: Alignment.topLeft,
              child: Text(
                widget.text,
                maxLines: _expanded ? null : _ExpandableDescription._maxLines,
                overflow: _expanded
                    ? TextOverflow.visible
                    : TextOverflow.ellipsis,
                style: widget.style,
              ),
            ),
            if (exceeds) ...[
              const SizedBox(height: 6),
              InkWell(
                onTap: () => setState(() => _expanded = !_expanded),
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 4,
                    horizontal: 2,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _expanded ? 'Ver menos' : 'Ver más',
                        style: ArchitectThemeTokens.appleText(
                          color: tokens.accent,
                          fontWeight: FontWeight.w500,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(width: 2),
                      Icon(
                        _expanded
                            ? Icons.keyboard_arrow_up_rounded
                            : Icons.keyboard_arrow_down_rounded,
                        size: 16,
                        color: tokens.accent,
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
