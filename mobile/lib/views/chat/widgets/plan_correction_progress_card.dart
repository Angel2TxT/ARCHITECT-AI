import 'package:flutter/material.dart';

/// Tarjeta de progreso de calibración y análisis (0% a 100%) antes de revelar el plano corregido.
class PlanCorrectionProgressCard extends StatefulWidget {
  const PlanCorrectionProgressCard({
    super.key,
    required this.onCompleted,
    this.duration = const Duration(milliseconds: 2100),
    this.detectionsCount = 0,
    this.errorsCount = 0,
  });

  final VoidCallback onCompleted;
  final Duration duration;
  final int detectionsCount;
  final int errorsCount;

  @override
  State<PlanCorrectionProgressCard> createState() =>
      _PlanCorrectionProgressCardState();
}

class _PlanCorrectionProgressCardState extends State<PlanCorrectionProgressCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;
  bool _isFinished = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    );

    _animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );

    _controller.addListener(() {
      if (mounted) setState(() {});
    });

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _finish();
      }
    });

    _controller.forward();
  }

  void _finish() {
    if (_isFinished) return;
    _isFinished = true;
    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) widget.onCompleted();
    });
  }

  void _finishInstantly() {
    if (_isFinished) return;
    _controller.stop();
    _finish();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _getPhaseText(int pct) {
    if (pct < 25) return 'Calibrando escala métrica y vanos…';
    if (pct < 55) return 'Verificando habitabilidad y normativas…';
    if (pct < 85) return 'Calculando cotas y anotaciones técnicas…';
    if (pct < 100) return 'Renderizando plano técnico en alta resolución…';
    return '✓ Plano corregido y calibrado con éxito';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = colorScheme.brightness == Brightness.dark;
    final primaryColor = isDark ? Colors.white : Colors.black;

    final progress = _animation.value;
    final pct = (progress * 100).clamp(0, 100).toInt();
    final phaseText = _getPhaseText(pct);

    return GestureDetector(
      onTap: _finishInstantly,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF161618) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark ? const Color(0x22FFFFFF) : const Color(0x18000000),
          ),
          boxShadow: [
            BoxShadow(
              color: isDark ? const Color(0x33000000) : const Color(0x0A000000),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Encabezado
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0x18FFFFFF) : const Color(0x0A000000),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.auto_awesome,
                    size: 13,
                    color: primaryColor,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Calibración técnica',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: isDark ? const Color(0xFFD1D5DB) : const Color(0xFF374151),
                    ),
                  ),
                ),
                Text(
                  '$pct%',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color: primaryColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Barra de progreso animada
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: Stack(
                children: [
                  Container(
                    height: 5,
                    width: double.infinity,
                    color: isDark ? const Color(0x1EFFFFFF) : const Color(0x0F000000),
                  ),
                  FractionallySizedBox(
                    widthFactor: progress.clamp(0.02, 1.0),
                    child: Container(
                      height: 5,
                      decoration: BoxDecoration(
                        color: primaryColor,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),

            // Texto de fase actual
            Text(
              phaseText,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: isDark ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

