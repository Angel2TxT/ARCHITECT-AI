import 'dart:async';

import 'package:flutter/material.dart';
import 'package:movil_architect/core/theme/architect_theme_tokens.dart';
import 'package:movil_architect/models/billing_models.dart';

class PlanCarousel extends StatefulWidget {
  const PlanCarousel({
    super.key,
    required this.plans,
    required this.onSelect,
    this.currentPlanSlug,
    this.selectingSlug,
  });

  final List<BillingPlan> plans;
  final ValueChanged<BillingPlan> onSelect;
  final String? currentPlanSlug;
  final String? selectingSlug;

  @override
  State<PlanCarousel> createState() => _PlanCarouselState();
}

class _PlanCarouselState extends State<PlanCarousel> {
  static const _autoPlayInterval = Duration(seconds: 5);

  late final PageController _pageController;
  int _index = 0;
  Timer? _autoPlayTimer;
  bool _userInteracting = false;
  final Map<int, double> _pageHeights = {};

  List<BillingPlan> get _orderedPlans {
    final plans = widget.plans;
    final slug = widget.currentPlanSlug;
    if (slug == null || slug.isEmpty || plans.isEmpty) return plans;

    final currentIndex = plans.indexWhere((plan) => plan.slug == slug);
    if (currentIndex <= 0) return plans;

    return [
      plans[currentIndex],
      ...plans.sublist(currentIndex + 1),
      ...plans.sublist(0, currentIndex),
    ];
  }

  @override
  void initState() {
    super.initState();
    _pageController = PageController(viewportFraction: 1, initialPage: 0);
    _startAutoPlay();
  }

  void _startAutoPlay() {
    _autoPlayTimer?.cancel();
    _autoPlayTimer = Timer.periodic(_autoPlayInterval, (_) => _advance());
  }

  void _advance() {
    if (!mounted || _userInteracting || widget.selectingSlug != null) return;
    final count = _orderedPlans.length;
    if (count <= 1 || !_pageController.hasClients) return;
    final next = (_index + 1) % count;
    _pageController.animateToPage(
      next,
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _autoPlayTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant PlanCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentPlanSlug != widget.currentPlanSlug ||
        oldWidget.plans.length != widget.plans.length) {
      _index = 0;
      _pageHeights.clear();
      if (_pageController.hasClients) {
        _pageController.jumpToPage(0);
      }
    }
  }

