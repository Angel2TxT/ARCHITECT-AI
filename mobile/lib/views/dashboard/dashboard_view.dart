import 'dart:io';

import 'package:flutter/material.dart';
import 'package:movil_architect/controllers/chat_controller.dart';
import 'package:movil_architect/controllers/dashboard_controller.dart';
import 'package:movil_architect/core/utils/app_notifications.dart';
import 'package:movil_architect/models/chat_models.dart';
import 'package:movil_architect/views/analyze/analyze_view.dart';
import 'package:movil_architect/views/chat/widgets/chat_message_bubble.dart';
import 'package:movil_architect/views/chat/widgets/chat_messages_list.dart';
import 'package:movil_architect/views/chat/widgets/plano_chat_attachment.dart';
import 'package:movil_architect/views/chat/widgets/typing_indicator_bubble.dart';
import 'package:movil_architect/views/billing/billing_view.dart';
import 'package:movil_architect/views/dashboard/widgets/dashboard_drawer.dart';
import 'package:movil_architect/views/dashboard/widgets/dashboard_shell.dart';
import 'package:movil_architect/views/settings/settings_view.dart';
import 'package:movil_architect/views/shared/app_states.dart';
import 'package:movil_architect/views/shared/attachment_picker_sheet.dart';
import 'package:movil_architect/views/home_projects/home_projects_list_view.dart';

class DashboardView extends StatefulWidget {
  const DashboardView({super.key, this.initialChatId});

  /// Abre el dashboard con una conversación ya cargada (sin otra pantalla).
  final String? initialChatId;

  @override
  State<DashboardView> createState() => _DashboardViewState();
}

