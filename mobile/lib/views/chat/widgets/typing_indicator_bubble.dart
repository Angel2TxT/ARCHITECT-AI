import 'dart:async';
import 'package:flutter/material.dart';

/// Burbuja del asistente con estado de pensamiento animado (estilo Apple monocromático).
class TypingIndicatorBubble extends StatefulWidget {
  const TypingIndicatorBubble({super.key});

  @override
  State<TypingIndicatorBubble> createState() => _TypingIndicatorBubbleState();
}

class _TypingIndicatorBubbleState extends State<TypingIndicatorBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  Timer? _stepTimer;
  int _stepIndex = 0;

  static const List<String> _thinkingSteps = [
    'Pensando…',
    'Consultando normativas y habitabilidad…',
    'Analizando proporciones métricas y vanos…',
    'Sintetizando veredicto técnico…',
  ];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();

    _stepTimer = Timer.periodic(const Duration(milliseconds: 2300), (_) {
      if (mounted) {
        setState(() {
          _stepIndex = (_stepIndex + 1) % _thinkingSteps.length;
        });
      }
    });
  }

  @override
  void dispose() {
    _stepTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  double _dotOpacity(double phase) {
    if (phase < 0.5) return phase * 2;
    return (1 - phase) * 2;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = colorScheme.brightness == Brightness.dark;
    final primaryColor = isDark ? Colors.white : Colors.black;

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF161618) : Colors.white,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomRight: Radius.circular(16),
            bottomLeft: Radius.circular(4),
          ),
          border: Border.all(
            color: isDark ? const Color(0x22FFFFFF) : const Color(0x18000000),
          ),
          boxShadow: [
            BoxShadow(
              color: isDark ? const Color(0x40000000) : const Color(0x0C000000),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                final scale = 0.92 + 0.12 * (0.5 + 0.5 * _dotOpacity(_controller.value));
                return Transform.scale(
                  scale: scale,
                  child: Container(
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
                );
              },
            ),
            const SizedBox(width: 9),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              transitionBuilder: (child, animation) {
                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, 0.15),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                );
              },
              child: Text(
                _thinkingSteps[_stepIndex],
                key: ValueKey<int>(_stepIndex),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: isDark ? const Color(0xFFD1D5DB) : const Color(0xFF4B5563),
                  letterSpacing: 0.1,
                ),
              ),
            ),
            const SizedBox(width: 8),
            AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(3, (index) {
                    final phase = (_controller.value + index * 0.22) % 1.0;
                    final opacity = 0.25 + (0.75 * _dotOpacity(phase));
                    return Padding(
                      padding: EdgeInsets.only(right: index < 2 ? 4 : 0),
                      child: Opacity(
                        opacity: opacity,
                        child: Container(
                          width: 5,
                          height: 5,
                          decoration: BoxDecoration(
                            color: primaryColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    );
                  }),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
