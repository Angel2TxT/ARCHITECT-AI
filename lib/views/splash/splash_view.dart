import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:movil_architect/controllers/splash_controller.dart';
import 'package:movil_architect/core/app_services.dart';
import 'package:movil_architect/core/config/app_config.dart';
import 'package:movil_architect/views/dashboard/dashboard_view.dart';
import 'package:movil_architect/views/login/login_view.dart';
import 'package:movil_architect/views/login/widgets/login_widgets.dart';

/// Pantalla de bienvenida (Splash Screen) animada estilo iOS para ARCHITECT.
///
/// Características principales:
/// - Estética minimalista iOS: espacio negativo amplio, fondo claro `#F7F7F8`, sombras suaves.
/// - Construcción progresiva del isotipo arquitectónico desde líneas técnicas hasta el volumen 3D:
///   1. Fase 1: Líneas técnicas CAD de plano (trazado progresivo con PathMetric)
///   2. Fase 2: Trazado del contorno estructural y arco perimetral dorado
///   3. Fase 3: Elevación y construcción de los volúmenes de las torres y panel dorado
///   4. Fase 4: Micro-asentamiento, desvanecimiento de líneas guía y reflejo dorado sutil
///   5. Fase 5: Aparición tipográfica de la marca ARCHITECT
///   6. Fase 6: Indicador de carga circular minimalista estilo iOS
/// - Sincronización coordinada y no bloqueante con [SplashController.bootstrap()].
class SplashView extends StatefulWidget {
  const SplashView({super.key});

  @override
  State<SplashView> createState() => _SplashViewState();
}

