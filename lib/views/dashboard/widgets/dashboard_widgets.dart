import 'package:flutter/material.dart';
import 'package:movil_architect/core/theme/app_colors.dart';
import 'package:movil_architect/models/dashboard_models.dart';

class DashboardTopBar extends StatelessWidget {
  const DashboardTopBar({super.key, required this.isPro});

  final bool isPro;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 22, 28, 12),
      child: Row(
        children: [
          const Icon(Icons.menu_rounded, size: 26, color: AppColors.ink),
          const SizedBox(width: 16),
          const Expanded(
            child: Text(
              'ARCHITECT',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppColors.ink,
                fontSize: 30,
                fontWeight: FontWeight.w900,
                letterSpacing: 4,
              ),
            ),
          ),
          if (isPro)
            Container(
              height: 24,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Text(
                'PRO',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class DashboardHeroIntro extends StatelessWidget {
  const DashboardHeroIntro({
    super.key,
    required this.title,
    required this.subtitle,
  });

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(36, 24, 36, 8),
      child: Column(
        children: [
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.ink,
              fontSize: 28,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.muted,
              fontSize: 16,
              height: 1.35,
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}

class DashboardMetricStrip extends StatelessWidget {
  const DashboardMetricStrip({super.key, required this.metrics});

  final List<DashboardMetric> metrics;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < metrics.length; i++) ...[
          if (i > 0) const SizedBox(width: 12),
          Expanded(child: DashboardMetricCard(metric: metrics[i])),
        ],
      ],
    );
  }
}

class DashboardMetricCard extends StatelessWidget {
  const DashboardMetricCard({super.key, required this.metric});

  final DashboardMetric metric;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 112,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.dashboardCard,
        borderRadius: BorderRadius.circular(28),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0E000000),
            blurRadius: 24,
            offset: Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(metric.icon, color: AppColors.muted, size: 20),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              metric.value,
              style: const TextStyle(
                color: AppColors.ink,
                fontSize: 25,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          Text(
            metric.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.muted,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class DashboardModuleCard extends StatelessWidget {
  const DashboardModuleCard({super.key, required this.module});

  final DashboardModule module;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 168),
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: AppColors.dashboardCard,
        borderRadius: BorderRadius.circular(30),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0C000000),
            blurRadius: 26,
            offset: Offset(0, 18),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: module.darkIcon ? Colors.black : AppColors.dashboardIconBg,
              shape: BoxShape.circle,
            ),
            child: Icon(
              module.icon,
              color: module.darkIcon ? Colors.white : AppColors.ink,
              size: 24,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            module.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.dashboardTitle,
              fontSize: 23,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            module.subtitle,
            style: const TextStyle(
              color: AppColors.ink,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            module.detail,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.muted,
              fontSize: 15,
              height: 1.35,
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}

class DashboardActivityPanel extends StatelessWidget {
  const DashboardActivityPanel({super.key, required this.activities});

  final List<ActivityItem> activities;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.dashboardCard,
        borderRadius: BorderRadius.circular(30),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0C000000),
            blurRadius: 26,
            offset: Offset(0, 18),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Actividad',
            style: TextStyle(
              color: AppColors.ink,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 16),
          for (final activity in activities)
            DashboardActivityRow(activity: activity),
        ],
      ),
    );
  }
}

class DashboardActivityRow extends StatelessWidget {
  const DashboardActivityRow({super.key, required this.activity});

  final ActivityItem activity;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: const BoxDecoration(
              color: AppColors.activityIconBg,
              shape: BoxShape.circle,
            ),
            child: Icon(activity.icon, size: 19, color: AppColors.muted),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              activity.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.ink,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            activity.time,
            style: const TextStyle(
              color: AppColors.muted,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class DashboardAskBar extends StatelessWidget {
  const DashboardAskBar({super.key, required this.placeholder});

  final String placeholder;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      padding: const EdgeInsets.fromLTRB(18, 8, 8, 8),
      decoration: BoxDecoration(
        color: const Color(0xF0FFFFFF),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: const Color(0xFFCBD5E1),
          width: 1.4,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x18000000),
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(
            Icons.attach_file_rounded,
            color: AppColors.muted,
            size: 23,
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Text(
              placeholder,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.askBarHint,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Container(
            width: 48,
            height: 48,
            decoration: const BoxDecoration(
              color: Colors.black,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.arrow_upward_rounded,
              color: Colors.white,
              size: 26,
            ),
          ),
        ],
      ),
    );
  }
}

class DashboardBottomNav extends StatelessWidget {
  const DashboardBottomNav({
    super.key,
    required this.items,
    required this.activeIndex,
    required this.onItemSelected,
  });

  final List<NavItemModel> items;
  final int activeIndex;
  final ValueChanged<int> onItemSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 78,
      padding: const EdgeInsets.fromLTRB(22, 9, 22, 10),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        boxShadow: [
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 22,
            offset: Offset(0, -8),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          for (var i = 0; i < items.length; i++)
            DashboardNavItem(
              item: items[i],
              active: i == activeIndex,
              onTap: () => onItemSelected(i),
            ),
        ],
      ),
    );
  }
}

class DashboardNavItem extends StatelessWidget {
  const DashboardNavItem({
    super.key,
    required this.item,
    required this.active,
    required this.onTap,
  });

  final NavItemModel item;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.ink : AppColors.navInactive;

    return SizedBox(
      width: 76,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(item.icon, color: color, size: 24),
            const SizedBox(height: 3),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                item.label,
                maxLines: 1,
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
