import 'package:flutter/material.dart';
import 'package:movil_architect/controllers/home_project_controller.dart';
import 'package:movil_architect/views/home_projects/home_project_detail_view.dart';

class CreateHomeProjectView extends StatefulWidget {
  const CreateHomeProjectView({super.key});

  @override
  State<CreateHomeProjectView> createState() => _CreateHomeProjectViewState();
}

class _CreateHomeProjectViewState extends State<CreateHomeProjectView> {
  static const _descriptionMax = 500;

  late final CreateHomeProjectController _controller;
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _clientController = TextEditingController();
  final _locationController = TextEditingController();
  final _descriptionController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _controller = CreateHomeProjectController();
    _descriptionController.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _nameController.dispose();
    _clientController.dispose();
    _locationController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final project = await _controller.create(
      name: _nameController.text,
      clientName: _clientController.text,
      location: _locationController.text,
      description: _descriptionController.text,
    );
    if (!mounted || project == null) return;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => HomeProjectDetailView(projectId: project.id),
      ),
    );
  }

  void _showInfo() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        final scheme = Theme.of(context).colorScheme;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '¿Qué es un proyecto Casa hogar?',
                  style: TextStyle(
                    color: scheme.onSurface,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Te guía por 9 etapas de una vivienda unifamiliar: '
                  'desde el levantamiento hasta la entrega. '
                  'Puedes adjuntar planos, documentos y trabajar con tu equipo.',
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 14,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context),
                    style: FilledButton.styleFrom(
                      backgroundColor: scheme.onSurface,
                      foregroundColor: scheme.surface,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    child: const Text('Entendido'),
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
    final scheme = Theme.of(context).colorScheme;
    final isDark = scheme.brightness == Brightness.dark;
    final surface = Theme.of(context).scaffoldBackgroundColor;
    final fieldFill = isDark
        ? scheme.surfaceContainerHighest
        : const Color(0xFFF2F2F4);
    final muted = scheme.onSurfaceVariant;

    return Scaffold(
      backgroundColor: isDark ? surface : Colors.white,
      appBar: AppBar(
        title: Text(
          'Nuevo proyecto',
          style: TextStyle(
            color: scheme.onSurface,
            fontWeight: FontWeight.w700,
            fontSize: 17,
          ),
        ),
        centerTitle: true,
        backgroundColor: isDark ? surface : Colors.white,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(
            height: 1,
            thickness: 1,
            color: scheme.outlineVariant.withValues(alpha: 0.45),
          ),
        ),
        actions: [
          IconButton(
            onPressed: _showInfo,
            tooltip: 'Información',
            icon: Icon(
              Icons.info_outline_rounded,
              color: muted,
            ),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) {
          return Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(22, 22, 22, 16),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Datos del proyecto',
                          style: TextStyle(
                            color: scheme.onSurface,
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            height: 1.15,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Ingresa la información clave para iniciar y gestionar tu obra o servicio.',
                          style: TextStyle(
                            color: muted,
                            fontSize: 14,
                            height: 1.4,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 28),
                        _LabeledField(
                          label: 'Nombre del proyecto *',
                          child: TextFormField(
                            controller: _nameController,
                            textInputAction: TextInputAction.next,
                            textCapitalization: TextCapitalization.sentences,
                            style: TextStyle(
                              color: scheme.onSurface,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                            decoration: _fieldDecoration(
                              fill: fieldFill,
                              muted: muted,
                              icon: Icons.folder_outlined,
                              hint: 'Ej. Residencia Palmeras Norte',
                            ),
                            validator: (value) {
                              final text = value?.trim() ?? '';
                              if (text.length < 2) {
                                return 'Mínimo 2 caracteres';
                              }
                              if (text.length > 160) {
                                return 'Máximo 160 caracteres';
                              }
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(height: 18),
                        _LabeledField(
                          label: 'Cliente',
                          child: TextFormField(
                            controller: _clientController,
                            textInputAction: TextInputAction.next,
                            textCapitalization: TextCapitalization.words,
                            style: TextStyle(
                              color: scheme.onSurface,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                            decoration: _fieldDecoration(
                              fill: fieldFill,
                              muted: muted,
                              icon: Icons.person_outline_rounded,
                              hint: 'Ej. Arq. Sofía Domínguez o Grupo ALFA',
                            ),
                            validator: (value) {
                              if ((value ?? '').trim().length > 120) {
                                return 'Máximo 120 caracteres';
                              }
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(height: 18),
                        _LabeledField(
                          label: 'Ubicación',
                          child: TextFormField(
                            controller: _locationController,
                            textInputAction: TextInputAction.next,
                            textCapitalization: TextCapitalization.sentences,
                            style: TextStyle(
                              color: scheme.onSurface,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                            decoration: _fieldDecoration(
                              fill: fieldFill,
                              muted: muted,
                              icon: Icons.place_outlined,
                              hint: 'Ej. Av. Insurgentes Sur 1450, CDMX',
                            ),
                            validator: (value) {
                              if ((value ?? '').trim().length > 200) {
                                return 'Máximo 200 caracteres';
                              }
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(height: 18),
                        _LabeledField(
                          label: 'Descripción',
                          trailing: Text(
                            'Máx. $_descriptionMax car.',
                            style: TextStyle(
                              color: muted,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          child: TextFormField(
                            controller: _descriptionController,
                            maxLines: 5,
                            maxLength: _descriptionMax,
                            textCapitalization: TextCapitalization.sentences,
                            style: TextStyle(
                              color: scheme.onSurface,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              height: 1.35,
                            ),
                            decoration: _fieldDecoration(
                              fill: fieldFill,
                              muted: muted,
                              hint:
                                  'Detalles sobre alcance, especificaciones iniciales, metros cuadrados u objetivos del proyecto...',
                              alignLabelWithHint: true,
                            ).copyWith(
                              counterText: '',
                              contentPadding: const EdgeInsets.fromLTRB(
                                16,
                                16,
                                16,
                                16,
                              ),
                            ),
                            validator: (value) {
                              if ((value ?? '').trim().length >
                                  _descriptionMax) {
                                return 'Máximo $_descriptionMax caracteres';
                              }
                              return null;
                            },
                          ),
                        ),
                        if (_controller.errorMessage != null) ...[
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFE8E8),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Text(
                              _controller.errorMessage!,
                              style: const TextStyle(
                                color: Color(0xFFB42318),
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(22, 8, 22, 16),
                  child: _CreateProjectButton(
                    isLoading: _controller.isLoading,
                    onPressed: _submit,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  InputDecoration _fieldDecoration({
    required Color fill,
    required Color muted,
    required String hint,
    IconData? icon,
    bool alignLabelWithHint = false,
  }) {
    return InputDecoration(
      filled: true,
      fillColor: fill,
      hintText: hint,
      hintStyle: TextStyle(
        color: muted.withValues(alpha: 0.85),
        fontSize: 14,
        fontWeight: FontWeight.w500,
      ),
      prefixIcon: icon == null
          ? null
          : Icon(icon, color: muted, size: 22),
      alignLabelWithHint: alignLabelWithHint,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.2),
          width: 1.4,
        ),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFFD64545)),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFFD64545), width: 1.4),
      ),
    );
  }
}

class _LabeledField extends StatelessWidget {
  const _LabeledField({
    required this.label,
    required this.child,
    this.trailing,
  });

  final String label;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: scheme.onSurface,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            ?trailing,
          ],
        ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }
}

class _CreateProjectButton extends StatelessWidget {
  const _CreateProjectButton({
    required this.isLoading,
    required this.onPressed,
  });

  final bool isLoading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = scheme.brightness == Brightness.dark;
    final bg = isDark ? scheme.onSurface : Colors.black;
    final fg = isDark ? scheme.surface : Colors.white;

    return SizedBox(
      height: 56,
      width: double.infinity,
      child: FilledButton(
        onPressed: isLoading ? null : onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: bg,
          foregroundColor: fg,
          disabledBackgroundColor: bg.withValues(alpha: 0.55),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
          ),
        ),
        child: isLoading
            ? SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: fg,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Crear proyecto',
                    style: TextStyle(
                      color: fg,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(Icons.arrow_forward_rounded, color: fg, size: 20),
                ],
              ),
      ),
    );
  }
}