class _SplashViewState extends State<SplashView>
    with SingleTickerProviderStateMixin {
  late final SplashController _controller;
  late final TextEditingController _urlController;
  late final AnimationController _animController;

  // Intervalos y fases de la animación
  // Fase 1: Líneas técnicas de plano CAD
  late final Animation<double> _blueprintLinesProgress;
  late final Animation<double> _blueprintOpacity;

  // Fase 2: Contornos estructurales y arco perimetral dorado
  late final Animation<double> _goldenArcProgress;
  late final Animation<double> _outlineProgress;

  // Fase 3: Construcción de las torres y volúmenes arquitectónicos
  late final Animation<double> _towerRiseProgress;
  late final Animation<double> _facetLeftProgress;
  late final Animation<double> _facetRightProgress;
  late final Animation<double> _goldFacetProgress;

  // Fase 4: Asentamiento final, reflejo dorado y desvanecimiento de guías
  late final Animation<double> _guidelinesFadeOut;
  late final Animation<double> _settleScale;
  late final Animation<double> _goldSheenProgress;

  // Fase 5: Tipografía de la marca ARCHITECT
  late final Animation<double> _brandOpacity;
  late final Animation<Offset> _brandSlide;

  // Fase 6: Indicador de actividad circular minimalista estilo iOS
  late final Animation<double> _indicatorOpacity;

  bool _navigating = false;
  bool _savingUrl = false;
  bool _bootstrapFinished = false;

  @override
  void initState() {
    super.initState();
    _controller = SplashController();
    _urlController = TextEditingController(
      text: AppServices.instance.apiClient.dio.options.baseUrl,
    );

    _initAnimation();
    _startBootstrap();
  }

  void _initAnimation() {
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3500),
    );

    // Fase 1: Líneas técnicas CAD (0.0s - 0.4s)
    _blueprintLinesProgress = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animController,
        curve: const Interval(0.0, 0.16, curve: Curves.easeOutCubic),
      ),
    );
    _blueprintOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animController,
        curve: const Interval(0.0, 0.08, curve: Curves.easeOut),
      ),
    );

    // Fase 2: Contornos estructurales y arco dorado (0.3s - 0.8s)
    _goldenArcProgress = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animController,
        curve: const Interval(0.12, 0.32, curve: Curves.easeInOutCubic),
      ),
    );
    _outlineProgress = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animController,
        curve: const Interval(0.14, 0.34, curve: Curves.easeOutCubic),
      ),
    );

    // Fase 3: Construcción de volúmenes de las torres (0.6s - 1.5s)
    // Torre izquierda de hormigón
    _facetLeftProgress = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animController,
        curve: const Interval(0.24, 0.46, curve: Curves.easeOutCubic),
      ),
    );
    // Torre central carbón (aguja principal)
    _towerRiseProgress = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animController,
        curve: const Interval(0.28, 0.52, curve: Curves.easeOutCubic),
      ),
    );
    // Espina estructural derecha en blanco
    _facetRightProgress = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animController,
        curve: const Interval(0.34, 0.56, curve: Curves.easeOutCubic),
      ),
    );
    // Panel interior dorado
    _goldFacetProgress = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animController,
        curve: const Interval(0.38, 0.60, curve: Curves.easeOutCubic),
      ),
    );

    // Fase 4: Asentamiento y acabado pulido (1.4s - 1.9s)
    _guidelinesFadeOut = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _animController,
        curve: const Interval(0.56, 0.72, curve: Curves.easeInOut),
      ),
    );
    _settleScale =
        TweenSequence<double>([
          TweenSequenceItem(
            tween: Tween<double>(
              begin: 0.96,
              end: 1.015,
            ).chain(CurveTween(curve: Curves.easeOutCubic)),
            weight: 60,
          ),
          TweenSequenceItem(
            tween: Tween<double>(
              begin: 1.015,
              end: 1.0,
            ).chain(CurveTween(curve: Curves.easeInOutCubic)),
            weight: 40,
          ),
        ]).animate(
          CurvedAnimation(
            parent: _animController,
            curve: const Interval(0.52, 0.78),
          ),
        );
    _goldSheenProgress = Tween<double>(begin: -0.3, end: 1.3).animate(
      CurvedAnimation(
        parent: _animController,
        curve: const Interval(0.60, 0.76, curve: Curves.easeInOutCubic),
      ),
    );

    // Fase 5: Tipografía de marca (1.8s - 2.2s)
    _brandOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animController,
        curve: const Interval(0.72, 0.86, curve: Curves.easeOut),
      ),
    );
    _brandSlide =
        Tween<Offset>(begin: const Offset(0.0, 0.20), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _animController,
            curve: const Interval(0.72, 0.88, curve: Curves.easeOutCubic),
          ),
        );

    // Fase 6: Indicador de actividad circular estilo iOS (2.2s - 2.5s)
    _indicatorOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animController,
        curve: const Interval(0.88, 1.0, curve: Curves.easeOut),
      ),
    );

    _animController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _checkAndNavigate();
      }
    });

    _animController.forward();
  }

  Future<void> _startBootstrap() async {
    await _controller.bootstrap();
    if (!mounted) return;
    _bootstrapFinished = true;
    _checkAndNavigate();
  }

  void _checkAndNavigate() {
    if (!mounted || _navigating) return;

    if (_controller.status == SplashStatus.serverError) {
      if (_animController.isCompleted) {
        _urlController.text =
            AppServices.instance.apiClient.dio.options.baseUrl;
        setState(() {});
      }
      return;
    }

    // Navegar únicamente cuando tanto la animación como la inicialización del backend hayan concluido
    if (_animController.isCompleted && _bootstrapFinished) {
      final status = _controller.status;
      if (status == SplashStatus.readyDashboard) {
        _goTo(const DashboardView());
      } else if (status == SplashStatus.readyLogin) {
        _goTo(const LoginView());
      }
    }
  }

  void _goTo(Widget page) {
    if (_navigating || !mounted) return;
    _navigating = true;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        pageBuilder: (context, animation, secondaryAnimation) => page,
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: CurvedAnimation(
              parent: animation,
              curve: Curves.easeInOutCubic,
            ),
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 380),
      ),
    );
  }

  Future<void> _saveServerAndRetry() async {
    final resolved = AppConfig.resolveForPlatform(_urlController.text.trim());
    if (resolved.isEmpty) return;

    setState(() => _savingUrl = true);
    try {
      await AppServices.instance.apiClient.setBaseUrl(resolved);
      _urlController.text = resolved;
      _navigating = false;
      _bootstrapFinished = false;
      await _startBootstrap();
    } finally {
      if (mounted) setState(() => _savingUrl = false);
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    _urlController.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F8),
      body: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) {
          if (_controller.status == SplashStatus.serverError &&
              _animController.isCompleted) {
            return _serverErrorContent();
          }

          return _animatedSplashContent();
        },
      ),
    );
  }

  Widget _animatedSplashContent() {
    // Colores de la paleta arquitectónica iOS
    const Color charcoalText = Color(0xFF29252A);
    const Color buildingCharcoal = Color(0xFF1F2A32);
    const Color goldAccent = Color(0xFFD9A441);
    const Color blueprintGuideline = Color(0xFF8A939E);

    return SafeArea(
      child: Center(
        child: SingleChildScrollView(
          physics: const NeverScrollableScrollPhysics(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 1. Lienzo de construcción vectorial del isotipo
              AnimatedBuilder(
                animation: _animController,
                builder: (context, child) {
                  return Transform.scale(
                    scale: _settleScale.value,
                    child: SizedBox(
                      width: 220,
                      height: 220,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // Trazado de líneas CAD, arco dorado y volúmenes estructurales
                          CustomPaint(
                            size: const Size(220, 220),
                            painter: _ArchitecturalEmblemPainter(
                              blueprintProgress: _blueprintLinesProgress.value,
                              blueprintOpacity: _blueprintOpacity.value,
                              guidelinesFade: _guidelinesFadeOut.value,
                              arcProgress: _goldenArcProgress.value,
                              outlineProgress: _outlineProgress.value,
                              leftFacetProgress: _facetLeftProgress.value,
                              towerRiseProgress: _towerRiseProgress.value,
                              rightFacetProgress: _facetRightProgress.value,
                              goldFacetProgress: _goldFacetProgress.value,
                              goldSheenProgress: _goldSheenProgress.value,
                              buildingColor: buildingCharcoal,
                              goldColor: goldAccent,
                              guidelineColor: blueprintGuideline,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),

              const SizedBox(height: 28),

              // 2. Tipografía de marca: ARCHITECT
              SlideTransition(
                position: _brandSlide,
                child: FadeTransition(
                  opacity: _brandOpacity,
                  child: const Text(
                    'ARCHITECT',
                    style: TextStyle(
                      color: charcoalText,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 7.5,
                      fontFamily:
                          '.SF Pro Text', // Fuente del sistema iOS como alternativa
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 38),

              // 3. Indicador de actividad circular minimalista estilo iOS
              FadeTransition(
                opacity: _indicatorOpacity,
                child: const SizedBox(
                  width: 20,
                  height: 20,
                  child: _IosMinimalSpinner(
                    trackColor: Color(0xFFE2E4E8),
                    accentColor: goldAccent,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _serverErrorContent() {
    final colorScheme = Theme.of(context).colorScheme;
    final message =
        _controller.errorMessage ?? 'No se pudo conectar al servidor';

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          children: [
            const SizedBox(height: 24),
            Icon(
              Icons.cloud_off_rounded,
              size: 52,
              color: colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colorScheme.onSurface,
                fontSize: 16,
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'En teléfono físico usa la IP de tu PC, por ejemplo:\n'
              'http://192.168.0.104:8000\n'
              '(misma red Wi‑Fi; no uses 10.0.2.2 ni localhost)',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: 13,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 22),
            LoginPillField(
              controller: _urlController,
              hint: 'URL DEL SERVIDOR',
              keyboardType: TextInputType.url,
              autocorrect: false,
            ),
            const SizedBox(height: 14),
            LoginPrimaryButton(
              label: 'Guardar y conectar',
              isLoading: _savingUrl,
              onPressed: _savingUrl ? null : _saveServerAndRetry,
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: _savingUrl ? null : _saveServerAndRetry,
              child: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Pintor personalizado para animar la construcción vectorial del edificio
/// según la geometría oficial del isotipo de ARCHITECT.
class _ArchitecturalEmblemPainter extends CustomPainter {
  const _ArchitecturalEmblemPainter({
    required this.blueprintProgress,
    required this.blueprintOpacity,
    required this.guidelinesFade,
    required this.arcProgress,
    required this.outlineProgress,
    required this.leftFacetProgress,
    required this.towerRiseProgress,
    required this.rightFacetProgress,
    required this.goldFacetProgress,
    required this.goldSheenProgress,
    required this.buildingColor,
    required this.goldColor,
    required this.guidelineColor,
  });

  final double blueprintProgress;
  final double blueprintOpacity;
  final double guidelinesFade;
  final double arcProgress;
  final double outlineProgress;
  final double leftFacetProgress;
  final double towerRiseProgress;
  final double rightFacetProgress;
  final double goldFacetProgress;
  final double goldSheenProgress;

  final Color buildingColor;
  final Color goldColor;
  final Color guidelineColor;

  @override
  void paint(Canvas canvas, Size size) {
    // Normalización del lienzo: marco de coordenadas de referencia 220 x 220
    final w = size.width;
    final scale = w / 220.0;

    canvas.save();
    canvas.scale(scale, scale);

    final center = Offset(110, 110);

    // ==========================================================
    // 1. LÍNEAS TÉCNICAS CAD DE PLANO (Fase 1: 0.0 - 0.4s)
    // ==========================================================
    if (guidelinesFade > 0.0 && blueprintProgress > 0.0) {
      final effectiveOpacity =
          blueprintOpacity * guidelinesFade.clamp(0.0, 1.0);
      final guidePaint = Paint()
        ..color = guidelineColor.withValues(alpha: effectiveOpacity * 0.45)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0;

      // Línea base técnica horizontal (cimentación)
      final groundLength = 175.0 * blueprintProgress;
      canvas.drawLine(
        const Offset(18, 185),
        Offset(18 + groundLength, 185),
        guidePaint,
      );

      // Eje vertical derecho de alineación y agrimensura
      final vertLength = 130.0 * blueprintProgress;
      canvas.drawLine(
        Offset(185, 195 - vertLength),
        const Offset(185, 195),
        guidePaint,
      );

      // Cota horizontal técnica derecha
      if (blueprintProgress > 0.5) {
        final crossTickProg = (blueprintProgress - 0.5) / 0.5;
        canvas.drawLine(
          const Offset(160, 146),
          Offset(160 + (48 * crossTickProg), 146),
          guidePaint,
        );
        // Pequeño nodo dorado de cota en la intersección (185, 146)
        if (blueprintProgress > 0.8) {
          final nodePaint = Paint()
            ..color = goldColor.withValues(alpha: effectiveOpacity * 0.9)
            ..style = PaintingStyle.fill;
          canvas.drawCircle(const Offset(185, 146), 2.2, nodePaint);
        }
      }

      // Guía diagonal técnica de 45 grados en la parte inferior izquierda
      if (blueprintProgress > 0.3) {
        final diagProg = (blueprintProgress - 0.3) / 0.7;
        canvas.drawLine(
          const Offset(22, 192),
          Offset(22 + (45 * diagProg), 192 - (45 * diagProg)),
          guidePaint,
        );
      }
    }

    // ==========================================================
    // 2. ARCO ARQUITECTÓNICO DORADO (Fase 2: 0.3 - 0.8s)
    // ==========================================================
    if (arcProgress > 0.0) {
      final arcRadius = 70.0;
      final arcRect = Rect.fromCircle(center: center, radius: arcRadius);

      final arcPaint = Paint()
        ..color = goldColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.2
        ..strokeCap = StrokeCap.round;

      // El arco se traza suavemente en sentido horario de -135 a +45 grados
      const startAngle = -math.pi * 0.75;
      final sweepAngle = (math.pi * 1.5) * arcProgress;

      canvas.drawArc(arcRect, startAngle, sweepAngle, false, arcPaint);
    }

    // ==========================================================
    // 3. VOLÚMENES Y FACETAS ARQUITECTÓNICAS (Fase 3: 0.6 - 1.5s)
    // ==========================================================

    // --- Volumen A: Torre izquierda de hormigón (gris claro) ---
    // Geometría: polígono desde la base (79, 185) hasta el pico (108, 59)
    if (leftFacetProgress > 0.0) {
      canvas.save();
      // Recorte de abajo hacia arriba a medida que se eleva
      final clipTop = 185 - (126 * leftFacetProgress);
      canvas.clipRect(Rect.fromLTRB(75, clipTop, 110, 190));

      final leftTowerPath = Path()
        ..moveTo(79, 185)
        ..lineTo(79, 81)
        ..lineTo(107, 59)
        ..lineTo(107, 185)
        ..close();

      // Color gris piedra arquitectónico
      final leftTowerPaint = Paint()
        ..color = const Color(0xFFC7CBD1)
        ..style = PaintingStyle.fill;
      canvas.drawPath(leftTowerPath, leftTowerPaint);

      // Línea de sombra vertical que separa el volumen izquierdo del central
      final shadowLinePaint = Paint()
        ..color = buildingColor.withValues(alpha: 0.35)
        ..strokeWidth = 1.0
        ..style = PaintingStyle.stroke;
      canvas.drawLine(
        const Offset(107, 59),
        const Offset(107, 185),
        shadowLinePaint,
      );

      canvas.restore();
    }

    // --- Volumen B: Torre central oscura (aguja principal) ---
    // Geometría: polígono desde (112, 185) hasta aguja (112, 24), (154, 66) y (154, 185)
    if (towerRiseProgress > 0.0) {
      canvas.save();
      final clipTop = 185 - (161 * towerRiseProgress);
      canvas.clipRect(Rect.fromLTRB(108, clipTop, 156, 190));

      final mainTowerPath = Path()
        ..moveTo(112, 185)
        ..lineTo(112, 24)
        ..lineTo(154, 66)
        ..lineTo(154, 185)
        ..close();

      final mainTowerPaint = Paint()
        ..color = buildingColor
        ..style = PaintingStyle.fill;
      canvas.drawPath(mainTowerPath, mainTowerPaint);

      canvas.restore();
    }

    // --- Volumen C: Espina estructural derecha (blanco) ---
    // Geometría: polígono (154, 66) a (161, 74), (161, 185) y (154, 185)
    if (rightFacetProgress > 0.0) {
      canvas.save();
      final clipTop = 185 - (119 * rightFacetProgress);
      canvas.clipRect(Rect.fromLTRB(152, clipTop, 163, 190));

      final rightSpinePath = Path()
        ..moveTo(154, 66)
        ..lineTo(161, 74)
        ..lineTo(161, 185)
        ..lineTo(154, 185)
        ..close();

      final spinePaint = Paint()
        ..color = const Color(0xFFECEEF2)
        ..style = PaintingStyle.fill;
      canvas.drawPath(rightSpinePath, spinePaint);

      canvas.restore();
    }

    // --- Volumen D: Faceta angular central dorada ---
    // Geometría: encajada en (112, 88), (139, 114), (139, 185) y (112, 185)
    if (goldFacetProgress > 0.0) {
      canvas.save();
      final clipTop = 185 - (97 * goldFacetProgress);
      canvas.clipRect(Rect.fromLTRB(110, clipTop, 142, 190));

      final goldFacetPath = Path()
        ..moveTo(112, 88)
        ..lineTo(139, 114)
        ..lineTo(139, 185)
        ..lineTo(112, 185)
        ..close();

      // Degradado dorado arquitectónico cálido
      final goldPaint = Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFE5B558), Color(0xFFD9A441), Color(0xFFB88225)],
        ).createShader(const Rect.fromLTWH(112, 88, 27, 97));

      canvas.drawPath(goldFacetPath, goldPaint);

      // Reflejo metálico diagonal dorado (Fase 4 de acabado)
      if (goldSheenProgress > -0.2 && goldSheenProgress < 1.2) {
        final sheenX = 112 + (27 * goldSheenProgress);
        final sheenPaint = Paint()
          ..shader = LinearGradient(
            begin: const Alignment(-0.8, -1.0),
            end: const Alignment(0.8, 1.0),
            colors: [
              Colors.transparent,
              Colors.white.withValues(alpha: 0.40),
              Colors.transparent,
            ],
            stops: const [0.0, 0.5, 1.0],
          ).createShader(Rect.fromLTWH(sheenX - 10, 88, 20, 97));
        canvas.drawPath(goldFacetPath, sheenPaint);
      }

      canvas.restore();
    }

    // --- Cerchas y pórticos estructurales en primer plano ---
    // Los frontones geométricos oscuros en el frente que enmarcan la base
    if (outlineProgress > 0.0) {
      final trussPaint = Paint()
        ..color = buildingColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.6
        ..strokeCap = StrokeCap.square
        ..strokeJoin = StrokeJoin.miter;

      // Pórtico frontal 1 (izquierdo): (55, 185) a (71, 137), (103, 103) y (103, 185)
      final portal1 = Path()
        ..moveTo(55, 185)
        ..lineTo(71, 137)
        ..lineTo(103, 103)
        ..lineTo(103, 185);

      _drawProgressivePath(canvas, portal1, outlineProgress, trussPaint);

      // Pórtico frontal 2 (derecho): (107, 120) a (131, 142) y (131, 185)
      final portal2 = Path()
        ..moveTo(107, 120)
        ..lineTo(131, 142)
        ..lineTo(131, 185);

      if (outlineProgress > 0.25) {
        final prog2 = (outlineProgress - 0.25) / 0.75;
        _drawProgressivePath(canvas, portal2, prog2, trussPaint);
      }

      // Línea base de cimentación arquitectónica
      final baseLine = Path()
        ..moveTo(18, 185)
        ..lineTo(195, 185);
      _drawProgressivePath(
        canvas,
        baseLine,
        outlineProgress,
        Paint()
          ..color = buildingColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4,
      );
    }

    canvas.restore();
  }

  /// Dibuja un trazado progresivamente utilizando ui.PathMetric.extractPath()
  void _drawProgressivePath(
    Canvas canvas,
    Path path,
    double progress,
    Paint paint,
  ) {
    if (progress <= 0.0) return;
    if (progress >= 1.0) {
      canvas.drawPath(path, paint);
      return;
    }

    final pathMetrics = path.computeMetrics();
    for (final metric in pathMetrics) {
      final extractLength = metric.length * progress.clamp(0.0, 1.0);
      final extracted = metric.extractPath(0.0, extractLength);
      canvas.drawPath(extracted, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ArchitecturalEmblemPainter oldDelegate) {
    return oldDelegate.blueprintProgress != blueprintProgress ||
        oldDelegate.arcProgress != arcProgress ||
        oldDelegate.outlineProgress != outlineProgress ||
        oldDelegate.towerRiseProgress != towerRiseProgress ||
        oldDelegate.leftFacetProgress != leftFacetProgress ||
        oldDelegate.rightFacetProgress != rightFacetProgress ||
        oldDelegate.goldFacetProgress != goldFacetProgress ||
        oldDelegate.goldSheenProgress != goldSheenProgress ||
        oldDelegate.guidelinesFade != guidelinesFade;
  }
}

/// Indicador circular minimalista de actividad estilo iOS con detalle dorado
class _IosMinimalSpinner extends StatefulWidget {
  const _IosMinimalSpinner({
    required this.trackColor,
    required this.accentColor,
  });

  final Color trackColor;
  final Color accentColor;

  @override
  State<_IosMinimalSpinner> createState() => _IosMinimalSpinnerState();
}

class _IosMinimalSpinnerState extends State<_IosMinimalSpinner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _rotationController;

  @override
  void initState() {
    super.initState();
    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat();
  }

  @override
  void dispose() {
    _rotationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _rotationController,
      builder: (context, _) {
        return Transform.rotate(
          angle: _rotationController.value * 2 * math.pi,
          child: CustomPaint(
            painter: _IosSpinnerPainter(
              trackColor: widget.trackColor,
              accentColor: widget.accentColor,
            ),
          ),
        );
      },
    );
  }
}

class _IosSpinnerPainter extends CustomPainter {
  const _IosSpinnerPainter({
    required this.trackColor,
    required this.accentColor,
  });

  final Color trackColor;
  final Color accentColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - 2.5) / 2;

    // Pista circular tenue
    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawCircle(center, radius, trackPaint);

    // Arco de barrido activo (detalle dorado sutil estilo iOS)
    final sweepPaint = Paint()
      ..color = accentColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      0,
      math.pi * 0.75,
      false,
      sweepPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _IosSpinnerPainter oldDelegate) {
    return false;
  }
}
