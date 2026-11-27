import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:movil_architect/controllers/home_project_controller.dart';
import 'package:movil_architect/core/app_services.dart';
import 'package:movil_architect/core/network/api_exception.dart';
import 'package:movil_architect/core/theme/architect_theme_tokens.dart';
import 'package:movil_architect/core/utils/app_notifications.dart';
import 'package:movil_architect/models/home_project_models.dart';
import 'package:movil_architect/views/home_projects/home_project_detail_view.dart';

class AcceptInviteView extends StatefulWidget {
  const AcceptInviteView({super.key});

  @override
  State<AcceptInviteView> createState() => _AcceptInviteViewState();
}

class _AcceptInviteViewState extends State<AcceptInviteView> {
  final _inviteInputController = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _inviteInputController.dispose();
    super.dispose();
  }

  Future<void> _accept() async {
    final raw = _inviteInputController.text.trim();
    String token = raw;
    final uri = Uri.tryParse(raw);
    if (uri != null && (uri.isScheme('http') || uri.isScheme('https'))) {
      if (uri.queryParameters.containsKey('invite') &&
          uri.queryParameters['invite']!.trim().isNotEmpty) {
        token = uri.queryParameters['invite']!.trim();
      } else if (uri.queryParameters.containsKey('token') &&
          uri.queryParameters['token']!.trim().isNotEmpty) {
        token = uri.queryParameters['token']!.trim();
      } else if (uri.pathSegments.isNotEmpty &&
          uri.pathSegments.last.trim().isNotEmpty) {
        token = uri.pathSegments.last.trim();
      }
    }

    token = token.replaceAll(' ', '').replaceAll('-', '');

    if (token.isEmpty) {
      setState(() => _error = 'Ingresa el código de 6 dígitos.');
      return;
    }
    if (token.length < 6) {
      setState(() => _error = 'El código debe tener al menos 6 dígitos.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final project =
          await AppServices.instance.homeProjectService.acceptInvite(token);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => HomeProjectDetailView(projectId: project.id),
        ),
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.message;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'No se pudo aceptar la invitación.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = scheme.brightness == Brightness.dark;
    final btnBg = isDark ? Colors.white : Colors.black;
    final btnFg = isDark ? Colors.black : Colors.white;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Aceptar invitación',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Ingresa el código numérico de 6 dígitos que recibiste por correo para unirte al proyecto.',
              style: TextStyle(height: 1.4),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _inviteInputController,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                letterSpacing: 6,
              ),
              decoration: InputDecoration(
                labelText: 'Código de invitación',
                hintText: '000000',
                helperText: 'Ejemplo: 482910 (o pega el enlace de invitación)',
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(
                    color: scheme.outlineVariant,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(
                    color: isDark ? Colors.white : Colors.black,
                    width: 1.5,
                  ),
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Colors.redAccent)),
            ],
            const SizedBox(height: 20),
            SizedBox(
              height: 52,
              child: FilledButton(
                onPressed: _loading ? null : _accept,
                style: FilledButton.styleFrom(
                  backgroundColor: btnBg,
                  foregroundColor: btnFg,
                  disabledBackgroundColor: btnBg.withValues(alpha: 0.45),
                  disabledForegroundColor: btnFg.withValues(alpha: 0.6),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                child: _loading
                    ? SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: btnFg,
                        ),
                      )
                    : const Text('Aceptar invitación'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class HomeProjectTeamView extends StatelessWidget {
  const HomeProjectTeamView({super.key, required this.controller});

  final HomeProjectDetailController controller;

  ButtonStyle _cancelButtonStyle(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return FilledButton.styleFrom(
      foregroundColor: Colors.white,
      backgroundColor:
          isDark ? const Color(0xFF3E3E44) : const Color(0xFF6B6B73),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      minimumSize: const Size(0, 42),
    );
  }

  ButtonStyle _dangerButtonStyle(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return FilledButton.styleFrom(
      foregroundColor: Colors.white,
      backgroundColor:
          isDark ? const Color(0xFFD9383A) : const Color(0xFFC8282A),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      minimumSize: const Size(0, 42),
    );
  }

  Future<void> _invite(BuildContext context) async {
    final tokens = ArchitectThemeTokens.of(context);
    final emailController = TextEditingController();
    var role = 'editor';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setLocal) => AlertDialog(
          title: const Text('Invitar miembro'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: emailController,
                autofocus: true,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(
                    RegExp(r'[a-zA-Z0-9@._+-]'),
                  ),
                ],
                style: ArchitectThemeTokens.appleText(
                  color: tokens.textPrimary,
                  fontSize: 15,
                ),
                decoration: InputDecoration(
                  labelText: 'Correo electrónico',
                  hintText: 'arquitecto@estudio.com',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                key: ValueKey(role),
                initialValue: role,
                decoration: InputDecoration(
                  labelText: 'Rol',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                items: const [
                  DropdownMenuItem(value: 'editor', child: Text('Editor')),
                  DropdownMenuItem(value: 'viewer', child: Text('Lectura')),
                ],
                onChanged: (value) {
                  if (value != null) setLocal(() => role = value);
                },
              ),
            ],
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              style: _cancelButtonStyle(dialogContext),
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
              onPressed: () => Navigator.pop(dialogContext, true),
              style: FilledButton.styleFrom(
                foregroundColor: tokens.primaryActionFg,
                backgroundColor: tokens.primaryActionBg,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 10,
                ),
                minimumSize: const Size(0, 42),
              ),
              child: Text(
                'Invitar',
                style: ArchitectThemeTokens.appleText(
                  color: tokens.primaryActionFg,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !context.mounted) {
      emailController.dispose();
      return;
    }
    final status = await controller.inviteMember(
      email: emailController.text,
      role: role,
    );
    emailController.dispose();
    if (!context.mounted) return;
    final message = status ?? controller.actionError ?? 'No se pudo invitar';
    if (status == null || status == 'Sin permiso para invitar.') {
      AppNotifications.error(context, message);
    } else {
      AppNotifications.success(context, message);
    }
  }

  Future<void> _remove(
    BuildContext context,
    HomeProjectMember member,
  ) async {
    final displayName =
        member.fullName.isNotEmpty ? member.fullName : member.email;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Quitar miembro'),
        content: Text('¿Quitar a $displayName del proyecto?'),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            style: _cancelButtonStyle(dialogContext),
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
            onPressed: () => Navigator.pop(dialogContext, true),
            style: _dangerButtonStyle(dialogContext),
            child: Text(
              'Quitar',
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
    if (ok != true || !context.mounted) return;
    final success = await controller.removeMember(member.userId);
    if (!context.mounted) return;
    AppNotifications.result(
      context,
      ok: success,
      successMessage: 'Miembro eliminado',
      errorMessage: controller.actionError,
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = ArchitectThemeTokens.of(context);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final project = controller.project;
        final canManage = controller.permissions.canManageTeam;

        return Scaffold(
          backgroundColor: tokens.drawerBackground,
          appBar: AppBar(
            backgroundColor: tokens.drawerBackground,
            foregroundColor: tokens.textPrimary,
            elevation: 0,
            scrolledUnderElevation: 0,
            centerTitle: true,
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
            title: Semantics(
              header: true,
              child: Text(
                'Equipo',
                style: ArchitectThemeTokens.appleDisplay(
                  color: tokens.textPrimary,
                  fontSize: 19,
                  fontWeight: FontWeight.w500,
                  letterSpacing: -0.3,
                ),
              ),
            ),
          ),
          floatingActionButton: canManage
              ? SafeArea(
                  top: false,
                  left: false,
                  child: _InviteMemberButton(
                    busy: controller.busy,
                    reduceMotion: reduceMotion,
                    onPressed: () => _invite(context),
                  ),
                )
              : null,
          body: SafeArea(
            top: false,
            child: project == null
                ? Center(
                    child: CircularProgressIndicator(color: tokens.accent),
                  )
                : RefreshIndicator(
                    color: tokens.accent,
                    onRefresh: () => controller.load(refresh: true),
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 104),
                      children: [
                        Text(
                          canManage
                              ? 'Gestiona miembros del proyecto.'
                              : 'Solo lectura: puedes ver el equipo.',
                          style: ArchitectThemeTokens.appleText(
                            color: tokens.textSecondary,
                            fontSize: 14,
                            fontWeight: FontWeight.w400,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 20),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text(
                              'Miembros',
                              style: ArchitectThemeTokens.appleDisplay(
                                color: tokens.textPrimary,
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                                letterSpacing: -0.2,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${project.members.length}',
                              style: ArchitectThemeTokens.appleText(
                                color: tokens.textSecondary,
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        if (project.members.isEmpty)
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
                                'Aún no hay miembros listados.',
                                style: ArchitectThemeTokens.appleText(
                                  color: tokens.textSecondary,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          )
                        else
                          for (final member in project.members) ...[
                            _TeamMemberCard(
                              member: member,
                              canRemove: canManage && !member.isOwner,
                              busy: controller.busy,
                              onRemove: () => _remove(context, member),
                            ),
                            const SizedBox(height: 10),
                          ],
                      ],
                    ),
                  ),
          ),
        );
      },
    );
  }
}

class _TeamMemberCard extends StatelessWidget {
  const _TeamMemberCard({
    required this.member,
    required this.canRemove,
    required this.busy,
    required this.onRemove,
  });

  final HomeProjectMember member;
  final bool canRemove;
  final bool busy;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final tokens = ArchitectThemeTokens.of(context);
    final textScale = MediaQuery.textScalerOf(context).scale(1.0);
    final displayName =
        member.fullName.trim().isNotEmpty ? member.fullName.trim() : member.email;
    final initial =
        displayName.trim().isNotEmpty ? displayName.trim()[0].toUpperCase() : '?';

    return Semantics(
      label:
          '$displayName, ${member.email}, ${homeProjectRoleLabel(member.role)}',
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
        decoration: BoxDecoration(
          color: tokens.surfaceSecondary,
          borderRadius: BorderRadius.circular(ArchitectThemeTokens.radiusLg),
          border: Border.all(color: tokens.borderSubtle, width: 1),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: member.isOwner
                    ? tokens.accentSubtle
                    : tokens.surfaceSelected,
                border: Border.all(
                  color: member.isOwner
                      ? tokens.accent.withValues(alpha: 0.4)
                      : tokens.borderStrong,
                  width: 1,
                ),
              ),
              alignment: Alignment.center,
              child: Text(
                initial,
                style: ArchitectThemeTokens.appleDisplay(
                  color: member.isOwner ? tokens.accent : tokens.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayName,
                    maxLines: textScale > 1.3 ? 2 : 1,
                    overflow: TextOverflow.ellipsis,
                    style: ArchitectThemeTokens.appleText(
                      color: tokens.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      height: 1.25,
                    ),
                  ),
                  if (member.email.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      member.email,
                      maxLines: textScale > 1.3 ? 2 : 1,
                      overflow: TextOverflow.ellipsis,
                      style: ArchitectThemeTokens.appleText(
                        color: tokens.textSecondary,
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  _RoleBadge(role: member.role, isOwner: member.isOwner),
                ],
              ),
            ),
            if (canRemove)
              Semantics(
                button: true,
                label: 'Quitar a $displayName',
                child: IconButton(
                  tooltip: 'Quitar miembro',
                  constraints: const BoxConstraints(
                    minWidth: 44,
                    minHeight: 44,
                  ),
                  onPressed: busy ? null : onRemove,
                  icon: Icon(
                    Icons.person_remove_outlined,
                    size: 20,
                    color: tokens.statusError,
                  ),
                ),
              )
            else
              const SizedBox(width: 6),
          ],
        ),
      ),
    );
  }
}

