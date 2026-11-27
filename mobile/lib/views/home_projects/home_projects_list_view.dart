import 'package:flutter/material.dart';
import 'package:movil_architect/controllers/home_project_controller.dart';
import 'package:movil_architect/core/theme/architect_theme_tokens.dart';
import 'package:movil_architect/core/utils/app_notifications.dart';
import 'package:movil_architect/models/home_project_models.dart';
import 'package:movil_architect/views/home_projects/create_home_project_view.dart';
import 'package:movil_architect/views/home_projects/home_project_detail_view.dart';
import 'package:movil_architect/views/home_projects/home_project_team_view.dart';
import 'package:movil_architect/views/home_projects/widgets/home_project_widgets.dart';
import 'package:movil_architect/views/shared/app_states.dart';
import 'package:movil_architect/views/shared/skeleton.dart';

class HomeProjectsListView extends StatefulWidget {
  const HomeProjectsListView({super.key});

  @override
  State<HomeProjectsListView> createState() => _HomeProjectsListViewState();
}

class _HomeProjectsListViewState extends State<HomeProjectsListView> {
  late final HomeProjectsController _controller;
  late final TextEditingController _searchController;
  String _searchQuery = '';
  bool _isSearching = false;
  bool _sortAscending = true;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _controller = HomeProjectsController();
    _controller.load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _startSearch() {
    setState(() {
      _isSearching = true;
    });
  }

  void _stopSearch() {
    setState(() {
      _isSearching = false;
      _searchQuery = '';
      _searchController.clear();
    });
  }

  void _toggleSort() {
    setState(() {
      _sortAscending = !_sortAscending;
    });
    AppNotifications.info(
      context,
      _sortAscending ? 'Ordenado de A a Z' : 'Ordenado de Z a A',
    );
  }

  List<HomeProject> _getFilteredProjects() {
    final query = _searchQuery.trim().toLowerCase();
    var list = _controller.projects;

    if (query.isNotEmpty) {
      list = list.where((p) {
        final name = p.name.toLowerCase();
        final loc = p.location.toLowerCase();
        final client = p.clientName.toLowerCase();
        final desc = p.description.toLowerCase();
        final stage = 'etapa ${p.currentStage}';
        return name.contains(query) ||
            loc.contains(query) ||
            client.contains(query) ||
            desc.contains(query) ||
            stage.contains(query);
      }).toList();
    }

    final sorted = List<HomeProject>.from(list);
    sorted.sort((a, b) {
      final comp =
          a.name.trim().toLowerCase().compareTo(b.name.trim().toLowerCase());
      return _sortAscending ? comp : -comp;
    });
    return sorted;
  }

