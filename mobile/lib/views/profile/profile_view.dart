import 'package:flutter/material.dart';
import 'package:movil_architect/controllers/profile_controller.dart';
import 'package:movil_architect/core/app_services.dart';
import 'package:movil_architect/core/theme/app_colors.dart';
import 'package:movil_architect/core/utils/app_notifications.dart';
import 'package:movil_architect/views/login/login_view.dart';
import 'package:movil_architect/views/shared/app_states.dart';

class ProfileView extends StatefulWidget {
  const ProfileView({super.key});

  @override
  State<ProfileView> createState() => _ProfileViewState();
}

class _ProfileViewState extends State<ProfileView> {
  late final ProfileController _controller;
  bool _obscureCurrent = true;
  bool _obscureNew = true;

  @override
  void initState() {
    super.initState();
    _controller = ProfileController()..load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String? _avatarUrl() {
    final url = _controller.user?.avatarUrl;
    if (url == null || url.isEmpty) return null;
    if (url.startsWith('http')) return url;
    return '${AppServices.instance.apiClient.dio.options.baseUrl}$url';
  }

  String get _initial {
    final user = _controller.user;
    if (user == null) return 'U';
    if (user.fullName.trim().isNotEmpty) {
      return user.fullName.trim()[0].toUpperCase();
    }
    if (user.email.isNotEmpty) return user.email[0].toUpperCase();
    return 'U';
  }

  String get _roleLabel {
    final role = _controller.user?.role.trim().toLowerCase() ?? 'user';
    return switch (role) {
      'admin' || 'administrador' => 'Administrador',
      'architect' || 'arquitecto' => 'Arquitecto',
      _ => role.isEmpty ? 'Usuario' : role[0].toUpperCase() + role.substring(1),
    };
  }

  void _showFeedback(bool ok) {
    if (ok && _controller.successMessage != null) {
      AppNotifications.success(context, _controller.successMessage!);
    } else if (_controller.errorMessage != null) {
      AppNotifications.error(context, _controller.errorMessage!);
    }
  }

  Future<void> _saveName() async {
    final ok = await _controller.saveName();
    if (!mounted) return;
    _showFeedback(ok);
  }

  Future<void> _savePassword() async {
    final ok = await _controller.savePassword();
    if (!mounted) return;
    _showFeedback(ok);
  }

  Future<void> _pickAvatar() async {
    final ok = await _controller.pickAndUploadAvatar();
    if (!mounted) return;
    _showFeedback(ok);
  }

  Future<void> _delete() async {
    final user = _controller.user;
    if (user == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar cuenta'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              user.hasPassword
                  ? 'Escribe tu contraseña para confirmar.'
                  : 'Escribe tu correo (${user.email}) para confirmar.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _controller.confirmDeleteController,
              obscureText: user.hasPassword,
              decoration: InputDecoration(
                hintText: user.hasPassword ? 'Contraseña' : 'Correo',
                filled: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ],
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
    if (!await _controller.deleteAccount()) {
      if (mounted && _controller.errorMessage != null) {
        AppNotifications.error(context, _controller.errorMessage!);
      }
      return;
    }
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const LoginView()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = colorScheme.brightness == Brightness.dark;
    final pageBg = isDark ? colorScheme.surface : AppColors.dashboardSurface;
    final cardBg = isDark ? colorScheme.surfaceContainerHighest : Colors.white;
    final fieldBg =
        isDark ? colorScheme.surfaceContainerHigh : const Color(0xFFF4F4F6);

    return Scaffold(
      backgroundColor: pageBg,
      appBar: AppBar(
        title: const Text(
          'Perfil',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        centerTitle: true,
        backgroundColor: pageBg,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) {
          if (_controller.isLoadingProfile) {
            return const AppLoadingView(message: 'Cargando perfil...');
          }

          final user = _controller.user;
          final avatar = _avatarUrl();
          final hasPassword = user?.hasPassword != false;

          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              _AvatarHeader(
                initial: _initial,
                avatarUrl: avatar,
                email: user?.email ?? '',
                isUpdating: _controller.isUpdatingAvatar,
                onPick: _pickAvatar,
              ),
              const SizedBox(height: 28),
              _ProfileCard(
                background: cardBg,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SectionLabel(
                      label: 'DATOS DE LA CUENTA',
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Nombre de usuario',
                      style: TextStyle(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _ProfileField(
                      controller: _controller.nameController,
                      fillColor: fieldBg,
                      prefixIcon: Icons.person_outline_rounded,
                      hint: 'Tu nombre',
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Rol: $_roleLabel',
                      style: TextStyle(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (user?.email.isNotEmpty == true) ...[
                      const SizedBox(height: 4),
                      Text(
                        user!.email,
                        style: TextStyle(
                          color: colorScheme.onSurfaceVariant,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),
                    _ProfilePrimaryButton(
                      label: 'Guardar nombre',
                      icon: Icons.check_rounded,
                      isLoading: _controller.isSavingName,
                      onPressed: _saveName,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _ProfileCard(
                background: cardBg,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.lock_outline_rounded,
                          size: 20,
                          color: colorScheme.onSurface,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            hasPassword
                                ? 'Cambiar contraseña'
                                : 'Crear contraseña',
                            style: TextStyle(
                              color: colorScheme.onSurface,
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: fieldBg,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            'Seguridad',
                            style: TextStyle(
                              color: colorScheme.onSurfaceVariant,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (!hasPassword) ...[
                      const SizedBox(height: 10),
                      Text(
                        'Tu cuenta es de Google. Puedes crear una contraseña para entrar también con correo.',
                        style: TextStyle(
                          color: colorScheme.onSurfaceVariant,
                          height: 1.4,
                          fontSize: 13,
                        ),
                      ),
                    ],
                    if (hasPassword) ...[
                      const SizedBox(height: 18),
                      Text(
                        'Contraseña actual',
                        style: TextStyle(
                          color: colorScheme.onSurfaceVariant,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _ProfileField(
                        controller: _controller.currentPasswordController,
                        fillColor: fieldBg,
                        obscureText: _obscureCurrent,
                        hint: '••••••••',
                        suffix: IconButton(
                          onPressed: () => setState(
                            () => _obscureCurrent = !_obscureCurrent,
                          ),
                          icon: Icon(
                            _obscureCurrent
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                            size: 20,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    Text(
                      'Nueva contraseña',
                      style: TextStyle(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _ProfileField(
                      controller: _controller.newPasswordController,
                      fillColor: fieldBg,
                      obscureText: _obscureNew,
                      hint: 'Mínimo 8 caracteres',
                      suffix: IconButton(
                        onPressed: () =>
                            setState(() => _obscureNew = !_obscureNew),
                        icon: Icon(
                          _obscureNew
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          size: 20,
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    _ProfilePrimaryButton(
                      label: 'Actualizar contraseña',
                      icon: Icons.vpn_key_rounded,
                      isLoading: _controller.isSavingPassword,
                      onPressed: _savePassword,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _DangerCard(
                isLoading: _controller.isDeletingAccount,
                onDelete: _delete,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _AvatarHeader extends StatelessWidget {
  const _AvatarHeader({
    required this.initial,
    required this.avatarUrl,
    required this.email,
    required this.isUpdating,
    required this.onPick,
  });

  final String initial;
  final String? avatarUrl;
  final String email;
  final bool isUpdating;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 160,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppColors.iosBlue.withValues(alpha: 0.18),
                    AppColors.iosBlue.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  padding: const EdgeInsets.all(3),
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color(0xFF111111),
                        Color(0xFF5A5A60),
                        Color(0xFF007AFF),
                      ],
                    ),
                  ),
                  child: CircleAvatar(
                    radius: 52,
                    backgroundColor: colorScheme.surface,
                    backgroundImage:
                        avatarUrl != null ? NetworkImage(avatarUrl!) : null,
                    child: avatarUrl == null
                        ? Text(
                            initial,
                            style: TextStyle(
                              fontSize: 36,
                              fontWeight: FontWeight.w900,
                              color: colorScheme.onSurface,
                            ),
                          )
                        : null,
                  ),
                ),
                Positioned(
                  right: 2,
                  bottom: 2,
                  child: Material(
                    color: AppColors.ink,
                    shape: const CircleBorder(),
                    elevation: 2,
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: isUpdating ? null : onPick,
                      child: SizedBox(
                        width: 36,
                        height: 36,
                        child: Center(
                          child: isUpdating
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(
                                  Icons.photo_camera_rounded,
                                  color: Colors.white,
                                  size: 18,
                                ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 14),
        TextButton(
          onPressed: isUpdating ? null : onPick,
          child: Text(
            isUpdating ? 'Actualizando foto…' : 'Cambiar foto',
            style: TextStyle(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
          ),
        ),
        if (email.isNotEmpty)
          Text(
            email,
            style: TextStyle(
              color: colorScheme.onSurfaceVariant,
              fontSize: 13,
            ),
          ),
      ],
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    required this.child,
    required this.background,
  });

  final Widget child;
  final Color background;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.06)
              : const Color(0xFFE8E8EC),
        ),
        boxShadow: isDark
            ? null
            : const [
                BoxShadow(
                  color: Color(0x08000000),
                  blurRadius: 18,
                  offset: Offset(0, 8),
                ),
              ],
      ),
      child: child,
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({
    required this.label,
  });

  final String label;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurface;
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
          ),
        ),
      ],
    );
  }
}

class _ProfileField extends StatelessWidget {
  const _ProfileField({
    required this.controller,
    required this.fillColor,
    this.hint,
    this.prefixIcon,
    this.suffix,
    this.obscureText = false,
  });

  final TextEditingController controller;
  final Color fillColor;
  final String? hint;
  final IconData? prefixIcon;
  final Widget? suffix;
  final bool obscureText;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return TextField(
      controller: controller,
      obscureText: obscureText,
      autocorrect: !obscureText,
      style: TextStyle(
        color: colorScheme.onSurface,
        fontWeight: FontWeight.w600,
        fontSize: 15,
      ),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(
          color: colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w500,
        ),
        prefixIcon: prefixIcon == null
            ? null
            : Icon(prefixIcon, size: 20, color: colorScheme.onSurfaceVariant),
        suffixIcon: suffix,
        filled: true,
        fillColor: fillColor,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

class _ProfilePrimaryButton extends StatelessWidget {
  const _ProfilePrimaryButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.isLoading = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? Colors.white : AppColors.ink;
    final fg = isDark ? AppColors.ink : Colors.white;
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: FilledButton.icon(
        onPressed: isLoading ? null : onPressed,
        icon: isLoading
            ? SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  color: fg,
                ),
              )
            : Icon(icon, size: 18),
        label: Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
        style: FilledButton.styleFrom(
          backgroundColor: bg,
          foregroundColor: fg,
          disabledBackgroundColor: bg.withValues(alpha: 0.5),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }
}

class _DangerCard extends StatelessWidget {
  const _DangerCard({
    required this.isLoading,
    required this.onDelete,
  });

  final bool isLoading;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF2A1518) : const Color(0xFFFFF1F1);
    final border = isDark ? const Color(0xFF5C2B2F) : const Color(0xFFF3C6C6);
    final title = isDark ? const Color(0xFFFFB4AB) : const Color(0xFFB42318);
    final body = isDark ? const Color(0xFFE8B4B0) : const Color(0xFF912018);
    final accent = isDark ? const Color(0xFFFF8A80) : const Color(0xFFD64545);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.warning_amber_rounded,
                color: accent,
                size: 22,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Acción irreversible',
                      style: TextStyle(
                        color: title,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Esta acción eliminará todos los datos asociados a tu cuenta.',
                      style: TextStyle(
                        color: body,
                        height: 1.4,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton(
              onPressed: isLoading ? null : onDelete,
              style: OutlinedButton.styleFrom(
                foregroundColor: accent,
                side: BorderSide(color: accent),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: isLoading
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: accent,
                      ),
                    )
                  : const Text(
                      'Eliminar cuenta',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
