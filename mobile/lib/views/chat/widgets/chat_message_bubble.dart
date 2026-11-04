import 'dart:io';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:movil_architect/core/app_services.dart';
import 'package:movil_architect/core/network/api_exception.dart';
import 'package:movil_architect/core/theme/app_colors.dart';
import 'package:movil_architect/core/utils/app_notifications.dart';
import 'package:movil_architect/core/utils/chat_attachment_cache.dart';
import 'package:movil_architect/core/utils/chat_response_formatter.dart';
import 'package:movil_architect/core/utils/image_utils.dart';
import 'package:movil_architect/models/analysis_models.dart';
import 'package:movil_architect/models/chat_models.dart';
import 'package:movil_architect/views/dashboard/widgets/dashboard_shell.dart';
import 'package:movil_architect/views/chat/widgets/plan_correction_progress_card.dart';
import 'package:movil_architect/views/chat/widgets/plan_zoom_viewer.dart';
import 'package:movil_architect/views/chat/widgets/typewriter_text.dart';
import 'package:movil_architect/views/shared/markdown_text.dart';

class ChatMessageBubble extends StatelessWidget {
  const ChatMessageBubble({
    super.key,
    required this.message,
    this.isLatest = false,
  });

  final ChatMessage message;
  final bool isLatest;

  static final Set<int> _animatedIds = <int>{};

  static bool isAnimated(int id) => _animatedIds.contains(id);
  static void markAnimated(int id) => _animatedIds.add(id);

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: message.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.88,
        ),
        child: message.isUser
            ? _UserBubble(message: message)
            : _AssistantBubble(
                message: message,
                isLatest: isLatest,
              ),
      ),
    );
  }
}

class _UserBubble extends StatelessWidget {
  const _UserBubble({required this.message});

  final ChatMessage message;

  String? get _imageBase64 {
    final content = message.content;
    final fromContent = content.imageBase64;
    if (fromContent != null && fromContent.isNotEmpty) return fromContent;
    return ChatAttachmentCache.instance.get(content.filename);
  }

  @override
  Widget build(BuildContext context) {
    final content = message.content;
    final filename = content.filename;
    final cachedOrRemoteImage = _imageBase64;
    final canShowImage = cachedOrRemoteImage != null &&
        cachedOrRemoteImage.isNotEmpty &&
        (filename == null ||
            filename.isEmpty ||
            isPlanoImageFile(filename));
    final text = content.text?.trim();
    final hasText = text != null && text.isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.ink,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (canShowImage) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: AspectRatio(
                aspectRatio: 4 / 3,
                child: Image.memory(
                  decodeBase64Image(cachedOrRemoteImage),
                  fit: BoxFit.cover,
                  errorBuilder: (_, error, stackTrace) => const ColoredBox(
                    color: Color(0x33FFFFFF),
                    child: Icon(
                      Icons.broken_image_outlined,
                      color: Colors.white70,
                    ),
                  ),
                ),
              ),
            ),
            if (filename != null && filename.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                filename,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            if (hasText) const SizedBox(height: 10),
          ] else if (filename != null && filename.isNotEmpty) ...[
            if (isPlanoImageFile(filename)) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: AspectRatio(
                  aspectRatio: 4 / 3,
                  child: ColoredBox(
                    color: const Color(0x33FFFFFF),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.image_outlined,
                          color: Colors.white70,
                          size: 36,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          filename,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ] else
              Row(
                children: [
                  const Icon(Icons.attach_file, color: Colors.white70, size: 18),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      filename,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            if (hasText) const SizedBox(height: 8),
          ],
          if (hasText)
            Text(
              text,
              style: const TextStyle(color: Colors.white, height: 1.4),
            ),
        ],
      ),
    );
  }
}

class _AssistantBubble extends StatefulWidget {
  const _AssistantBubble({
    required this.message,
    required this.isLatest,
  });

  final ChatMessage message;
  final bool isLatest;

  @override
  State<_AssistantBubble> createState() => _AssistantBubbleState();
}

