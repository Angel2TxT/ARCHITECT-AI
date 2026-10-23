import 'package:flutter/material.dart';
import 'package:movil_architect/core/theme/app_colors.dart';
import 'package:movil_architect/core/utils/chat_attachment_cache.dart';
import 'package:movil_architect/core/utils/chat_response_formatter.dart';
import 'package:movil_architect/core/utils/image_utils.dart';
import 'package:movil_architect/models/chat_models.dart';
import 'package:movil_architect/views/dashboard/widgets/dashboard_shell.dart';
import 'package:movil_architect/views/shared/app_states.dart';
import 'package:movil_architect/views/shared/markdown_text.dart';

class ChatMessageBubble extends StatelessWidget {
  const ChatMessageBubble({super.key, required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: message.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.82,
        ),
        child: message.isUser
            ? _UserBubble(message: message)
            : _AssistantBubble(message: message),
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
            // Fallback: si parece imagen pero aún no hay bytes, mostrar placeholder.
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

class _AssistantBubble extends StatelessWidget {
  const _AssistantBubble({required this.message});

  final ChatMessage message;

  String? get _annotatedImage {
    final content = message.content;
    final fromContent = content.imageBase64;
    if (fromContent != null && fromContent.trim().isNotEmpty) {
      return fromContent;
    }
    final analysisId = content.analysisId;
    if (analysisId == null) return null;
    return ChatAttachmentCache.instance.getAnnotatedSync(analysisId);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = colorScheme.brightness == Brightness.dark;
    final content = message.content;
    final verdict = content.verdict;
    final toneColor =
        verdict != null ? verdictColor(verdict.tone) : colorScheme.onSurface;
    final annotatedImage = _annotatedImage;
    final showPlanIndicator =
        content.hasImage || content.analysisId != null;
    final structuredDetail = verdict != null && verdict.detail.isNotEmpty
        ? ChatResponseFormatter.formatVerdictDetail(
            verdict.detail,
            omitTotals: content.stats != null,
          )
        : '';
    final bodyText = () {
      if (content.text == null || content.text!.isEmpty) return '';
      var formatted = ChatResponseFormatter.formatAssistantText(content.text!);
      if (structuredDetail.isNotEmpty) {
        formatted =
            ChatResponseFormatter.stripDuplicateHallazgos(formatted);
      }
      return formatted;
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
          const AiReplyHeader(),
          const SizedBox(height: 10),
          if (showPlanIndicator) ...[
            const _PlanAnalyzedChip(),
            const SizedBox(height: 10),
          ],
          if (verdict != null && verdict.headline.isNotEmpty) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(verdictIcon(verdict.tone), color: toneColor, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    verdict.headline,
                    style: TextStyle(
                      color: toneColor,
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
          ],
          if (content.stats != null) ...[
            AnalysisCountsRow(counts: content.stats!),
            const SizedBox(height: 12),
          ],
          if (structuredDetail.isNotEmpty) ...[
            MarkdownText(
              data: structuredDetail,
              style: TextStyle(
                color: colorScheme.onSurface,
                height: 1.4,
                fontSize: 13.5,
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (annotatedImage != null && annotatedImage.isNotEmpty) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.memory(
                decodeBase64Image(annotatedImage),
                fit: BoxFit.contain,
                errorBuilder: (_, error, stackTrace) => const SizedBox.shrink(),
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (bodyText.isNotEmpty)
            MarkdownText(
              data: bodyText,
              style: TextStyle(color: colorScheme.onSurface, height: 1.45),
            ),
          if (suggestions.isNotEmpty) ...[
            if (bodyText.isNotEmpty) const SizedBox(height: 12),
            MarkdownText(
              data: [
                '**Sugerencias**',
                for (final item in suggestions) '- $item',
              ].join('\n'),
              style: TextStyle(color: colorScheme.onSurface, height: 1.45),
            ),
          ],
        ],
      ),
    );
  }
}
class _PlanAnalyzedChip extends StatelessWidget {
  const _PlanAnalyzedChip();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = colorScheme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isDark
            ? colorScheme.surfaceContainerHigh
            : AppColors.dashboardIconBg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.architecture, size: 14, color: colorScheme.onSurface),
          const SizedBox(width: 6),
          Text(
            'Plano analizado',
            style: TextStyle(
              color: colorScheme.onSurface,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
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
      ],
    );
  }
}
