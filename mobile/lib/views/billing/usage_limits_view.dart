import 'package:flutter/material.dart';
import 'package:movil_architect/core/app_services.dart';
import 'package:movil_architect/core/network/api_exception.dart';
import 'package:movil_architect/core/theme/app_colors.dart';
import 'package:movil_architect/models/auth_models.dart';
import 'package:movil_architect/models/billing_models.dart';

class UsageLimitsView extends StatefulWidget {
  const UsageLimitsView({super.key});

  @override
  State<UsageLimitsView> createState() => _UsageLimitsViewState();
}

class _UsageLimitsViewState extends State<UsageLimitsView> {
  bool _loading = true;
  String? _error;
  SubscriptionModel? _subscription;
  List<UsageHistoryPoint> _history = [];
  int _selectedUsageIndex = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final billing = AppServices.instance.billingService;
      final api = AppServices.instance.mobileApiService;
      final auth = AppServices.instance.authService;
      final results = await Future.wait([
        billing.getSubscription(),
        billing.usageHistory(),
        api.me(),
      ]);
      _subscription = results[0] as SubscriptionModel?;
      _history = results[1] as List<UsageHistoryPoint>;
      final me = results[2] as MeResponse;
      auth.updateSession(user: me.user, subscription: me.subscription);
      _subscription ??= me.subscription;
      if (_history.isNotEmpty) {
        _selectedUsageIndex =
            (_history.length - 1).clamp(0, _history.length - 1);
      } else {
        _selectedUsageIndex = 0;
      }
    } on ApiException catch (error) {
      _error = error.message;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = colorScheme.brightness == Brightness.dark;
    final pageBg = isDark ? colorScheme.surface : AppColors.dashboardSurface;

    return Scaffold(
      backgroundColor: pageBg,
      appBar: AppBar(
        title: const Text(
          'Uso y límites',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        backgroundColor: pageBg,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        _error!,
                        style: const TextStyle(color: Colors.redAccent),
                      ),
                    ),
                  if (_subscription != null)
                    _CurrentUsageCard(subscription: _subscription!)
                  else
                    Text(
                      'No se pudo cargar el uso del plan.',
                      style: TextStyle(color: colorScheme.onSurfaceVariant),
                    ),
                  if (_history.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    Text(
                      'Uso mensual',
                      style: TextStyle(
                        color: colorScheme.onSurface,
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _MonthlyUsageSelector(
                      history: _history,
                      selectedIndex: _selectedUsageIndex.clamp(
                        0,
                        _history.length - 1,
                      ),
                      monthlyLimit: _subscription?.plan.analysesLimitMonthly,
                      onChanged: (index) {
                        setState(() => _selectedUsageIndex = index);
                      },
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}

class _CurrentUsageCard extends StatelessWidget {
  const _CurrentUsageCard({required this.subscription});

  final SubscriptionModel subscription;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = colorScheme.brightness == Brightness.dark;
    final cardBg =
        isDark ? colorScheme.surfaceContainerHighest : Colors.white;
    final trackBg =
        isDark ? colorScheme.surfaceContainerHigh : AppColors.loginFieldFill;
    final plan = subscription.plan;
    final usage = subscription.usage;
    final limit = plan.analysesLimitMonthly;
    final hasNumericLimit = limit != null && limit > 0;
    final unlimited = subscription.isUnlimited && !hasNumericLimit;
    final progress = hasNumericLimit
        ? (usage.analysesUsed / limit).clamp(0.0, 1.0)
        : null;
    final percent = progress == null ? null : (progress * 100).round();
    final barColor = usage.limitReached || (percent != null && percent >= 90)
        ? const Color(0xFFD64545)
        : (percent != null && percent >= 70)
            ? const Color(0xFFD9A406)
            : colorScheme.onSurface;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardBg,
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Plan ${plan.name}',
            style: TextStyle(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.w800,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 18),
          if (unlimited) ...[
            Text(
              'Análisis ilimitados este mes',
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ] else if (percent != null && progress != null) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Uso del mes',
                        style: TextStyle(
                          color: colorScheme.onSurfaceVariant,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  '$percent%',
                  style: TextStyle(
                    color: barColor,
                    fontWeight: FontWeight.w900,
                    fontSize: 36,
                    height: 1,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: SizedBox(
                height: 16,
                child: Stack(
                  children: [
                    Container(color: trackBg),
                    FractionallySizedBox(
                      widthFactor: progress,
                      child: Container(
                        decoration: BoxDecoration(
                          color: barColor,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '0%',
                  style: TextStyle(
                    color: colorScheme.onSurfaceVariant,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  '50%',
                  style: TextStyle(
                    color: colorScheme.onSurfaceVariant,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  '100%',
                  style: TextStyle(
                    color: colorScheme.onSurfaceVariant,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
          if (plan.maxFileMb > 0) ...[
            const SizedBox(height: 14),
            Text(
              'Máx. ${plan.maxFileMb} MB por archivo',
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: 13,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MonthlyUsageSelector extends StatelessWidget {
  const _MonthlyUsageSelector({
    required this.history,
    required this.selectedIndex,
    required this.onChanged,
    this.monthlyLimit,
  });

  final List<UsageHistoryPoint> history;
  final int selectedIndex;
  final ValueChanged<int> onChanged;
  final int? monthlyLimit;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = colorScheme.brightness == Brightness.dark;
    final cardBg =
        isDark ? colorScheme.surfaceContainerHighest : Colors.white;
    final fieldBg =
        isDark ? colorScheme.surfaceContainerHigh : const Color(0xFFF4F4F6);
    final point = history[selectedIndex];
    final hasLimit = monthlyLimit != null && monthlyLimit! > 0;
    final percent = hasLimit
        ? ((point.analysesUsed / monthlyLimit!) * 100).clamp(0, 100).round()
        : null;
    final usageLabel =
        percent != null ? '$percent%' : '${point.analysesUsed} análisis';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.06)
              : const Color(0xFFE8E8EC),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Mes',
            style: TextStyle(
              color: colorScheme.onSurfaceVariant,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: fieldBg,
              borderRadius: BorderRadius.circular(14),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                value: selectedIndex,
                isExpanded: true,
                borderRadius: BorderRadius.circular(14),
                icon: Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: colorScheme.onSurfaceVariant,
                ),
                items: [
                  for (var i = 0; i < history.length; i++)
                    DropdownMenuItem<int>(
                      value: i,
                      child: Text(
                        history[i].label,
                        style: TextStyle(
                          color: colorScheme.onSurface,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) onChanged(value);
                },
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Uso del mes',
                  style: TextStyle(
                    color: colorScheme.onSurfaceVariant,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: fieldBg,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  usageLabel,
                  style: TextStyle(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