class _AssistantBubbleState extends State<_AssistantBubble> {
  bool _downloadingPdf = false;
  bool _downloadingDxf = false;
  bool _imageRevealed = false;

  String? get _annotatedImage {
    final content = widget.message.content;
    final fromContent = content.imageBase64;
    if (fromContent != null && fromContent.trim().isNotEmpty) {
      return fromContent;
    }
    final analysisId = content.analysisId;
    if (analysisId == null) return null;
    return ChatAttachmentCache.instance.getAnnotatedSync(analysisId);
  }

  Future<void> _downloadPdf(BuildContext context, int analysisId) async {
    if (_downloadingPdf) return;
    setState(() => _downloadingPdf = true);
    try {
      AppNotifications.info(context, 'Generando dictamen técnico oficial…');
      final bytes = await AppServices.instance.mobileApiService
          .downloadDossierPdf(analysisId);
      if (bytes.isEmpty) {
        throw ApiException(message: 'El dictamen PDF no contiene datos.');
      }
      final dir = await getTemporaryDirectory();
      final filePath =
          '${dir.path}/Dictamen_ARCHITECT_${analysisId.toString().padLeft(6, '0')}.pdf';
      final file = File(filePath);
      await file.writeAsBytes(bytes, flush: true);
      final result = await OpenFilex.open(filePath);
      if (result.type != ResultType.done && context.mounted) {
        AppNotifications.error(
          context,
          result.message.isNotEmpty ? result.message : 'No se pudo abrir el PDF.',
        );
      } else if (context.mounted) {
        AppNotifications.success(context, 'Dictamen PDF abierto con éxito');
      }
    } on ApiException catch (error) {
      if (context.mounted) AppNotifications.error(context, error.message);
    } catch (_) {
      if (context.mounted) {
        AppNotifications.error(context, 'Error al descargar el dictamen PDF.');
      }
    } finally {
      if (mounted) setState(() => _downloadingPdf = false);
    }
  }

  Future<void> _downloadDxf(BuildContext context, int analysisId) async {
    if (_downloadingDxf) return;
    setState(() => _downloadingDxf = true);
    try {
      AppNotifications.info(context, 'Exportando archivo vectorial CAD DXF…');
      final bytes =
          await AppServices.instance.mobileApiService.downloadDxf(analysisId);
      if (bytes.isEmpty) {
        throw ApiException(message: 'El archivo DXF no contiene datos.');
      }
      final dir = await getTemporaryDirectory();
      final filePath =
          '${dir.path}/Plano_CAD_${analysisId.toString().padLeft(6, '0')}.dxf';
      final file = File(filePath);
      await file.writeAsBytes(bytes, flush: true);
      final result = await OpenFilex.open(filePath);
      if (result.type != ResultType.done && context.mounted) {
        AppNotifications.error(
          context,
          result.message.isNotEmpty ? result.message : 'No se pudo abrir el archivo DXF.',
        );
      } else if (context.mounted) {
        AppNotifications.success(context, 'Plano CAD DXF exportado con éxito');
      }
    } on ApiException catch (error) {
      if (context.mounted) AppNotifications.error(context, error.message);
    } catch (_) {
      if (context.mounted) {
        AppNotifications.error(context, 'Error al exportar el plano CAD DXF.');
      }
    } finally {
      if (mounted) setState(() => _downloadingDxf = false);
    }
  }

