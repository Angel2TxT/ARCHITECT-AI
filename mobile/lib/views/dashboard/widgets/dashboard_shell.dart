import 'dart:io';

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

class DashboardHero extends StatelessWidget {
  const DashboardHero({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Text(
        '¿Qué plano revisamos hoy?',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: colorScheme.onSurface,
          fontSize: 28,
          fontWeight: FontWeight.w800,
          height: 1.2,
        ),
      ),
    );
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

class _DashboardAskBarState extends State<DashboardAskBar> {
  late final FocusNode _focusNode;
  late final SpeechDictationController _dictation;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    _focusNode.addListener(_onFocusChanged);
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
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChanged);
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
    final borderColor = isFocused
        ? (isDark ? Colors.white : Colors.black)
        : (isDark ? const Color(0xFF4A4A50) : const Color(0xFFCBD5E1));

    return Container(
      height: 56,
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
      decoration: BoxDecoration(
        color: barColor,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: borderColor,
          width: isFocused ? 1.8 : 1.4,
        ),
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
    );
  }
}