class _RoleBadge extends StatelessWidget {
  const _RoleBadge({required this.role, required this.isOwner});

  final String role;
  final bool isOwner;

  @override
  Widget build(BuildContext context) {
    final tokens = ArchitectThemeTokens.of(context);
    final label = homeProjectRoleLabel(role);
    final isEditor = role == 'editor';

    final Color bgColor;
    final Color fgColor;

    if (isOwner) {
      bgColor = tokens.accentSubtle;
      fgColor = tokens.accent;
    } else if (isEditor) {
      bgColor = tokens.statusPositive.withValues(alpha: 0.12);
      fgColor = tokens.statusPositive;
    } else {
      bgColor = tokens.surfaceSelected;
      fgColor = tokens.textSecondary;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(ArchitectThemeTokens.radiusSm),
      ),
      child: Text(
        label,
        style: ArchitectThemeTokens.appleText(
          color: fgColor,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class _InviteMemberButton extends StatefulWidget {
  const _InviteMemberButton({
    required this.busy,
    required this.reduceMotion,
    required this.onPressed,
  });

  final bool busy;
  final bool reduceMotion;
  final VoidCallback onPressed;

  @override
  State<_InviteMemberButton> createState() => _InviteMemberButtonState();
}

class _InviteMemberButtonState extends State<_InviteMemberButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final tokens = ArchitectThemeTokens.of(context);
    final disabled = widget.busy;

    return Semantics(
      button: true,
      enabled: !disabled,
      label: 'Invitar miembro al proyecto',
      child: AnimatedScale(
        scale: (_pressed && !disabled && !widget.reduceMotion) ? 0.97 : 1.0,
        duration: widget.reduceMotion
            ? Duration.zero
            : const Duration(milliseconds: 110),
        curve: Curves.easeOutCubic,
        child: Material(
          color: disabled
              ? tokens.primaryActionBg.withValues(alpha: 0.45)
              : tokens.primaryActionBg,
          borderRadius: BorderRadius.circular(ArchitectThemeTokens.radiusMd),
          elevation: 0,
          child: InkWell(
            onTap: disabled ? null : widget.onPressed,
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
                      Icons.person_add_outlined,
                      size: 18,
                      color: tokens.primaryActionFg,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Invitar',
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

