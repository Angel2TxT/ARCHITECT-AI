import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:movil_architect/views/shared/markdown_text.dart';

/// Renderiza texto con animación progresiva de mecanografía (estilo Apple).
/// Si el usuario toca el texto, se muestra completo al instante.
class TypewriterText extends StatefulWidget {
  const TypewriterText({
    super.key,
    required this.data,
    this.style,
    this.animate = false,
    this.onCompleted,
  });

  final String data;
  final TextStyle? style;
  final bool animate;
  final VoidCallback? onCompleted;

  @override
  State<TypewriterText> createState() => _TypewriterTextState();
}

class _TypewriterTextState extends State<TypewriterText> {
  Timer? _timer;
  int _charIndex = 0;
  bool _isFinished = false;

  @override
  void initState() {
    super.initState();
    if (widget.animate && widget.data.isNotEmpty) {
      _startTyping();
    } else {
      _charIndex = widget.data.length;
      _isFinished = true;
    }
  }

  @override
  void didUpdateWidget(TypewriterText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data != widget.data) {
      _timer?.cancel();
      if (widget.animate) {
        _charIndex = 0;
        _isFinished = false;
        _startTyping();
      } else {
        _charIndex = widget.data.length;
        _isFinished = true;
      }
    }
  }

  void _startTyping() {
    final length = widget.data.length;
    // Calibración de ritmo para que sea visible, fluido y no excesivamente lento
    final isShort = length < 140;
    final charsPerTick = isShort ? 1 : 2;
    final tickInterval = Duration(milliseconds: isShort ? 24 : 22);

    _timer = Timer.periodic(tickInterval, (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _charIndex = math.min(_charIndex + charsPerTick, length);
        if (_charIndex >= length) {
          timer.cancel();
          _isFinished = true;
          widget.onCompleted?.call();
        }
      });
    });
  }

  void _finishInstantly() {
    if (_isFinished) return;
    _timer?.cancel();
    setState(() {
      _charIndex = widget.data.length;
      _isFinished = true;
    });
    widget.onCompleted?.call();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final baseStyle = widget.style ??
        TextStyle(
          color: Theme.of(context).colorScheme.onSurface,
          height: 1.45,
          fontSize: 14,
        );

    if (_isFinished || !widget.animate) {
      return MarkdownText(
        data: widget.data,
        style: baseStyle,
      );
    }

    final currentSlice = widget.data.substring(0, _charIndex);

    return GestureDetector(
      onTap: _finishInstantly,
      behavior: HitTestBehavior.opaque,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          MarkdownText(
            data: currentSlice,
            style: baseStyle,
          ),
          Positioned(
            right: -6,
            bottom: 0,
            child: Text(
              '│',
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w700,
                fontSize: baseStyle.fontSize,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

