import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:movil_architect/core/speech/speech_dictation.dart';
import 'package:movil_architect/core/utils/app_notifications.dart';

bool isPlanoImageFile(String name) {
  final ext = name.split('.').last.toLowerCase();
  return ext == 'png' || ext == 'jpg' || ext == 'jpeg' || ext == 'webp';
}

class PendingPlanoLoadingBanner extends StatelessWidget {
  const PendingPlanoLoadingBanner({
    super.key,
    required this.fileName,
    required this.progress,
    this.onCancel,
  });

  final String fileName;
  final double progress;
  final VoidCallback? onCancel;

  static const _previewSize = 72.0;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: SizedBox(
                width: _previewSize,
                height: _previewSize,
                child: ColoredBox(
                  color: colorScheme.surfaceContainerHighest,
                  child: Center(
                    child: SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(
                        value: progress > 0 ? progress : null,
                        strokeWidth: 3,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (onCancel != null)
              Positioned(
                top: -6,
                right: -6,
                child: _DismissChip(onTap: onCancel!),
              ),
          ],
        ),
      ),
    );
  }
}

class PendingPlanoBanner extends StatelessWidget {
  const PendingPlanoBanner({
    super.key,
    required this.file,
    required this.fileName,
    required this.onTap,
    required this.onDismiss,
  });

  final File file;
  final String fileName;
  final VoidCallback onTap;
  final VoidCallback onDismiss;

  static const _previewSize = 72.0;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isImage = isPlanoImageFile(fileName);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(14),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: SizedBox(
                    width: _previewSize,
                    height: _previewSize,
                    child: isImage
                        ? Image.file(file, fit: BoxFit.cover)
                        : ColoredBox(
                            color: colorScheme.surfaceContainerHighest,
                            child: Icon(
                              Icons.description_outlined,
                              color: colorScheme.onSurfaceVariant,
                              size: 32,
                            ),
                          ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: -6,
              right: -6,
              child: _DismissChip(onTap: onDismiss),
            ),
          ],
        ),
      ),
    );
  }
}

class _DismissChip extends StatelessWidget {
  const _DismissChip({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: colorScheme.surface,
      elevation: 2,
      shadowColor: Colors.black26,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(
            Icons.close_rounded,
            size: 16,
            color: colorScheme.onSurface,
          ),
        ),
      ),
    );
  }
}

class DashboardTopBar extends StatelessWidget {
  const DashboardTopBar({
    super.key,
    required this.onMenuTap,
    this.onNewChatTap,
  });

  final VoidCallback onMenuTap;
  final VoidCallback? onNewChatTap;

  @override
  Widget build(BuildContext context) {
    final iconColor = Theme.of(context).colorScheme.onSurface;

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
      child: Row(
        children: [
          IconButton(
            onPressed: onMenuTap,
            icon: Icon(Icons.menu_rounded, size: 26, color: iconColor),
          ),
          const Spacer(),
          if (onNewChatTap != null)
            IconButton(
              onPressed: onNewChatTap,
              tooltip: 'Nuevo chat',
              icon: Icon(Icons.edit_outlined, size: 24, color: iconColor),
            ),
        ],
      ),
    );
  }
}

class _WelcomeLine {
  const _WelcomeLine({
    required this.text,
    required this.darkGradientStart,
    required this.darkGradientMiddle,
    required this.darkGradientEnd,
    required this.glowColor,
    required this.eyebrowColor,
  });

  final String text;
  final Color darkGradientStart;
  final Color darkGradientMiddle;
  final Color darkGradientEnd;
  final Color glowColor;
  final Color eyebrowColor;
}