  void _updateHeight(int pageIndex, double height) {
    if (height <= 0) return;
    final current = _pageHeights[pageIndex];
    if (current == null || (current - height).abs() > 1.0) {
      setState(() => _pageHeights[pageIndex] = height);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = ArchitectThemeTokens.of(context);
    final plans = _orderedPlans;
    if (plans.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text(
          'No hay planes disponibles.',
          style: ArchitectThemeTokens.appleText(
            color: tokens.textSecondary,
            fontSize: 14,
          ),
        ),
      );
    }

    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final targetHeight = _pageHeights[_index] ?? 500;

    return Column(
      children: [
        AnimatedContainer(
          duration: reduceMotion
              ? Duration.zero
              : const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          height: targetHeight,
          child: NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              if (notification is ScrollStartNotification &&
                  notification.dragDetails != null) {
                _userInteracting = true;
                _autoPlayTimer?.cancel();
              } else if (notification is ScrollEndNotification &&
                  _userInteracting) {
                _userInteracting = false;
                _startAutoPlay();
              }
              return false;
            },
            child: PageView.builder(
              controller: _pageController,
              itemCount: plans.length,
              onPageChanged: (value) => setState(() => _index = value),
              itemBuilder: (context, index) {
                final plan = plans[index];
                return OverflowBox(
                  minHeight: 0,
                  maxHeight: double.infinity,
                  alignment: Alignment.topCenter,
                  child: _MeasureHeight(
                    onHeight: (h) => _updateHeight(index, h),
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: PlanPricingCard(
                        plan: plan,
                        isCurrent: plan.slug == widget.currentPlanSlug,
                        isSelecting: plan.slug == widget.selectingSlug,
                        onSelect: () => widget.onSelect(plan),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        if (plans.length > 1) ...[
          const SizedBox(height: 14),
          _PageDots(
            count: plans.length,
            index: _index,
          ),
        ],
      ],
    );
  }
}

class _MeasureHeight extends StatefulWidget {
  const _MeasureHeight({required this.onHeight, required this.child});

  final ValueChanged<double> onHeight;
  final Widget child;

  @override
  State<_MeasureHeight> createState() => _MeasureHeightState();
}

class _MeasureHeightState extends State<_MeasureHeight> {
  double? _lastHeight;

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final renderObject = context.findRenderObject();
      if (renderObject is RenderBox && renderObject.hasSize) {
        final h = renderObject.size.height;
        if (_lastHeight == null || (_lastHeight! - h).abs() > 1.0) {
          _lastHeight = h;
          widget.onHeight(h);
        }
      }
    });
    return widget.child;
  }
}

class PlanPricingCard extends StatelessWidget {
  const PlanPricingCard({
    super.key,
    required this.plan,
    required this.onSelect,
    this.isCurrent = false,
    this.isSelecting = false,
  });

  final BillingPlan plan;
  final VoidCallback onSelect;
  final bool isCurrent;
  final bool isSelecting;

  @override
  Widget build(BuildContext context) {
    final tokens = ArchitectThemeTokens.of(context);
    final features = plan.displayFeatures;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: tokens.surfaceSecondary,
        borderRadius: BorderRadius.circular(ArchitectThemeTokens.radiusLg),
        border: Border.all(
          color: isCurrent
              ? tokens.accent.withValues(alpha: 0.55)
              : tokens.borderSubtle,
          width: 1,
        ),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  plan.name,
                  style: ArchitectThemeTokens.appleDisplay(
                    color: tokens.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w500,
                    height: 1.2,
                  ),
                ),
              ),
              if (isCurrent) ...[
                const SizedBox(width: 10),
                Text(
                  'Plan actual',
                  style: ArchitectThemeTokens.appleText(
                    color: tokens.accent,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                plan.priceAmountLabel,
                style: ArchitectThemeTokens.appleDisplay(
                  color: tokens.textPrimary,
                  fontSize: 40,
                  fontWeight: FontWeight.w500,
                  height: 1.05,
                ).copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
              ),
              if (!plan.isFree) ...[
                const SizedBox(width: 6),
                Text(
                  '/ mes',
                  style: ArchitectThemeTokens.appleText(
                    color: tokens.textSecondary,
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Text(
            plan.description.isEmpty
                ? 'Funciones básicas para probar la plataforma.'
                : plan.description,
            style: ArchitectThemeTokens.appleText(
              color: tokens.textSecondary,
              fontSize: 14,
              fontWeight: FontWeight.w400,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 18),
          Divider(height: 1, thickness: 1, color: tokens.borderSubtle),
          const SizedBox(height: 18),
          for (int i = 0; i < features.length; i++) ...[
            if (i > 0) const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(
                    Icons.check_rounded,
                    size: 17,
                    color: tokens.accent,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    features[i],
                    style: ArchitectThemeTokens.appleText(
                      color: tokens.textPrimary,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w400,
                      height: 1.38,
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 22),
          _PlanSelectButton(
            isCurrent: isCurrent,
            isSelecting: isSelecting,
            onPressed: isCurrent || isSelecting ? null : onSelect,
          ),
        ],
      ),
    );
  }
}

class _PlanSelectButton extends StatelessWidget {
  const _PlanSelectButton({
    required this.isCurrent,
    required this.isSelecting,
    required this.onPressed,
  });

  final bool isCurrent;
  final bool isSelecting;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final tokens = ArchitectThemeTokens.of(context);
    final label = isCurrent ? 'Plan actual' : 'Seleccionar plan';

    if (isCurrent) {
      return SizedBox(
        width: double.infinity,
        height: 48,
        child: OutlinedButton(
          onPressed: null,
          style: OutlinedButton.styleFrom(
            disabledForegroundColor: tokens.textSecondary,
            side: BorderSide(color: tokens.borderSubtle, width: 1),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(ArchitectThemeTokens.radiusMd),
            ),
          ),
          child: Text(
            label,
            style: ArchitectThemeTokens.appleText(
              color: tokens.textSecondary,
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      );
    }

    return SizedBox(
      width: double.infinity,
      height: 48,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: tokens.primaryActionBg,
          foregroundColor: tokens.primaryActionFg,
          disabledBackgroundColor:
              tokens.primaryActionBg.withValues(alpha: 0.55),
          disabledForegroundColor: tokens.primaryActionFg,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ArchitectThemeTokens.radiusMd),
          ),
        ),
        child: isSelecting
            ? SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: tokens.primaryActionFg,
                ),
              )
            : Text(
                label,
                style: ArchitectThemeTokens.appleText(
                  color: tokens.primaryActionFg,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
      ),
    );
  }
}

class _PageDots extends StatelessWidget {
  const _PageDots({required this.count, required this.index});

  final int count;
  final int index;

  @override
  Widget build(BuildContext context) {
    final tokens = ArchitectThemeTokens.of(context);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (i) {
        final active = i == index;
        return AnimatedContainer(
          duration: reduceMotion
              ? Duration.zero
              : const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          margin: const EdgeInsets.symmetric(horizontal: 3.5),
          width: active ? 16 : 6,
          height: 6,
          decoration: BoxDecoration(
            color: active
                ? tokens.accent
                : tokens.textSecondary.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(99),
          ),
        );
      }),
    );
  }
}
