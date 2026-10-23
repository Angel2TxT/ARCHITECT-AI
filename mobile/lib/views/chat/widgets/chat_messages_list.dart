import 'dart:io';

import 'package:flutter/material.dart';
import 'package:movil_architect/controllers/chat_controller.dart';
import 'package:movil_architect/core/theme/app_colors.dart';
import 'package:movil_architect/models/chat_models.dart';
import 'package:movil_architect/views/chat/widgets/chat_message_bubble.dart';
import 'package:movil_architect/views/chat/widgets/plano_chat_attachment.dart';
import 'package:movil_architect/views/chat/widgets/typing_indicator_bubble.dart';

class ChatMessagesList extends StatelessWidget {
  const ChatMessagesList({
    super.key,
    required this.controller,
    required this.scrollController,
    this.pendingMessage,
    this.isWaitingResponse = false,
    this.isAnalyzingPlano = false,
    this.pendingPlanoFile,
    this.pendingPlanoName,
    this.pendingPlanoProgress,
    this.onDismissPendingPlano,
    this.onPendingPlanoTap,
    this.onRefresh,
    this.emptyMessage = 'Esta conversación aún no tiene mensajes.',
  });

  final ChatController controller;
  final ScrollController scrollController;
  final String? pendingMessage;
  final bool isWaitingResponse;
  final bool isAnalyzingPlano;
  final File? pendingPlanoFile;
  final String? pendingPlanoName;
  final double? pendingPlanoProgress;
  final VoidCallback? onDismissPendingPlano;
  final VoidCallback? onPendingPlanoTap;
  final Future<void> Function()? onRefresh;
  final String emptyMessage;

  bool get _hasPendingPlano =>
      pendingPlanoName != null && pendingPlanoName!.isNotEmpty;

  ChatMessage? _pendingChatMessage(String text) {
    return ChatMessage(
      id: -1,
      role: 'user',
      content: MessageContent(text: text),
      createdAt: DateTime.now(),
    );
  }

  bool _showPending(String? pending) {
    if (pending == null) return false;
    final messages = controller.messages;
    if (messages.isEmpty) return true;
    final last = messages.last;
    return !(last.isUser && last.content.text == pending);
  }

  bool _showTyping(bool waiting, String? pending) {
    return controller.isSending || waiting;
  }

  int _itemCount(String? pending, bool waiting) {
    var count = controller.messages.length;
    if (_showPending(pending) || (_hasPendingPlano && pending != null)) {
      count++;
    }
    if (_showTyping(waiting, pending)) count++;
    return count;
  }

  Widget _buildPendingGroup(String? pending) {
    if (_hasPendingPlano) {
      return UserPlanoMessageGroup(
        fileName: pendingPlanoName!,
        file: pendingPlanoFile,
        loadProgress: pendingPlanoProgress,
        text: pending ?? '',
        onDismissPlano: onDismissPendingPlano,
        onPlanoTap: onPendingPlanoTap,
      );
    }

    if (pending != null) {
      return ChatMessageBubble(message: _pendingChatMessage(pending)!);
    }

    return const SizedBox.shrink();
  }

  Widget _buildItem(
    BuildContext context,
    int index,
    String? pending,
    bool waiting,
  ) {
    final messages = controller.messages;
    var offset = 0;

    for (var i = 0; i < messages.length; i++) {
      if (index == offset) {
        return ChatMessageBubble(message: messages[i]);
      }
      offset++;
    }

    final showPendingGroup =
        _showPending(pending) || (_hasPendingPlano && pending != null);

    if (showPendingGroup) {
      if (index == offset) {
        return _buildPendingGroup(pending);
      }
      offset++;
    }

    if (_showTyping(waiting, pending) && index == offset) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const TypingIndicatorBubble(),
          if (isAnalyzingPlano)
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 4),
              child: Text(
                'Analizando plano…',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      );
    }

    return const SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    final pending = pendingMessage ?? controller.pendingUserMessage;
    final waiting = isWaitingResponse || controller.isSending;
    final isEmpty = controller.messages.isEmpty &&
        !_showPending(pending) &&
        !(_hasPendingPlano && pending != null) &&
        !waiting;

    if (isEmpty) {
      final empty = Center(
        child: Text(
          emptyMessage,
          style: const TextStyle(color: AppColors.muted),
        ),
      );
      if (onRefresh == null) return empty;
      return LayoutBuilder(
        builder: (context, constraints) {
          return RefreshIndicator(
            onRefresh: onRefresh!,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: empty,
              ),
            ),
          );
        },
      );
    }

    final listView = ListView.builder(
      controller: scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      itemCount: _itemCount(pending, waiting),
      itemBuilder: (context, index) =>
          _buildItem(context, index, pending, waiting),
    );

    if (onRefresh == null) return listView;

    return RefreshIndicator(
      onRefresh: onRefresh!,
      child: listView,
    );
  }
}
