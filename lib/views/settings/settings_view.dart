import 'package:flutter/material.dart';
import 'package:movil_architect/controllers/dashboard_controller.dart';
import 'package:movil_architect/controllers/settings_controller.dart';
import 'package:movil_architect/core/config/app_config.dart';
import 'package:movil_architect/core/theme/app_colors.dart';
import 'package:movil_architect/core/utils/app_notifications.dart';
import 'package:movil_architect/models/auth_models.dart';
import 'package:movil_architect/views/billing/billing_view.dart';
import 'package:movil_architect/views/billing/usage_limits_view.dart';
import 'package:movil_architect/views/dashboard/widgets/dashboard_drawer.dart';
import 'package:movil_architect/views/login/login_view.dart';
import 'package:movil_architect/views/login/widgets/login_widgets.dart';
import 'package:movil_architect/views/profile/profile_view.dart';
import 'package:movil_architect/views/support/support_list_view.dart';

class SettingsView extends StatefulWidget {
  const SettingsView({
    super.key,
    this.controller,
    this.onAllChatsDeleted,
    this.onNewChat,
    this.onChatOpen,
    this.onChatDeleted,
    this.onStageAdmin,
    this.onPlans,
  });

  final DashboardController? controller;
  final VoidCallback? onAllChatsDeleted;
  final VoidCallback? onNewChat;
  final ValueChanged<String>? onChatOpen;
  final ValueChanged<String>? onChatDeleted;
  final VoidCallback? onStageAdmin;
  final VoidCallback? onPlans;

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  late final DashboardController _dashboardController;
  late final SettingsController _settingsController;
  late final bool _ownsDashboardController;

  @override
  void initState() {
    super.initState();
    _ownsDashboardController = widget.controller == null;
    _dashboardController = widget.controller ?? DashboardController();
    _settingsController = SettingsController();
    _settingsController.load();
    if (_ownsDashboardController) {
      _dashboardController.load();
    }
  }

  @override
  void dispose() {
    _settingsController.dispose();
    if (_ownsDashboardController) {
      _dashboardController.dispose();
    }
    super.dispose();
  }

  Future<void> _saveServer() async {
    final ok = await _settingsController.save();
    if (!mounted) return;
    if (ok && _settingsController.successMessage != null) {
      AppNotifications.success(
        context,
        _settingsController.successMessage!,
      );
    } else if (_settingsController.errorMessage != null) {
      AppNotifications.error(context, _settingsController.errorMessage!);
    }
  }

  Future<void> _testConnection() async {
    await _settingsController.testConnection();
    if (!mounted) return;
    if (_settingsController.successMessage != null) {
      AppNotifications.success(
        context,
        _settingsController.successMessage!,
      );
    } else if (_settingsController.errorMessage != null) {
      AppNotifications.error(context, _settingsController.errorMessage!);
    }
  }

