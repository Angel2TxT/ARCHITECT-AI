import 'package:flutter/material.dart';

class DashboardMetric {
  const DashboardMetric({
    required this.value,
    required this.label,
    required this.icon,
  });

  final String value;
  final String label;
  final IconData icon;
}

class DashboardModule {
  const DashboardModule({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.detail,
    this.darkIcon = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String detail;
  final bool darkIcon;
}

class ActivityItem {
  const ActivityItem({
    required this.icon,
    required this.title,
    required this.time,
  });

  final IconData icon;
  final String title;
  final String time;
}

class NavItemModel {
  const NavItemModel({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;
}

class DashboardData {
  const DashboardData({
    required this.heroTitle,
    required this.heroSubtitle,
    required this.metrics,
    required this.modules,
    required this.activities,
    required this.navItems,
    required this.askPlaceholder,
    required this.isPro,
  });

  final String heroTitle;
  final String heroSubtitle;
  final List<DashboardMetric> metrics;
  final List<DashboardModule> modules;
  final List<ActivityItem> activities;
  final List<NavItemModel> navItems;
  final String askPlaceholder;
  final bool isPro;

  factory DashboardData.mock() {
    return const DashboardData(
      heroTitle: 'Dashboard',
      heroSubtitle: 'Tus planos, revisiones y alertas en un solo lugar.',
      askPlaceholder: 'Dime tu pregunta',
      isPro: true,
      metrics: [
        DashboardMetric(
          value: '12',
          label: 'Planos',
          icon: Icons.layers_outlined,
        ),
        DashboardMetric(
          value: '84%',
          label: 'Avance',
          icon: Icons.query_stats_rounded,
        ),
        DashboardMetric(
          value: '32',
          label: 'Alertas',
          icon: Icons.notifications_none_rounded,
        ),
      ],
      modules: [
        DashboardModule(
          icon: Icons.error_outline_rounded,
          title: 'Análisis de Errores',
          subtitle: '24 hallazgos',
          detail: 'Estructura, normativa y trazos fuera de eje.',
          darkIcon: true,
        ),
        DashboardModule(
          icon: Icons.door_front_door_outlined,
          title: 'Revisión de Puertas',
          subtitle: '8 accesos',
          detail: 'Giros, claros mínimos y rutas accesibles.',
        ),
        DashboardModule(
          icon: Icons.straighten_rounded,
          title: 'Medidas',
          subtitle: '92% completo',
          detail: 'Cotas principales listas para comparar.',
        ),
      ],
      activities: [
        ActivityItem(
          icon: Icons.check_circle_outline_rounded,
          title: 'Normativa actualizada',
          time: 'Hace 12 min',
        ),
        ActivityItem(
          icon: Icons.upload_file_outlined,
          title: 'Casa Norte.dwg',
          time: 'Hoy',
        ),
        ActivityItem(
          icon: Icons.warning_amber_rounded,
          title: 'Escalera sin descanso',
          time: 'Pendiente',
        ),
      ],
      navItems: [
        NavItemModel(icon: Icons.workspaces_outline, label: 'Workspace'),
        NavItemModel(icon: Icons.view_in_ar_outlined, label: 'Models'),
        NavItemModel(icon: Icons.inventory_2_outlined, label: 'Archives'),
        NavItemModel(icon: Icons.settings_outlined, label: 'Settings'),
      ],
    );
  }
}