  Future<void> _openCreate() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const CreateHomeProjectView()));
    if (mounted) await _controller.load(refresh: true);
  }

  Future<void> _openDetail(String projectId) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => HomeProjectDetailView(projectId: projectId),
      ),
    );
    if (mounted) await _controller.load(refresh: true);
  }

  Future<void> _togglePin(
    HomeProject project, {
    required bool wasPinned,
  }) async {
    await _controller.togglePin(project.id);
    if (!mounted) return;
    AppNotifications.success(
      context,
      wasPinned ? 'Proyecto desfijado' : 'Proyecto fijado',
    );
  }

  Future<void> _confirmDelete(HomeProject project) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cancelBg =
        isDark ? const Color(0xFF3E3E44) : const Color(0xFF6B6B73);
    final dangerBg =
        isDark ? const Color(0xFFD9383A) : const Color(0xFFC8282A);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar proyecto'),
        content: Text(
          'Se eliminará "${project.name}". Esta acción no se puede deshacer.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context, false),
            style: FilledButton.styleFrom(
              foregroundColor: Colors.white,
              backgroundColor: cancelBg,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              minimumSize: const Size(0, 42),
            ),
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
            style: FilledButton.styleFrom(
              foregroundColor: Colors.white,
              backgroundColor: dangerBg,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              minimumSize: const Size(0, 42),
            ),
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

    final ok = await _controller.deleteProject(project.id);
    if (!mounted) return;
    if (ok) {
      AppNotifications.success(context, 'Proyecto eliminado');
    } else {
      AppNotifications.error(
        context,
        _controller.errorMessage ?? 'No se pudo eliminar',
      );
    }
  }

  Future<void> _confirmLeave(HomeProject project) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cancelBg =
        isDark ? const Color(0xFF3E3E44) : const Color(0xFF6B6B73);
    final dangerBg =
        isDark ? const Color(0xFFD9383A) : const Color(0xFFC8282A);
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
            style: FilledButton.styleFrom(
              foregroundColor: Colors.white,
              backgroundColor: cancelBg,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              minimumSize: const Size(0, 42),
            ),
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
            style: FilledButton.styleFrom(
              foregroundColor: Colors.white,
              backgroundColor: dangerBg,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              minimumSize: const Size(0, 42),
            ),
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

    final ok = await _controller.leaveProject(project.id);
    if (!mounted) return;
    if (ok) {
      AppNotifications.success(context, 'Te diste de baja del proyecto');
    } else {
      AppNotifications.error(
        context,
        _controller.errorMessage ?? 'No se pudo dar de baja',
      );
    }
  }

  Future<void> _promptRename(HomeProject project) async {
    final textController = TextEditingController(text: project.name);
    final formKey = GlobalKey<FormState>();
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
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() == true) {
                Navigator.pop(context, textController.text.trim());
              }
            },
            child: const Text('Guardar'),
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

    final ok = await _controller.renameProject(project.id, newName);
    if (!mounted) return;
    if (ok) {
      AppNotifications.success(context, 'Nombre actualizado');
    } else {
      AppNotifications.error(
        context,
        _controller.errorMessage ?? 'No se pudo actualizar el nombre',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = ArchitectThemeTokens.of(context);

    return PopScope(
      canPop: !_isSearching,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_isSearching) {
          _stopSearch();
        }
      },
      child: Scaffold(
        backgroundColor: tokens.drawerBackground,
        appBar: AppBar(
          backgroundColor: tokens.drawerBackground,
          foregroundColor: tokens.textPrimary,
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: true,
          leading: Semantics(
            button: true,
            label: _isSearching ? 'Cerrar búsqueda' : 'Regresar',
            child: IconButton(
              icon: Icon(
                Icons.arrow_back_rounded,
                size: 22,
                color: tokens.textPrimary,
              ),
              tooltip: _isSearching ? 'Cerrar búsqueda' : 'Regresar',
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
              onPressed: _isSearching
                  ? _stopSearch
                  : () => Navigator.of(context).maybePop(),
            ),
          ),
          title: _isSearching
              ? TextField(
                  controller: _searchController,
                  autofocus: true,
                  textInputAction: TextInputAction.search,
                  style: ArchitectThemeTokens.appleText(
                    color: tokens.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w400,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Buscar proyectos...',
                    hintStyle: ArchitectThemeTokens.appleText(
                      color: tokens.textSecondary,
                      fontSize: 16,
                    ),
                    border: InputBorder.none,
                  ),
                  onChanged: (value) {
                    setState(() {
                      _searchQuery = value;
                    });
                  },
                )
              : Semantics(
                  header: true,
                  child: Text(
                    'Casa hogar',
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
          actions: [
            if (_isSearching) ...[
              if (_searchQuery.isNotEmpty)
                IconButton(
                  tooltip: 'Limpiar búsqueda',
                  constraints: const BoxConstraints(
                    minWidth: 44,
                    minHeight: 44,
                  ),
                  icon: Icon(
                    Icons.close_rounded,
                    size: 20,
                    color: tokens.textPrimary,
                  ),
                  onPressed: () {
                    _searchController.clear();
                    setState(() {
                      _searchQuery = '';
                    });
                  },
                ),
            ] else ...[
              Semantics(
                button: true,
                label: 'Buscar proyectos',
                child: IconButton(
                  tooltip: 'Buscar proyectos',
                  constraints: const BoxConstraints(
                    minWidth: 44,
                    minHeight: 44,
                  ),
                  icon: Icon(
                    Icons.search_rounded,
                    size: 22,
                    color: tokens.textPrimary,
                  ),
                  onPressed: _startSearch,
                ),
              ),
              Semantics(
                button: true,
                label: _sortAscending ? 'Ordenar Z a A' : 'Ordenar A a Z',
                child: IconButton(
                  tooltip: _sortAscending
                      ? 'Orden A-Z (activo)'
                      : 'Orden Z-A (activo)',
                  constraints: const BoxConstraints(
                    minWidth: 44,
                    minHeight: 44,
                  ),
                  icon: Icon(
                    _sortAscending
                        ? Icons.sort_by_alpha_rounded
                        : Icons.sort_by_alpha_outlined,
                    size: 22,
                    color: tokens.textPrimary,
                  ),
                  onPressed: _toggleSort,
                ),
              ),
              Semantics(
                button: true,
                label: 'Aceptar invitación',
                child: IconButton(
                  tooltip: 'Aceptar invitación',
                  constraints: const BoxConstraints(
                    minWidth: 44,
                    minHeight: 44,
                  ),
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const AcceptInviteView(),
                      ),
                    );
                  },
                  icon: Icon(
                    Icons.mail_outline_rounded,
                    size: 21,
                    color: tokens.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 4),
            ],
          ],
        ),
        floatingActionButton: SafeArea(
          top: false,
          left: false,
          child: _NewProjectButton(onPressed: _openCreate),
        ),
        body: SafeArea(
          top: false,
          child: ListenableBuilder(
            listenable: _controller,
            builder: (context, _) {
              if (_controller.state == HomeProjectsState.loading) {
                return const HomeProjectsListSkeleton();
              }
              if (_controller.state == HomeProjectsState.error) {
                return AppErrorView(
                  message: _controller.errorMessage ?? 'Error al cargar',
                  onRetry: () => _controller.load(),
                );
              }
              if (_controller.state == HomeProjectsState.empty) {
                return RefreshIndicator(
                  color: tokens.accent,
                  onRefresh: () => _controller.load(refresh: true),
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 96),
                    children: [
                      SizedBox(height: MediaQuery.sizeOf(context).height * 0.2),
                      Icon(
                        Icons.home_work_outlined,
                        size: 48,
                        color: tokens.textSecondary,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Aún no hay proyectos',
                        textAlign: TextAlign.center,
                        style: ArchitectThemeTokens.appleDisplay(
                          color: tokens.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Crea tu primer proyecto de vivienda\nunifamiliar en 9 etapas.',
                        textAlign: TextAlign.center,
                        style: ArchitectThemeTokens.appleText(
                          color: tokens.textSecondary,
                          fontSize: 14,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
                );
              }

              final projects = _getFilteredProjects();

              if (projects.isEmpty && _searchQuery.isNotEmpty) {
                return RefreshIndicator(
                  color: tokens.accent,
                  onRefresh: () => _controller.load(refresh: true),
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 96),
                    children: [
                      SizedBox(height: MediaQuery.sizeOf(context).height * 0.18),
                      Icon(
                        Icons.search_off_rounded,
                        size: 48,
                        color: tokens.textSecondary,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Sin coincidencias',
                        textAlign: TextAlign.center,
                        style: ArchitectThemeTokens.appleDisplay(
                          color: tokens.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          'No encontramos ningún proyecto que coincida con "$_searchQuery".',
                          textAlign: TextAlign.center,
                          style: ArchitectThemeTokens.appleText(
                            color: tokens.textSecondary,
                            fontSize: 14,
                            height: 1.45,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Center(
                        child: TextButton.icon(
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                          icon: Icon(
                            Icons.close_rounded,
                            size: 18,
                            color: tokens.textPrimary,
                          ),
                          label: Text(
                            'Limpiar búsqueda',
                            style: ArchitectThemeTokens.appleText(
                              color: tokens.textPrimary,
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }

              return RefreshIndicator(
                color: tokens.accent,
                onRefresh: () => _controller.load(refresh: true),
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 104),
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          _searchQuery.isNotEmpty
                              ? 'Resultados'
                              : 'Proyectos activos',
                          style: ArchitectThemeTokens.appleDisplay(
                            color: tokens.textPrimary,
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.25,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${projects.length}',
                          style: ArchitectThemeTokens.appleText(
                            color: tokens.textSecondary,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    for (final project in projects) ...[
                      HomeProjectCard(
                        project: project,
                        pinned: _controller.isPinned(project.id),
                        onTap: () => _openDetail(project.id),
                        onPin: () => _togglePin(
                          project,
                          wasPinned: _controller.isPinned(project.id),
                        ),
                        onRename: project.permissions.canRenameProject
                            ? () => _promptRename(project)
                            : null,
                        onDelete: project.permissions.canDeleteProject
                            ? () => _confirmDelete(project)
                            : null,
                        onLeave: (project.myRole != 'owner' &&
                                !project.permissions.canDeleteProject)
                            ? () => _confirmLeave(project)
                            : null,
                      ),
                      const SizedBox(height: 12),
                    ],
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _NewProjectButton extends StatefulWidget {
  const _NewProjectButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  State<_NewProjectButton> createState() => _NewProjectButtonState();
}

class _NewProjectButtonState extends State<_NewProjectButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final tokens = ArchitectThemeTokens.of(context);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    return Semantics(
      button: true,
      label: 'Crear nuevo proyecto',
      child: AnimatedScale(
        scale: (_pressed && !reduceMotion) ? 0.97 : 1.0,
        duration: reduceMotion
            ? Duration.zero
            : const Duration(milliseconds: 110),
        curve: Curves.easeOutCubic,
        child: Material(
          color: tokens.primaryActionBg,
          borderRadius: BorderRadius.circular(ArchitectThemeTokens.radiusMd),
          elevation: 0,
          child: InkWell(
            onTap: widget.onPressed,
            onHighlightChanged: (value) {
              if (mounted) setState(() => _pressed = value);
            },
            borderRadius: BorderRadius.circular(ArchitectThemeTokens.radiusMd),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 12,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.add_rounded,
                      size: 19,
                      color: tokens.primaryActionFg,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Nuevo proyecto',
                      style: ArchitectThemeTokens.appleText(
                        color: tokens.primaryActionFg,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        letterSpacing: -0.15,
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