class _DashboardViewState extends State<DashboardView> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  late final DashboardController _controller;
  final _scrollController = ScrollController();
  ChatController? _chatController;

  @override
  void initState() {
    super.initState();
    _controller = DashboardController();
    _controller.load().then((_) {
      final chatId = widget.initialChatId;
      if (chatId != null && chatId.isNotEmpty && mounted) {
        _activateChat(chatId);
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _chatController?.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _syncChatController(String chatId) async {
    if (_chatController?.chatId == chatId) {
      await _chatController!.load(showLoading: false);
      if (mounted) setState(() {});
      return;
    }

    _chatController?.dispose();
    _chatController = ChatController(chatId: chatId);
    if (mounted) setState(() {});
    await _chatController!.load();
    if (mounted) setState(() {});
  }

  Future<void> _activateChat(String chatId) async {
    _controller.setActiveChat(chatId);
    await _syncChatController(chatId);
    if (!mounted) return;

    if (_chatController?.state == ChatState.error &&
        _chatController?.errorStatusCode == 404) {
      _controller.clearActiveChat();
      _chatController?.dispose();
      _chatController = null;
      setState(() {});
      AppNotifications.error(context, 'Esa conversación ya no existe');
      return;
    }

    if (_chatController?.messages.isEmpty == true &&
        _chatController?.state == ChatState.success) {
      final emptyId = chatId;
      _closeChat();
      _controller.deleteChat(emptyId).catchError((_) {});
      if (mounted) {
        AppNotifications.info(
          context,
          'La conversación estaba vacía y se descartó.',
        );
      }
      return;
    }

    _scrollToBottom();
  }

  void _closeChat() {
    _controller.clearActiveChat();
    _chatController?.dispose();
    _chatController = null;
    setState(() {});
  }

  void _newChat() {
    _closeChat();
    _controller.askController.clear();
    _controller.clearPendingPlano();
    if (mounted) setState(() {});
  }

  void _startNewChat() {
    _newChat();
  }

  void _openCasaHogar() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const HomeProjectsListView(),
      ),
    );
  }

  void _openPlans() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const BillingView(),
      ),
    );
  }

  Future<void> _openAnalyze({File? initialFile, String? initialFileName}) async {
    final file = initialFile ?? _controller.pendingPlanoFile;
    final name = initialFileName ?? _controller.pendingPlanoName;
    if (file == null) return;

    _controller.clearPendingPlano();

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AnalyzeView(
          initialFile: file,
          initialFileName: name,
        ),
      ),
    );
    if (mounted) await _controller.load(refresh: true);
  }

  Future<void> _openAttachmentPicker() async {
    final pick = await showAttachmentPickerSheet(context);
    if (pick == null || !mounted) return;
    await _controller.preparePendingPlano(pick.file, pick.name);
    _scrollToBottom();
  }

  Future<void> _openPendingPlano() async {
    if (!_controller.hasPendingPlano) return;
    await _openAnalyze();
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SettingsView(
          controller: _controller,
          onAllChatsDeleted: _closeChat,
          onNewChat: () {
            Navigator.of(context).pop();
            _startNewChat();
          },
          onChatOpen: (chatId) {
            Navigator.of(context).pop();
            _activateChat(chatId);
          },
          onChatDeleted: (chatId) {
            if (_chatController?.chatId == chatId) {
              _closeChat();
            }
          },
          onStageAdmin: () {
            Navigator.of(context).pop();
            _openCasaHogar();
          },
          onPlans: () {
            Navigator.of(context).pop();
            _openPlans();
          },
        ),
      ),
    );
  }

  void _openDrawer() => _scaffoldKey.currentState?.openDrawer();

  Listenable get _askBarListenable {
    if (_chatController != null) {
      return Listenable.merge([_controller, _chatController!]);
    }
    return _controller;
  }

  Future<void> _sendMessage() async {
    _scrollToBottom();

    if (_controller.hasPendingPlano && !_controller.isLoadingPendingPlano) {
      await _sendPlanoAnalysis();
      return;
    }

    if (_chatController != null) {
      final ok = await _chatController!.sendMessage();
      if (!mounted) return;
      if (_chatController!.errorMessage != null) {
        AppNotifications.error(context, _chatController!.errorMessage!);
      }
      if (ok) await _controller.load(refresh: true);
      if (mounted) setState(() {});
      _scrollToBottom();
      return;
    }

    final chatId = await _controller.sendAsk();
    if (!mounted) return;

    if (_controller.askErrorMessage != null) {
      AppNotifications.error(context, _controller.askErrorMessage!);
      return;
    }

    if (chatId != null) {
      _controller.setActiveChat(chatId);
      await _syncChatController(chatId);
      if (mounted) setState(() {});
    }
    _scrollToBottom();
  }

  Future<void> _sendPlanoAnalysis() async {
    final inputController = _chatController?.messageController ??
        _controller.askController;
    final message = inputController.text.trim();
    inputController.clear();

    final result = await _controller.analyzePendingPlano(message: message);
    if (!mounted) return;

    if (_controller.askErrorMessage != null) {
      AppNotifications.error(context, _controller.askErrorMessage!);
      return;
    }

    final chatId = result?.chatId ?? _controller.activeChatId;
    if (chatId != null && chatId.isNotEmpty) {
      await _activateChat(chatId);
      if (result != null && _chatController != null) {
        await _chatController!.applyAnalysisResult(result);
      }
    }

    if (mounted) setState(() {});
    _scrollToBottom();
  }

  bool get _showChatArea {
    return _controller.hasActiveChat ||
        _controller.pendingAskMessage != null ||
        _controller.isSendingAsk ||
        _controller.isAnalyzingPlano ||
        _chatController != null;
  }

  bool get _showPlanoInChat =>
      _controller.pendingAskMessage != null || _controller.isAnalyzingPlano;

  Future<void> _refreshDashboard() async {
    await _controller.load(refresh: true);
    if (_chatController != null) {
      await _chatController!.load(showLoading: false);
    }
  }

  void _dismissPlanoAttachment() {
    if (_controller.isLoadingPendingPlano) {
      _controller.cancelPendingPlanoLoad();
    } else {
      _controller.clearPendingPlano();
    }
  }

  Widget _buildPendingMessages() {
    final pending = _controller.pendingAskMessage;
    final name = _showPlanoInChat ? _controller.displayPlanoName : null;

    return RefreshIndicator(
      onRefresh: _refreshDashboard,
      child: ListView(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      children: [
        if (name != null && pending != null)
          UserPlanoMessageGroup(
            fileName: name,
            file: _controller.displayPlanoFile,
            text: pending,
            onDismissPlano: null,
            onPlanoTap: null,
          )
        else if (pending != null)
          ChatMessageBubble(
            message: ChatMessage(
              id: -1,
              role: 'user',
              content: MessageContent(text: pending),
              createdAt: DateTime.now(),
            ),
          ),
        if (_controller.isSendingAsk) const TypingIndicatorBubble(),
        if (_controller.isAnalyzingPlano) ...[
          const TypingIndicatorBubble(),
          Padding(
            padding: const EdgeInsets.only(top: 8),
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
      ],
      ),
    );
  }

  Widget _buildMainContent() {
    if (_chatController != null) {
      return ListenableBuilder(
        listenable: _chatController!,
        builder: (context, _) {
          if (_chatController!.state == ChatState.error) {
            return AppErrorView(
              message: _chatController!.errorMessage ?? 'Error al cargar',
              onRetry: () => _chatController!.load().then((_) => _scrollToBottom()),
              retryLabel: 'Reintentar',
            );
          }
          if (_chatController!.state == ChatState.loading) {
            return const AppLoadingView(message: 'Cargando conversación...');
          }
          return ChatMessagesList(
            controller: _chatController!,
            scrollController: _scrollController,
            pendingMessage: _controller.pendingAskMessage,
            isWaitingResponse: _controller.isSendingAsk ||
                _controller.isAnalyzingPlano,
            isAnalyzingPlano: _controller.isAnalyzingPlano,
            pendingPlanoFile:
                _showPlanoInChat ? _controller.displayPlanoFile : null,
            pendingPlanoName:
                _showPlanoInChat ? _controller.displayPlanoName : null,
            onDismissPendingPlano: null,
            onPendingPlanoTap: null,
            onRefresh: _refreshDashboard,
          );
        },
      );
    }

    if (_controller.pendingAskMessage != null ||
        _controller.isSendingAsk ||
        _controller.isAnalyzingPlano) {
      return _buildPendingMessages();
    }

    return const Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 20),
        child: DashboardHero(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      resizeToAvoidBottomInset: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      drawer: DashboardDrawer(
        controller: _controller,
        onNewChat: _startNewChat,
        onSettings: _openSettings,
        onChatOpen: _activateChat,
        onChatDeleted: (chatId) {
          if (_chatController?.chatId == chatId) {
            _closeChat();
          }
        },
        onStageAdmin: _openCasaHogar,
        onPlans: _openPlans,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListenableBuilder(
                listenable: _chatController != null
                    ? Listenable.merge([_controller, _chatController!])
                    : _controller,
                builder: (context, _) {
                  if (_controller.state == DashboardState.loading) {
                    return const AppLoadingView(message: 'Cargando...');
                  }

                  if (_controller.state == DashboardState.error) {
                    return AppErrorView(
                      message: _controller.errorMessage ?? 'Error al cargar',
                      onRetry: () => _controller.load(),
                    );
                  }

                  return Column(
                    children: [
                      DashboardTopBar(
                        onMenuTap: _openDrawer,
                        onNewChatTap: () {
                          _newChat();
                        },
                      ),
                      Expanded(
                        child: _showChatArea
                            ? _buildMainContent()
                            : RefreshIndicator(
                                onRefresh: _refreshDashboard,
                                child: LayoutBuilder(
                                  builder: (context, constraints) {
                                    return SingleChildScrollView(
                                      physics:
                                          const AlwaysScrollableScrollPhysics(),
                                      child: ConstrainedBox(
                                        constraints: BoxConstraints(
                                          minHeight: constraints.maxHeight,
                                        ),
                                        child: const Center(
                                          child: Padding(
                                            padding: EdgeInsets.symmetric(
                                              horizontal: 20,
                                            ),
                                            child: DashboardHero(),
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                      ),
                    ],
                  );
                },
              ),
            ),
            ListenableBuilder(
              listenable: _askBarListenable,
              builder: (context, _) {
                if (_controller.state != DashboardState.success) {
                  return const SizedBox.shrink();
                }

                final isSending =
                    _controller.isSendingAsk ||
                    _controller.isAnalyzingPlano ||
                    (_chatController?.isSending ?? false);

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_controller.isLoadingPendingPlano &&
                        _controller.pendingPlanoName != null)
                      PendingPlanoLoadingBanner(
                        fileName: _controller.pendingPlanoName!,
                        progress: _controller.pendingPlanoLoadProgress,
                        onCancel: _controller.cancelPendingPlanoLoad,
                      )
                    else if (_controller.hasPendingPlano &&
                        _controller.pendingPlanoFile != null &&
                        _controller.pendingPlanoName != null)
                      PendingPlanoBanner(
                        file: _controller.pendingPlanoFile!,
                        fileName: _controller.pendingPlanoName!,
                        onTap: _openPendingPlano,
                        onDismiss: _dismissPlanoAttachment,
                      ),
                    DashboardAskBar(
                      controller: _chatController?.messageController ??
                          _controller.askController,
                      onAttachTap: _controller.isLoadingPendingPlano ||
                              _controller.isAnalyzingPlano
                          ? null
                          : _openAttachmentPicker,
                      onSendTap: _sendMessage,
                      isSending: isSending,
                      hintText: _controller.hasPendingPlano
                          ? 'Indica qué revisar en tu plano'
                          : 'Dime tu pregunta',
                    ),
                    if (_controller.askErrorMessage != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                        child: Text(
                          _controller.askErrorMessage!,
                          style: const TextStyle(
                            color: Colors.redAccent,
                            fontSize: 13,
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
