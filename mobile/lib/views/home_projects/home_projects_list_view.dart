import 'package:flutter/material.dart';
import 'package:movil_architect/controllers/home_project_controller.dart';
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
      final comp = a.name.trim().toLowerCase().compareTo(b.name.trim().toLowerCase());
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar proyecto'),
        content: Text(
          'Se eliminará "${project.name}". Esta acción no se puede deshacer.',
        ),
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
              if (!RegExp(r'^[a-zA-ZáéíóúÁÉÍÓÚñÑüÜ\s]+$').hasMatch(trimmed)) {
                return 'Solo se admiten letras';
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

    if (newName == null || newName.isEmpty || newName == project.name || !mounted) return;

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
    final scheme = Theme.of(context).colorScheme;

    return PopScope(
      canPop: !_isSearching,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_isSearching) {
          _stopSearch();
        }
      },
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          elevation: 0,
          leading: _isSearching
              ? IconButton(
                  icon: Icon(Icons.arrow_back, color: scheme.onSurface),
                  tooltip: 'Cerrar búsqueda',
                  onPressed: _stopSearch,
                )
              : null,
          title: _isSearching
              ? TextField(
                  controller: _searchController,
                  autofocus: true,
                  style: TextStyle(
                    color: scheme.onSurface,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Buscar proyectos...',
                    hintStyle: TextStyle(
                      color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
                      fontSize: 15,
                    ),
                    border: InputBorder.none,
                  ),
                  onChanged: (value) {
                    setState(() {
                      _searchQuery = value;
                    });
                  },
                )
              : const Text(
                  'Casa hogar',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
          actions: [
            if (_isSearching) ...[
              if (_searchQuery.isNotEmpty)
                IconButton(
                  tooltip: 'Limpiar',
                  icon: Icon(Icons.close, color: scheme.onSurface),
                  onPressed: () {
                    _searchController.clear();
                    setState(() {
                      _searchQuery = '';
                    });
                  },
                ),
            ] else ...[
              IconButton(
                tooltip: 'Buscar proyectos',
                icon: Icon(Icons.search, color: scheme.onSurface),
                onPressed: _startSearch,
              ),
              IconButton(
                tooltip: _sortAscending ? 'Orden A-Z (activo)' : 'Orden Z-A (activo)',
                icon: Icon(
                  _sortAscending
                      ? Icons.sort_by_alpha
                      : Icons.sort_by_alpha_outlined,
                  color: scheme.onSurface,
                ),
                onPressed: _toggleSort,
              ),
              IconButton(
                tooltip: 'Aceptar invitación',
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const AcceptInviteView()),
                  );
                },
                icon: Icon(
                  Icons.mail_outline,
                  color: scheme.onSurface,
                ),
              ),
            ],
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _openCreate,
          icon: const Icon(Icons.add, color: Colors.white),
          backgroundColor: Colors.black,
          label: const Text(
            'Nuevo proyecto',
            style: TextStyle(color: Colors.white),
          ),
        ),
        body: ListenableBuilder(
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
                onRefresh: () => _controller.load(refresh: true),
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    SizedBox(height: MediaQuery.sizeOf(context).height * 0.2),
                    Icon(
                      Icons.home_work_outlined,
                      size: 56,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Aún no hay proyectos',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: scheme.onSurface,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Crea tu primer proyecto de vivienda\nunifamiliar en 9 etapas.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              );
            }

            final projects = _getFilteredProjects();

            if (projects.isEmpty && _searchQuery.isNotEmpty) {
              return RefreshIndicator(
                onRefresh: () => _controller.load(refresh: true),
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    SizedBox(height: MediaQuery.sizeOf(context).height * 0.2),
                    Icon(
                      Icons.search_off_rounded,
                      size: 56,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Sin coincidencias',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: scheme.onSurface,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Text(
                        'No encontramos ningún proyecto que coincida con "$_searchQuery".',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          height: 1.4,
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
                        icon: const Icon(Icons.clear),
                        label: const Text('Limpiar búsqueda'),
                      ),
                    ),
                  ],
                ),
              );
            }

            return RefreshIndicator(
              onRefresh: () => _controller.load(refresh: true),
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
                itemCount: projects.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final project = projects[index];
                  return HomeProjectCard(
                    project: project,
                    pinned: _controller.isPinned(project.id),
                    onTap: () => _openDetail(project.id),
                    onPin: () => _togglePin(
                      project,
                      wasPinned: _controller.isPinned(project.id),
                    ),
                    onRename: () => _promptRename(project),
                    onDelete: project.permissions.canDeleteProject
                        ? () => _confirmDelete(project)
                        : null,
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }
}