  Widget _buildStatusPill(AnalysisCounts? stats, bool isDark) {
    final errors = stats?.errors ?? 0;
    final warnings = stats?.warnings ?? 0;

    final Color bg;
    final Color fg;
    final IconData icon;
    final String text;

    if (errors > 0) {
      bg = const Color(0xFFEF4444).withValues(alpha: isDark ? 0.2 : 0.12);
      fg = isDark ? const Color(0xFFFCA5A5) : const Color(0xFFDC2626);
      icon = Icons.error_outline;
      text = 'Requiere adecuaciones normativas';
    } else if (warnings > 0) {
      bg = const Color(0xFFF59E0B).withValues(alpha: isDark ? 0.2 : 0.12);
      fg = isDark ? const Color(0xFFFCD34D) : const Color(0xFFD97706);
      icon = Icons.warning_amber_rounded;
      text = 'Observaciones de diseño';
    } else {
      bg = const Color(0xFF22C55E).withValues(alpha: isDark ? 0.2 : 0.12);
      fg = isDark ? const Color(0xFF86EFAC) : const Color(0xFF16A34A);
      icon = Icons.verified_outlined;
      text = 'Cumplimiento satisfactorio';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: fg),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: fg,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKpisRow(AnalysisCounts counts, bool isDark) {
    return Row(
      children: [
        Expanded(
          child: _KpiCard(
            label: 'Errores',
            value: counts.errors.toString(),
            color: counts.errors > 0
                ? const Color(0xFFEF4444)
                : (isDark ? Colors.white70 : Colors.black87),
            isDark: isDark,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _KpiCard(
            label: 'Avisos',
            value: counts.warnings.toString(),
            color: counts.warnings > 0
                ? const Color(0xFFF59E0B)
                : (isDark ? Colors.white70 : Colors.black87),
            isDark: isDark,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _KpiCard(
            label: 'Detectados',
            value: counts.detections.toString(),
            color: isDark ? Colors.white : Colors.black,
            isDark: isDark,
          ),
        ),
      ],
    );
  }

  Widget _buildPlanImageCard(
    String base64Image,
    BuildContext context,
    bool isDark,
  ) {
    final decodedBytes = decodeBase64Image(base64Image);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () {
            PlanZoomViewer.show(
              context,
              imageBytes: decodedBytes,
              title: 'Plano técnico analizado',
            );
          },
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isDark ? const Color(0x28FFFFFF) : const Color(0x18000000),
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(13),
              child: Stack(
                children: [
                  Image.memory(
                    decodedBytes,
                    fit: BoxFit.contain,
                    errorBuilder: (_, error, stackTrace) => const SizedBox.shrink(),
                  ),
                  Positioned(
                    bottom: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.zoom_in,
                            size: 13,
                            color: Colors.white,
                          ),
                          SizedBox(width: 4),
                          Text(
                            'Toca para zoom',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 5),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            'Plano con incidencias marcadas',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: Colors.grey,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = colorScheme.brightness == Brightness.dark;
    final content = widget.message.content;
    final verdict = content.verdict;
    final annotatedImage = _annotatedImage;
    final analysisId = content.analysisId;

    final hasAnalysis = analysisId != null ||
        (content.stats != null && content.stats!.detections > 0) ||
        (annotatedImage != null && annotatedImage.isNotEmpty);

    final isNewUnseen = widget.isLatest &&
        !ChatMessageBubble.isAnimated(widget.message.id);

    final showProgress = hasAnalysis &&
        annotatedImage != null &&
        annotatedImage.isNotEmpty &&
        isNewUnseen &&
        !_imageRevealed;

    final shouldAnimateText = isNewUnseen;

    final bodyText = () {
      if (content.text == null || content.text!.isEmpty) {
        return verdict?.headline ?? '';
      }
      return ChatResponseFormatter.formatAssistantText(content.text!);
    }();

    final suggestions = verdict?.suggestions
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList() ??
        const <String>[];

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? colorScheme.surfaceContainerHighest : Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: isDark
            ? null
            : const [
                BoxShadow(
                  color: Color(0x0A000000),
                  blurRadius: 12,
                  offset: Offset(0, 4),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Cabecera IA Apple Monochrome
          const AiReplyHeader(),
          const SizedBox(height: 10),

          // 2. Si es análisis de plano, unificamos: imagen arriba, auditoría abajo (sin sándwich)
          if (hasAnalysis) ...[
            // 2.1 PLANO VISUAL ARRIBA
            if (showProgress)
              PlanCorrectionProgressCard(
                detectionsCount: content.stats?.detections ?? 0,
                errorsCount: content.stats?.errors ?? 0,
                onCompleted: () {
                  if (mounted) setState(() => _imageRevealed = true);
                  ChatMessageBubble.markAnimated(widget.message.id);
                },
              )
            else if (annotatedImage != null && annotatedImage.isNotEmpty)
              _buildPlanImageCard(annotatedImage, context, isDark),

            const SizedBox(height: 10),

            // 2.2 TARJETA UNIFICADA DE AUDITORÍA ABAJO
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF141416) : const Color(0xFFF9FAFB),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isDark ? const Color(0x22FFFFFF) : const Color(0x18000000),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Estado normativo y botones de descarga oficial
                  _buildStatusPill(content.stats, isDark),
                  if (analysisId != null) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        _ActionButton(
                          icon: Icons.picture_as_pdf_outlined,
                          label: 'Dictamen PDF',
                          isLoading: _downloadingPdf,
                          onPressed: () => _downloadPdf(context, analysisId),
                        ),
                        _ActionButton(
                          icon: Icons.architecture_outlined,
                          label: 'Exportar DXF',
                          isLoading: _downloadingDxf,
                          onPressed: () => _downloadDxf(context, analysisId),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 10),

                  // Veredicto técnico ejecutivo mecanografiado
                  if (bodyText.isNotEmpty) ...[
                    TypewriterText(
                      data: bodyText,
                      animate: shouldAnimateText,
                      onCompleted: () {
                        ChatMessageBubble.markAnimated(widget.message.id);
                      },
                      style: TextStyle(
                        color: colorScheme.onSurface,
                        fontSize: 13.5,
                        height: 1.45,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],

                  // Cinta de métricas KPI
                  if (content.stats != null) ...[
                    _buildKpisRow(content.stats!, isDark),
                  ],

                  // Acciones prioritarias sugeridas (si existen)
                  if (suggestions.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    MarkdownText(
                      data: [
                        '**Pasos sugeridos:**',
                        for (final item in suggestions) '- $item',
                      ].join('\n'),
                      style: TextStyle(
                        color: colorScheme.onSurface,
                        fontSize: 12.5,
                        height: 1.4,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ] else ...[
            // Flujo conversacional estándar (sin plano)
            if (bodyText.isNotEmpty)
              TypewriterText(
                data: bodyText,
                animate: shouldAnimateText,
                onCompleted: () {
                  ChatMessageBubble.markAnimated(widget.message.id);
                },
                style: TextStyle(
                  color: colorScheme.onSurface,
                  fontSize: 14,
                  height: 1.45,
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.label,
    required this.value,
    required this.color,
    required this.isDark,
  });

  final String label;
  final String value;
  final Color color;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
      decoration: BoxDecoration(
        color: isDark ? const Color(0x12FFFFFF) : const Color(0x08000000),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark ? const Color(0x18FFFFFF) : const Color(0x10000000),
        ),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              fontFeatures: const [FontFeature.tabularFigures()],
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
              color: isDark ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.isLoading = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: isLoading ? null : onPressed,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: isDark ? const Color(0x1AFFFFFF) : const Color(0x0A000000),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isDark ? const Color(0x2AFFFFFF) : const Color(0x1A000000),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isLoading) ...[
                SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.8,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                ),
                const SizedBox(width: 6),
              ] else ...[
                Icon(icon, size: 13, color: isDark ? Colors.white : Colors.black87),
                const SizedBox(width: 5),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AiReplyHeader extends StatelessWidget {
  const AiReplyHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = colorScheme.brightness == Brightness.dark;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: isDark
                ? colorScheme.surfaceContainerHigh
                : AppColors.dashboardIconBg,
            shape: BoxShape.circle,
          ),
          child: Padding(
            padding: const EdgeInsets.all(5),
            child: Icon(
              Icons.auto_awesome,
              size: 12,
              color: colorScheme.onSurface,
            ),
          ),
        ),
        const SizedBox(width: 7),
        Text(
          'ARCHITECT IA',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
            color: isDark ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280),
          ),
        ),
      ],
    );
  }
}