const List<_WelcomeLine> _kWelcomeLines = [
  _WelcomeLine(
    text: '¿Qué plano revisamos hoy?',
    darkGradientStart: Color(0xFFE2E8F0),
    darkGradientMiddle: Color(0xFFFFFFFF),
    darkGradientEnd: Color(0xFF94A3B8),
    glowColor: Color(0x35E2E8F0),
    eyebrowColor: Color(0xFF94A3B8),
  ),
  _WelcomeLine(
    text: '¿En qué te ayudamos hoy?',
    darkGradientStart: Color(0xFF67E8F9),
    darkGradientMiddle: Color(0xFFFFFFFF),
    darkGradientEnd: Color(0xFF22D3EE),
    glowColor: Color(0x3D22D3EE),
    eyebrowColor: Color(0xFF22D3EE),
  ),
  _WelcomeLine(
    text: 'Normativa, medidas u obra: pregunta',
    darkGradientStart: Color(0xFF6EE7B7),
    darkGradientMiddle: Color(0xFFECFDF5),
    darkGradientEnd: Color(0xFF34D399),
    glowColor: Color(0x3B34D399),
    eyebrowColor: Color(0xFF34D399),
  ),
  _WelcomeLine(
    text: 'Sube un plano y lo revisamos juntos',
    darkGradientStart: Color(0xFFBEF264),
    darkGradientMiddle: Color(0xFFF7FEE7),
    darkGradientEnd: Color(0xFF84CC16),
    glowColor: Color(0x3884CC16),
    eyebrowColor: Color(0xFFA3E635),
  ),
  _WelcomeLine(
    text: 'Tu estudio de revisión con IA',
    darkGradientStart: Color(0xFF5EEAD4),
    darkGradientMiddle: Color(0xFFFFFFFF),
    darkGradientEnd: Color(0xFF2DD4BF),
    glowColor: Color(0x3D2DD4BF),
    eyebrowColor: Color(0xFF2DD4BF),
  ),
  _WelcomeLine(
    text: '¿Listo para la siguiente revisión?',
    darkGradientStart: Color(0xFF67E8F9),
    darkGradientMiddle: Color(0xFFFFFFFF),
    darkGradientEnd: Color(0xFF38BDF8),
    glowColor: Color(0x3E38BDF8),
    eyebrowColor: Color(0xFF38BDF8),
  ),
  _WelcomeLine(
    text: 'Cuéntame qué necesitas revisar',
    darkGradientStart: Color(0xFF6EE7B7),
    darkGradientMiddle: Color(0xFFFFFFFF),
    darkGradientEnd: Color(0xFF10B981),
    glowColor: Color(0x3B10B981),
    eyebrowColor: Color(0xFF34D399),
  ),
  _WelcomeLine(
    text: 'Puertas, ventanas, normas… aquí estoy',
    darkGradientStart: Color(0xFFE2E8F0),
    darkGradientMiddle: Color(0xFFFFFFFF),
    darkGradientEnd: Color(0xFF94A3B8),
    glowColor: Color(0x35E2E8F0),
    eyebrowColor: Color(0xFFCBD5E1),
  ),
  _WelcomeLine(
    text: 'Diseñemos con precisión milimétrica',
    darkGradientStart: Color(0xFFA5B4FC),
    darkGradientMiddle: Color(0xFFFFFFFF),
    darkGradientEnd: Color(0xFF818CF8),
    glowColor: Color(0x3D818CF8),
    eyebrowColor: Color(0xFFA5B4FC),
  ),
  _WelcomeLine(
    text: 'Validemos el cumplimiento de tu proyecto',
    darkGradientStart: Color(0xFFFDE047),
    darkGradientMiddle: Color(0xFFFEF9C3),
    darkGradientEnd: Color(0xFFEAB308),
    glowColor: Color(0x38EAB308),
    eyebrowColor: Color(0xFFFACC15),
  ),
  _WelcomeLine(
    text: 'Cada detalle arquitectónico cuenta',
    darkGradientStart: Color(0xFF93C5FD),
    darkGradientMiddle: Color(0xFFEFF6FF),
    darkGradientEnd: Color(0xFF3B82F6),
    glowColor: Color(0x3B3B82F6),
    eyebrowColor: Color(0xFF60A5FA),
  ),
  _WelcomeLine(
    text: 'Tu asistente experto en planos y normas',
    darkGradientStart: Color(0xFF6EE7B7),
    darkGradientMiddle: Color(0xFFF0FDF4),
    darkGradientEnd: Color(0xFF059669),
    glowColor: Color(0x3B059669),
    eyebrowColor: Color(0xFF34D399),
  ),
];