  Future<void> _logout() async {
    await _dashboardController.logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const LoginView()),
      (_) => false,
    );
  }

  Future<void> _confirmDeleteAllChats() async {
    final count = _dashboardController.chats.length;
    if (count == 0) {
      AppNotifications.error(
        context,
        'No hay conversaciones para eliminar',
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar historial de chats'),
        content: Text(
          '¿Borrar las $count conversaciones?\n'
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
                Text('Eliminando conversaciones…'),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      await _dashboardController.deleteAllChats();
      if (!mounted) return;
      Navigator.pop(context);
      widget.onAllChatsDeleted?.call();
      AppNotifications.success(context, 'Historial de chats eliminado');
    } catch (_) {
      if (!mounted) return;
      Navigator.pop(context);
      AppNotifications.error(
        context,
        'No se pudieron eliminar todas las conversaciones',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final cardColor = Theme.of(context).cardColor;

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      drawer: DashboardDrawer(
        controller: _dashboardController,
        onNewChat: widget.onNewChat ?? () {},
        onSettings: () {},
        onChatOpen: widget.onChatOpen ?? (_) {},
        onChatDeleted: widget.onChatDeleted,
        onStageAdmin: widget.onStageAdmin ?? () {},
        onPlans: widget.onPlans ?? () {},
      ),
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        automaticallyImplyLeading: false,
        leading: IconButton(
          tooltip: 'Menú',
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
          icon: Icon(
            Icons.menu_rounded,
            size: 26,
            color: colorScheme.onSurface,
          ),
        ),
        title: Text(
          'Ajustes',
          style: TextStyle(
            color: colorScheme.onSurface,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge([
          _dashboardController,
          _settingsController,
        ]),
        builder: (context, _) {
          final subscription = _dashboardController.subscription;

          return RefreshIndicator(
            onRefresh: () => _dashboardController.load(refresh: true),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              children: [
                const _SectionTitle('Enterprise'),
                const SizedBox(height: 10),
                if (_dashboardController.state == DashboardState.loading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (subscription != null)
                  _EnterpriseCard(subscription: subscription)
                else
                  const _InfoCard(
                    message: 'No se pudo cargar la información del plan.',
                  ),
                const SizedBox(height: 28),
                const _SectionTitle('Cuenta'),
                const SizedBox(height: 10),
                _SettingsTile(
                  icon: Icons.person_outline,
                  title: 'Perfil',
                  subtitle: 'Nombre, avatar y contraseña',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const ProfileView(),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 10),
                _SettingsTile(
                  icon: Icons.workspace_premium_outlined,
                  title: 'Planes y facturación',
                  subtitle: 'Cambiar plan, recibos y reembolsos',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const BillingView(),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 10),
                _SettingsTile(
                  icon: Icons.speed_outlined,
                  title: 'Uso y límites',
                  subtitle: 'Porcentaje de análisis y historial mensual',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const UsageLimitsView(),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 10),
                _SettingsTile(
                  icon: Icons.support_agent_outlined,
                  title: 'Ayuda y soporte',
                  subtitle: 'Tickets y mensajes',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const SupportListView(),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 28),
                const _SectionTitle('Apariencia'),
                const SizedBox(height: 10),
                Container(
                  decoration: BoxDecoration(
                    color: cardColor,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: SwitchListTile(
                    value: _settingsController.isDarkMode,
                    onChanged: _settingsController.setDarkMode,
                    title: Text(
                      'Modo oscuro',
                      style: TextStyle(
                        color: colorScheme.onSurface,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    subtitle: Text(
                      _settingsController.isDarkMode
                          ? 'Tema oscuro activo'
                          : 'Tema claro activo',
                      style: TextStyle(color: colorScheme.onSurfaceVariant),
                    ),
                    secondary: Icon(
                      _settingsController.isDarkMode
                          ? Icons.dark_mode_outlined
                          : Icons.light_mode_outlined,
                      color: colorScheme.onSurface,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  decoration: BoxDecoration(
                    color: cardColor,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: ListTile(
                    onTap: _confirmDeleteAllChats,
                    leading: Icon(
                      Icons.delete_sweep_outlined,
                      color: colorScheme.error,
                    ),
                    title: Text(
                      'Eliminar historial de chats',
                      style: TextStyle(
                        color: colorScheme.onSurface,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    subtitle: Text(
                      _dashboardController.chats.isEmpty
                          ? 'No hay conversaciones guardadas'
                          : '${_dashboardController.chats.length} conversaciones en el historial',
                      style: TextStyle(color: colorScheme.onSurfaceVariant),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                const _SectionTitle('Servidor'),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: cardColor,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'URL del backend',
                        style: TextStyle(
                          color: colorScheme.onSurface,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'API local (Docker): ${AppConfig.defaultServerUrl()}\n'
                        'Enciende el backend con Docker en el puerto 8000.\n'
                        'Emulador Android: http://10.0.2.2:8000',
                        style: TextStyle(
                          color: colorScheme.onSurfaceVariant,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 16),
                      LoginPillField(
                        controller: _settingsController.urlController,
                        hint: 'URL DEL SERVIDOR',
                        keyboardType: TextInputType.url,
                        autocorrect: false,
                      ),
                      const SizedBox(height: 14),
                      OutlinedButton(
                        onPressed: _settingsController.isTesting
                            ? null
                            : _testConnection,
                        child: _settingsController.isTesting
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('Probar conexión'),
                      ),
                      const SizedBox(height: 10),
                      LoginPrimaryButton(
                        label: 'Guardar servidor',
                        isLoading: _settingsController.isLoading,
                        onPressed: _saveServer,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _logout,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFD64545),
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(52),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  icon: const Icon(Icons.logout, color: Colors.white),
                  label: const Text('Cerrar sesión'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: ListTile(
        onTap: onTap,
        leading: Icon(icon, color: colorScheme.onSurface),
        title: Text(
          title,
          style: TextStyle(
            color: colorScheme.onSurface,
            fontWeight: FontWeight.w700,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(color: colorScheme.onSurfaceVariant),
        ),
        trailing: const Icon(Icons.chevron_right),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Text(
      label,
      style: TextStyle(
        color: colorScheme.onSurface,
        fontSize: 20,
        fontWeight: FontWeight.w900,
      ),
    );
  }
}

class _EnterpriseCard extends StatelessWidget {
  const _EnterpriseCard({required this.subscription});

  final SubscriptionModel subscription;

  static String _subscriptionStatusLabel(String status) {
    switch (status.toLowerCase().trim()) {
      case 'active':
        return 'Activo';
      case 'canceled':
      case 'cancelled':
        return 'Cancelado';
      case 'past_due':
        return 'Pago pendiente';
      case 'trialing':
        return 'Prueba';
      case 'incomplete':
        return 'Incompleto';
      case 'unpaid':
        return 'Sin pagar';
      case 'paused':
        return 'Pausado';
      default:
        return status;
    }
  }

  @override
  Widget build(BuildContext context) {
    final plan = subscription.plan;
    final usage = subscription.usage;
    final limit = plan.analysesLimitMonthly;
    final progress = subscription.isUnlimited || limit == null || limit == 0
        ? null
        : (usage.analysesUsed / limit).clamp(0.0, 1.0);
    final percent =
        progress == null ? null : (progress * 100).round();
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: const BoxDecoration(
                  color: AppColors.ink,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.workspace_premium_outlined,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      plan.name.toUpperCase(),
                      style: TextStyle(
                        color: colorScheme.onSurface,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1,
                      ),
                    ),
                    Text(
                      _subscriptionStatusLabel(subscription.status),
                      style: TextStyle(color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            subscription.isUnlimited
                ? 'Análisis ilimitados este mes'
                : percent != null
                    ? 'Uso del mes: $percent%'
                    : 'Análisis: ${usage.analysesUsed}',
            style: TextStyle(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (progress != null) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 8,
                backgroundColor: AppColors.loginFieldFill,
                color: const Color(0xFF1B4D8A),
              ),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            'Máx. ${plan.maxFileMb} MB por archivo',
            style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        message,
        style: TextStyle(color: colorScheme.onSurfaceVariant, height: 1.4),
      ),
    );
  }
}
