import 'package:flutter/material.dart';

/// Bloque gris animado (shimmer) para pantallas de carga.
class SkeletonBox extends StatefulWidget {
  const SkeletonBox({
    super.key,
    this.width,
    this.height = 14,
    this.borderRadius = 8,
  });

  final double? width;
  final double height;
  final double borderRadius;

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
    _opacity = Tween<double>(begin: 0.35, end: 0.75).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final base = scheme.brightness == Brightness.dark
        ? scheme.surfaceContainerHighest
        : const Color(0xFFE0E0E2);

    return FadeTransition(
      opacity: _opacity,
      child: Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: base,
          borderRadius: BorderRadius.circular(widget.borderRadius),
        ),
      ),
    );
  }
}

/// Skeleton del historial de chats (drawer).
class ChatHistorySkeleton extends StatelessWidget {
  const ChatHistorySkeleton({super.key, this.itemCount = 6});

  final int itemCount;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 8),
      itemCount: itemCount,
      itemBuilder: (context, index) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonBox(
                  width: 140 + (index % 3) * 28.0,
                  height: 15,
                  borderRadius: 6,
                ),
                const SizedBox(height: 8),
                SkeletonBox(
                  width: 70 + (index % 2) * 20.0,
                  height: 12,
                  borderRadius: 6,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Skeleton de la lista de proyectos Casa hogar.
class HomeProjectsListSkeleton extends StatelessWidget {
  const HomeProjectsListSkeleton({super.key, this.itemCount = 4});

  final int itemCount;

  @override
  Widget build(BuildContext context) {
    final cardColor = Theme.of(context).cardColor;

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
      itemCount: itemCount,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return Container(
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isDark ? const Color(0xFF2E2E34) : const Color(0xFFD0D5DD),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: isDark
                    ? Colors.black.withValues(alpha: 0.3)
                    : Colors.black.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: SkeletonBox(
                        height: 17,
                        borderRadius: 6,
                        width: 160 + (index % 2) * 40.0,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const SkeletonBox(width: 72, height: 22, borderRadius: 999),
                  ],
                ),
                const SizedBox(height: 12),
                SkeletonBox(
                  width: 120 + (index % 3) * 24.0,
                  height: 13,
                  borderRadius: 6,
                ),
                const SizedBox(height: 8),
                const SkeletonBox(width: 180, height: 12, borderRadius: 6),
                const SizedBox(height: 16),
                const SkeletonBox(width: 90, height: 13, borderRadius: 6),
                const SizedBox(height: 10),
                const SkeletonBox(
                  width: double.infinity,
                  height: 8,
                  borderRadius: 999,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Skeleton del detalle de proyecto (etapas / info Casa hogar).
class HomeProjectDetailSkeleton extends StatelessWidget {
  const HomeProjectDetailSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final cardColor = Theme.of(context).cardColor;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        const Row(
          children: [
            SkeletonBox(width: 80, height: 24, borderRadius: 999),
            Spacer(),
            SkeletonBox(width: 70, height: 14, borderRadius: 6),
          ],
        ),
        const SizedBox(height: 16),
        const SkeletonBox(width: 180, height: 16, borderRadius: 6),
        const SizedBox(height: 10),
        const SkeletonBox(width: 220, height: 13, borderRadius: 6),
        const SizedBox(height: 12),
        const SkeletonBox(
          width: double.infinity,
          height: 13,
          borderRadius: 6,
        ),
        const SizedBox(height: 6),
        const SkeletonBox(width: 260, height: 13, borderRadius: 6),
        const SizedBox(height: 20),
        const SkeletonBox(width: 210, height: 13, borderRadius: 6),
        const SizedBox(height: 10),
        const SkeletonBox(
          width: double.infinity,
          height: 8,
          borderRadius: 999,
        ),
        const SizedBox(height: 20),
        const SkeletonBox(
          width: double.infinity,
          height: 48,
          borderRadius: 14,
        ),
        const SizedBox(height: 28),
        const SkeletonBox(width: 80, height: 18, borderRadius: 6),
        const SizedBox(height: 14),
        SizedBox(
          height: 44,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: 9,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (_, _) => const SkeletonBox(
              width: 44,
              height: 36,
              borderRadius: 999,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Material(
          color: cardColor,
          borderRadius: BorderRadius.circular(20),
          child: const Padding(
            padding: EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: SkeletonBox(height: 17, borderRadius: 6),
                    ),
                    SizedBox(width: 10),
                    SkeletonBox(width: 72, height: 22, borderRadius: 999),
                  ],
                ),
                SizedBox(height: 12),
                SkeletonBox(
                  width: double.infinity,
                  height: 13,
                  borderRadius: 6,
                ),
                SizedBox(height: 6),
                SkeletonBox(width: 200, height: 13, borderRadius: 6),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        const Row(
          children: [
            Expanded(
              child: SkeletonBox(width: 100, height: 16, borderRadius: 6),
            ),
            SkeletonBox(width: 40, height: 14, borderRadius: 6),
          ],
        ),
        const SizedBox(height: 12),
        for (var i = 0; i < 4; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          Material(
            color: cardColor,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  const SkeletonBox(width: 36, height: 36, borderRadius: 999),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SkeletonBox(
                          width: 140 + (i % 3) * 20.0,
                          height: 14,
                          borderRadius: 6,
                        ),
                        const SizedBox(height: 8),
                        const SkeletonBox(
                          width: double.infinity,
                          height: 6,
                          borderRadius: 999,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}