class DashboardHero extends StatefulWidget {
  const DashboardHero({super.key, this.initialIndex});

  final int? initialIndex;

  @override
  State<DashboardHero> createState() => _DashboardHeroState();
}

class _DashboardHeroState extends State<DashboardHero>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shimmerController;
  Timer? _rotationTimer;
  late int _currentIndex;

  static int _lastInitialIndex = -1;

  static int pickDistinctIndex() {
    if (_kWelcomeLines.length <= 1) return 0;
    final random = math.Random();
    int next;
    do {
      next = random.nextInt(_kWelcomeLines.length);
    } while (next == _lastInitialIndex);
    _lastInitialIndex = next;
    return next;
  }

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex ?? pickDistinctIndex();
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 5500),
    )..repeat();

    _startRotationTimer();
  }

  void _startRotationTimer() {
    _rotationTimer?.cancel();
    _rotationTimer = Timer.periodic(const Duration(seconds: 6), (_) {
      if (!mounted) return;
      setState(() {
        _currentIndex = (_currentIndex + 1) % _kWelcomeLines.length;
      });
    });
  }

  void _advancePrompt() {
    if (!mounted) return;
    setState(() {
      _currentIndex = (_currentIndex + 1) % _kWelcomeLines.length;
    });
    _startRotationTimer();
  }

  @override
  void dispose() {
    _rotationTimer?.cancel();
    _shimmerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = colorScheme.brightness == Brightness.dark;
    final line = _kWelcomeLines[_currentIndex];

    return GestureDetector(
      onTap: _advancePrompt,
      behavior: HitTestBehavior.opaque,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Rotating title with glow and shimmer
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 550),
                switchInCurve: const Cubic(0.22, 1.0, 0.36, 1.0),
                switchOutCurve: Curves.easeIn,
                transitionBuilder: (child, animation) {
                  return FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, 0.10),
                        end: Offset.zero,
                      ).animate(animation),
                      child: child,
                    ),
                  );
                },
                child: Stack(
                  key: ValueKey('title_$_currentIndex'),
                  alignment: Alignment.center,
                  children: [
                    if (isDark)
                      Positioned(
                        child: Container(
                          width: 220,
                          height: 70,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: line.glowColor.withValues(alpha: 0.22),
                                blurRadius: 45,
                                spreadRadius: 10,
                              ),
                            ],
                          ),
                        ),
                      ),
                    AnimatedBuilder(
                      animation: _shimmerController,
                      builder: (context, _) {
                        return ShaderMask(
                          blendMode: BlendMode.srcIn,
                          shaderCallback: (bounds) {
                            if (bounds.isEmpty) {
                              return const LinearGradient(
                                colors: [Colors.white, Colors.white],
                              ).createShader(bounds);
                            }
                            final shift = _shimmerController.value;
                            if (isDark) {
                              return LinearGradient(
                                begin: Alignment(-1.8 + shift * 2.8, -0.2),
                                end: Alignment(0.6 + shift * 2.8, 0.2),
                                colors: [
                                  line.darkGradientStart,
                                  line.darkGradientMiddle,
                                  line.darkGradientEnd,
                                  line.darkGradientStart,
                                ],
                                stops: const [0.0, 0.45, 0.75, 1.0],
                              ).createShader(bounds);
                            } else {
                              return LinearGradient(
                                begin: Alignment(-1.8 + shift * 2.8, -0.2),
                                end: Alignment(0.6 + shift * 2.8, 0.2),
                                colors: const [
                                  Color(0xFF0F172A),
                                  Color(0xFF334155),
                                  Color(0xFF0F172A),
                                ],
                                stops: const [0.0, 0.5, 1.0],
                              ).createShader(bounds);
                            }
                          },
                          child: Text(
                            line.text,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 27,
                              fontWeight: FontWeight.w800,
                              height: 1.20,
                              letterSpacing: -0.5,
                              color: Colors.white,
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BorderBeamPainter extends CustomPainter {
  const _BorderBeamPainter({
    required this.progress,
    required this.isDark,
    required this.isFocused,
    required this.isBusy,
  });

  final double progress;
  final bool isDark;
  final bool isFocused;
  final bool isBusy;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final strokeWidth = isFocused ? 2.2 : (isBusy ? 2.0 : 1.5);
    final halfStroke = strokeWidth / 2;
    final strokeRect = Rect.fromLTWH(
      halfStroke,
      halfStroke,
      math.max(0.0, size.width - strokeWidth),
      math.max(0.0, size.height - strokeWidth),
    );
    final strokeRRect = RRect.fromRectAndRadius(
      strokeRect,
      Radius.circular(strokeRect.height / 2),
    );

    // 1. Base subtle border outline
    final baseBorderColor = isDark
        ? (isFocused ? const Color(0xFF4A4A52) : const Color(0xFF2E2E34))
        : (isFocused ? const Color(0xFF94A3B8) : const Color(0xFFCBD5E1));

    final basePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = baseBorderColor;
    canvas.drawRRect(strokeRRect, basePaint);

    // 2. Rotating beam gradient
    final rotationAngle = progress * 2 * math.pi;
    final colors = isDark
        ? const [
            Colors.transparent,
            Colors.transparent,
            Color(0x22FFFFFF),
            Color(0xFFFFFFFF),
            Color(0xFFCBD5E1),
            Color(0x5594A3B8),
            Colors.transparent,
          ]
        : const [
            Colors.transparent,
            Colors.transparent,
            Color(0x15000000),
            Color(0xFF0F172A),
            Color(0xFF334155),
            Color(0x3364748B),
            Colors.transparent,
          ];

    final stops = const [0.0, 0.48, 0.62, 0.76, 0.86, 0.94, 1.0];

    final beamGradient = SweepGradient(
      center: Alignment.center,
      startAngle: 0.0,
      endAngle: math.pi * 2,
      transform: GradientRotation(rotationAngle),
      colors: colors,
      stops: stops,
    );

    // 3. Glowing aura in dark mode or on focus/busy
    if (isDark || isFocused || isBusy) {
      final glowPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth + (isFocused ? 3.0 : 1.8)
        ..maskFilter = MaskFilter.blur(
          BlurStyle.normal,
          isFocused ? 5.0 : 3.0,
        )
        ..shader = beamGradient.createShader(strokeRect);
      canvas.drawRRect(strokeRRect, glowPaint);
    }

    // 4. Sharp beam stroke
    final beamPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..shader = beamGradient.createShader(strokeRect);
    canvas.drawRRect(strokeRRect, beamPaint);
  }

  @override
  bool shouldRepaint(covariant _BorderBeamPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.isDark != isDark ||
        oldDelegate.isFocused != isFocused ||
        oldDelegate.isBusy != isBusy;
  }
}

class DashboardAskBar extends StatefulWidget {
  const DashboardAskBar({
    super.key,
    required this.controller,
    this.onAttachTap,
    this.onSendTap,
    this.isSending = false,
    this.hintText = '',
  });

  final TextEditingController controller;
  final VoidCallback? onAttachTap;
  final VoidCallback? onSendTap;
  final bool isSending;
  final String hintText;

  @override
  State<DashboardAskBar> createState() => _DashboardAskBarState();
}

class _DashboardAskBarState extends State<DashboardAskBar>
    with SingleTickerProviderStateMixin {
  late final FocusNode _focusNode;
  late final SpeechDictationController _dictation;
  late final AnimationController _beamController;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    _focusNode.addListener(_onFocusChanged);
    _beamController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3400),
    )..repeat();

    _dictation = SpeechDictationController(
      onListeningChanged: (_) {
        if (mounted) setState(() {});
      },
      onError: (message) {
        if (!mounted) return;
        AppNotifications.error(context, message);
      },
    );
  }

  void _onFocusChanged() {
    _updateBeamSpeed();
  }

  @override
  void didUpdateWidget(covariant DashboardAskBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isSending != oldWidget.isSending) {
      _updateBeamSpeed();
    }
  }

  void _updateBeamSpeed() {
    final targetDuration = widget.isSending
        ? const Duration(milliseconds: 1850)
        : (_focusNode.hasFocus
            ? const Duration(milliseconds: 2400)
            : const Duration(milliseconds: 3400));
    if (_beamController.duration != targetDuration) {
      _beamController.duration = targetDuration;
      if (!_beamController.isAnimating) {
        _beamController.repeat();
      }
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChanged);
    _beamController.dispose();
    _dictation.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _focusField() {
    if (widget.isSending) return;
    _focusNode.requestFocus();
  }

  Future<void> _toggleDictation() async {
    if (widget.isSending) return;
    await _dictation.toggle(
      currentText: widget.controller.text,
      onText: (text) {
        widget.controller.value = TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(offset: text.length),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = colorScheme.brightness == Brightness.dark;
    final barColor = isDark
        ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.95)
        : const Color(0xF0FFFFFF);
    final isFocused = _focusNode.hasFocus;

    return Container(
      height: 56,
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: AnimatedBuilder(
        animation: _beamController,
        builder: (context, child) {
          return CustomPaint(
            foregroundPainter: _BorderBeamPainter(
              progress: _beamController.value,
              isDark: isDark,
              isFocused: isFocused,
              isBusy: widget.isSending,
            ),
            child: child,
          );
        },
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
          decoration: BoxDecoration(
            color: barColor,
            borderRadius: BorderRadius.circular(999),
            boxShadow: [
              BoxShadow(
                color: colorScheme.shadow.withValues(alpha: isDark ? 0.25 : 0.08),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: widget.onAttachTap,
                  borderRadius: BorderRadius.circular(999),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Icon(
                      Icons.attach_file_rounded,
                      color: colorScheme.onSurfaceVariant,
                      size: 23,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _focusField,
                  child: TextField(
                    focusNode: _focusNode,
                    controller: widget.controller,
                    enabled: !widget.isSending,
                    readOnly: false,
                    enableInteractiveSelection: true,
                    keyboardType: TextInputType.text,
                    textCapitalization: TextCapitalization.sentences,
                    textInputAction: TextInputAction.send,
                    onSubmitted: widget.isSending
                        ? null
                        : (_) => widget.onSendTap?.call(),
                    style: TextStyle(
                      color: colorScheme.onSurface,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                    decoration: InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      hintText: widget.hintText,
                      hintStyle: TextStyle(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 14,
                      ),
                    ),
                  ),
                ),
              ),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: widget.isSending ? null : _toggleDictation,
                  borderRadius: BorderRadius.circular(999),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Icon(
                      _dictation.isListening
                          ? Icons.mic_rounded
                          : Icons.mic_none_rounded,
                      color: _dictation.isListening
                          ? Colors.red
                          : colorScheme.onSurfaceVariant,
                      size: 23,
                    ),
                  ),
                ),
              ),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: widget.isSending ? null : widget.onSendTap,
                  borderRadius: BorderRadius.circular(999),
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: isDark ? colorScheme.onSurface : Colors.black,
                      shape: BoxShape.circle,
                    ),
                    child: widget.isSending
                        ? Padding(
                            padding: const EdgeInsets.all(14),
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: isDark
                                  ? colorScheme.surface
                                  : Colors.white,
                            ),
                          )
                        : Icon(
                            Icons.arrow_upward_rounded,
                            color: isDark ? colorScheme.surface : Colors.white,
                            size: 26,
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
