import 'dart:async';

import 'package:flutter/material.dart';
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
  static const _autoPlayInterval = Duration(seconds: 4);

  late final PageController _pageController;
  int _index = 0;
  Timer? _autoPlayTimer;
  bool _userInteracting = false;

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
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeInOut,
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
    if (oldWidget.currentPlanSlug != widget.currentPlanSlug) {
      _index = 0;
      if (_pageController.hasClients) {
        _pageController.jumpToPage(0);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final plans = _orderedPlans;
    if (plans.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Text('No hay planes disponibles.'),
      );
    }

    return Column(
      children: [
        SizedBox(
          height: 460,
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
              return Padding(
                padding: const EdgeInsets.fromLTRB(6, 8, 6, 20),
                child: PlanPricingCard(
                  plan: plan,
                  isCurrent: plan.slug == widget.currentPlanSlug,
                  isSelecting: plan.slug == widget.selectingSlug,
                  onSelect: () => widget.onSelect(plan),
                ),
              );
            },
          ),
          ),
        ),
        if (plans.length > 1)
          _PageDots(
            count: plans.length,
            index: _index,
          ),
      ],
    );
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

  static const _serif = 'serif';

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = colorScheme.brightness == Brightness.dark;
    final cardColor = isDark
        ? colorScheme.surfaceContainerHighest
        : Colors.white;
    final ink = colorScheme.onSurface;
    final muted = colorScheme.onSurfaceVariant;

    return Material(
      color: cardColor,
      surfaceTintColor: Colors.transparent,
      elevation: isDark ? 0 : 4,
      shadowColor: Colors.black.withValues(alpha: 0.18),
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 28, 28, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              plan.name,
              style: TextStyle(
                fontFamily: _serif,
                fontSize: 28,
                fontWeight: FontWeight.w700,
                color: ink,
                height: 1.1,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  plan.priceAmountLabel,
                  style: TextStyle(
                    fontFamily: _serif,
                    fontSize: 48,
                    fontWeight: FontWeight.w700,
                    color: ink,
                    height: 1,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 6, bottom: 8),
                  child: Text(
                    '/mes',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: muted,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              plan.description.isEmpty
                  ? 'Funciones básicas para probar la plataforma.'
                  : plan.description,
              style: TextStyle(
                fontSize: 15,
                height: 1.4,
                color: muted,
              ),
            ),
            const SizedBox(height: 22),
            Expanded(
              child: ListView.separated(
                physics: const BouncingScrollPhysics(),
                itemCount: plan.displayFeatures.length,
                separatorBuilder: (_, _) => const SizedBox(height: 14),
                itemBuilder: (context, index) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.check, size: 20, color: ink),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          plan.displayFeatures[index],
                          style: TextStyle(
                            fontSize: 16,
                            color: ink,
                            height: 1.3,
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton(
                onPressed: isCurrent || isSelecting ? null : onSelect,
                style: OutlinedButton.styleFrom(
                  foregroundColor: ink,
                  disabledForegroundColor: muted,
                  side: BorderSide(color: ink, width: 1.2),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: isSelecting
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: ink,
                        ),
                      )
                    : Text(
                        isCurrent ? 'Plan actual' : 'Seleccionar',
                        style: TextStyle(
                          fontFamily: _serif,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: isCurrent ? muted : ink,
                        ),
                      ),
              ),
            ),
          ],
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
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (i) {
        final active = i == index;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: active ? 18 : 7,
          height: 7,
          decoration: BoxDecoration(
            color: active
                ? colorScheme.onSurface
                : colorScheme.onSurface.withValues(alpha: 0.25),
            borderRadius: BorderRadius.circular(99),
          ),
        );
      }),
    );
  }
}
