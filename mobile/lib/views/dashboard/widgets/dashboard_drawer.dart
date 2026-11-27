import 'package:flutter/material.dart';
import 'package:movil_architect/controllers/dashboard_controller.dart';
import 'package:movil_architect/core/app_services.dart';
import 'package:movil_architect/core/theme/architect_theme_tokens.dart';
import 'package:movil_architect/core/utils/app_notifications.dart';
import 'package:movil_architect/core/utils/date_utils.dart';
import 'package:movil_architect/models/chat_models.dart';
import 'package:movil_architect/views/shared/skeleton.dart';

class DashboardDrawer extends StatefulWidget {
  const DashboardDrawer({
    super.key,
    required this.controller,
    required this.onNewChat,
    required this.onSettings,
    required this.onChatOpen,
    required this.onStageAdmin,
    required this.onPlans,
    this.onChatDeleted,
  });

  final DashboardController controller;
  final VoidCallback onNewChat;
  final VoidCallback onSettings;
  final ValueChanged<String> onChatOpen;
  final VoidCallback onStageAdmin;
  final VoidCallback onPlans;
  final ValueChanged<String>? onChatDeleted;

  @override
  State<DashboardDrawer> createState() => _DashboardDrawerState();
}

class _DashboardDrawerState extends State<DashboardDrawer> {
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  String? _selectedChatId;
  bool _chatsExpanded = true;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        widget.controller.load(refresh: true);
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  List<ChatSummary> get _filteredChats {
    final query = _searchController.text.trim().toLowerCase();
    final items = widget.controller.chats.where((item) {
      if (item.title == 'Nuevo chat' && item.messageCount == 0) return false;
      return true;
    }).toList();
    if (query.isEmpty) return items;
    return items
        .where((item) => item.title.toLowerCase().contains(query))
        .toList();
  }

  Future<void> _confirmDelete(ChatSummary chat) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cancelBg =
        isDark ? const Color(0xFF3E3E44) : const Color(0xFF6B6B73);
    final dangerBg =
        isDark ? const Color(0xFFD9383A) : const Color(0xFFC8282A);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar conversación'),
        content: Text('¿Borrar "${chat.title}"?'),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context, false),
            style: FilledButton.styleFrom(
              foregroundColor: Colors.white,
              backgroundColor: cancelBg,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              minimumSize: const Size(0, 42),
            ),
            child: Text(
              'Cancelar',
              style: ArchitectThemeTokens.appleText(
                color: Colors.white,
                fontSize: 14.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 4),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              foregroundColor: Colors.white,
              backgroundColor: dangerBg,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              minimumSize: const Size(0, 42),
            ),
            child: Text(
              'Eliminar',
              style: ArchitectThemeTokens.appleText(
                color: Colors.white,
                fontSize: 14.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await widget.controller.deleteChat(chat.id);
      if (_selectedChatId == chat.id) _selectedChatId = null;
      widget.onChatDeleted?.call(chat.id);
      if (mounted) {
        setState(() {});
        AppNotifications.success(context, 'Conversación eliminada');
      }
    } catch (_) {
      if (!mounted) return;
      AppNotifications.error(
        context,
        'No se pudo eliminar la conversación',
      );
    }
  }

  void _openChat(ChatSummary chat) {
    setState(() => _selectedChatId = chat.id);
    Navigator.of(context).pop();
    widget.onChatOpen(chat.id);
  }

  Future<void> _togglePinChat(ChatSummary chat, {required bool wasPinned}) async {
    await widget.controller.togglePinChat(chat.id);
    if (!mounted) return;
    setState(() {});
    AppNotifications.success(
      context,
      wasPinned ? 'Chat desfijado' : 'Chat fijado',
    );
  }

  Future<void> _showChatOptions(
    ChatSummary chat,
    Offset globalPosition,
  ) async {
    final colorScheme = Theme.of(context).colorScheme;
    final tokens = ArchitectThemeTokens.of(context);
    final isPinned = widget.controller.isChatPinned(chat.id);
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;

    final selected = await showMenu<String>(
      context: context,
      color: tokens.surfaceSelected,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ArchitectThemeTokens.radiusLg),
        side: BorderSide(color: tokens.borderSubtle),
      ),
      position: RelativeRect.fromRect(
        Rect.fromLTWH(globalPosition.dx, globalPosition.dy, 1, 1),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem(
          value: 'pin',
          child: Row(
            children: [
              Icon(
                isPinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
                size: 18,
                color: isPinned ? tokens.accent : tokens.textPrimary,
              ),
              const SizedBox(width: 12),
              Text(isPinned ? 'Desfijar' : 'Fijar'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(
                Icons.delete_outline_rounded,
                size: 18,
                color: colorScheme.error,
              ),
              const SizedBox(width: 12),
              Text('Eliminar', style: TextStyle(color: colorScheme.error)),
            ],
          ),
        ),
      ],
    );

    if (!mounted || selected == null) return;

    switch (selected) {
      case 'pin':
        await _togglePinChat(chat, wasPinned: isPinned);
      case 'delete':
        await _confirmDelete(chat);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = ArchitectThemeTokens.of(context);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final drawerWidth =
        (MediaQuery.sizeOf(context).width * 0.82).clamp(288.0, 340.0);

    return Drawer(
      backgroundColor: tokens.drawerBackground,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      width: drawerWidth,
      child: SafeArea(
        child: ListenableBuilder(
          listenable: widget.controller,
          builder: (context, _) {
            final user = widget.controller.user;
            final userLabel = user?.fullName.trim().isNotEmpty == true
                ? user!.fullName.trim()
                : (user?.email.trim().isNotEmpty == true
                    ? user!.email.trim()
                    : 'Usuario');
            final userInitial = user?.fullName.trim().isNotEmpty == true
                ? user!.fullName.trim()[0].toUpperCase()
                : (user?.email.trim().isNotEmpty == true
                    ? user!.email.trim()[0].toUpperCase()
                    : 'U');
            final rawAvatar = user?.avatarUrl?.trim();
            final avatarUrl = (rawAvatar != null && rawAvatar.isNotEmpty)
                ? (rawAvatar.startsWith('http')
                    ? rawAvatar
                    : '${AppServices.instance.apiClient.dio.options.baseUrl}$rawAvatar')
                : null;

            final chats = _filteredChats;
            final activeChatId = widget.controller.activeChatId;
            if (activeChatId != null) {
              _selectedChatId = activeChatId;
            } else if (_selectedChatId != null &&
                chats.every((chat) => chat.id != _selectedChatId)) {
              _selectedChatId = null;
            }

            final hasQuery = _searchController.text.trim().isNotEmpty;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _DrawerBrandHeader(
                  onClose: () => Navigator.of(context).pop(),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                  child: _DrawerSearchBar(
                    controller: _searchController,
                    focusNode: _searchFocusNode,
                    onClear: () {
                      _searchController.clear();
                      _searchFocusNode.requestFocus();
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Column(
                    children: [
                      _DrawerNavItem(
                        icon: Icons.home_work_outlined,
                        label: 'Casa hogar',
                        onTap: () {
                          Navigator.of(context).pop();
                          widget.onStageAdmin();
                        },
                      ),
                      const SizedBox(height: 2),
                      _DrawerNavItem(
                        icon: Icons.workspace_premium_outlined,
                        label: 'Planes',
                        onTap: () {
                          Navigator.of(context).pop();
                          widget.onPlans();
                        },
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                  child: Divider(
                    height: 1,
                    thickness: 1,
                    color: tokens.borderSubtle,
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 2),
                        child: _SectionHeader(
                          title: 'Recientes',
                          count: chats.length,
                          expanded: _chatsExpanded,
                          reduceMotion: reduceMotion,
                          onTap: () =>
                              setState(() => _chatsExpanded = !_chatsExpanded),
                        ),
                      ),
                      if (_chatsExpanded)
                        Expanded(
                          child: RefreshIndicator(
                            color: tokens.accent,
                            onRefresh: () =>
                                widget.controller.load(refresh: true),
                            child: _buildHistoryContent(
                              context: context,
                              tokens: tokens,
                              chats: chats,
                              hasQuery: hasQuery,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                _DrawerProfileFooter(
                  name: userLabel,
                  initial: userInitial,
                  avatarUrl: avatarUrl,
                  onNewChat: () {
                    Navigator.of(context).pop();
                    widget.onNewChat();
                  },
                  onProfileTap: () {
                    Navigator.of(context).pop();
                    widget.onSettings();
                  },
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildHistoryContent({
    required BuildContext context,
    required ArchitectThemeTokens tokens,
    required List<ChatSummary> chats,
    required bool hasQuery,
  }) {
    if (widget.controller.state == DashboardState.loading) {
      return const ChatHistorySkeleton();
    }

    if (widget.controller.state == DashboardState.error && chats.isEmpty) {
      return LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.sync_problem_rounded,
                        size: 28,
                        color: tokens.textSecondary,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        widget.controller.errorMessage ??
                            'No se pudieron sincronizar las conversaciones.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: tokens.textSecondary,
                          fontSize: 13,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextButton.icon(
                        onPressed: () => widget.controller.load(refresh: true),
                        icon: const Icon(Icons.refresh_rounded, size: 16),
                        label: const Text('Reintentar'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      );
    }

    if (chats.isEmpty) {
      return LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Center(
                child: _HistoryEmptyMessage(
                  message: hasQuery
                      ? 'No hay conversaciones que coincidan con tu búsqueda.'
                      : 'Aún no tienes conversaciones.\nInicia un nuevo chat arriba.',
                ),
              ),
            ),
          );
        },
      );
    }

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(12, 2, 12, 12),
      itemCount: chats.length,
      itemBuilder: (context, index) {
        final item = chats[index];
        return _ChatHistoryTile(
          title: item.title,
          subtitle: formatRelativeTime(item.updatedAt),
          selected: item.id == _selectedChatId,
          pinned: widget.controller.isChatPinned(item.id),
          onTap: () => _openChat(item),
          onOptionsTap: (position) => _showChatOptions(item, position),
        );
      },
    );
  }
}

class _DrawerBrandHeader extends StatelessWidget {
  const _DrawerBrandHeader({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final tokens = ArchitectThemeTokens.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
      child: Row(
        children: [
          Container(
            width: 2.5,
            height: 18,
            decoration: BoxDecoration(
              color: tokens.accent,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                'ARCHITECT',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: ArchitectThemeTokens.appleDisplay(
                  color: tokens.textPrimary,
                  fontSize: 17.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 3.6,
                ),
              ),
            ),
          ),
          Semantics(
            button: true,
            label: 'Cerrar menú',
            child: IconButton(
              onPressed: onClose,
              tooltip: 'Cerrar menú',
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
              icon: Icon(
                Icons.close_rounded,
                size: 20,
                color: tokens.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DrawerSearchBar extends StatefulWidget {
  const _DrawerSearchBar({
    required this.controller,
    required this.focusNode,
    required this.onClear,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onClear;

  @override
  State<_DrawerSearchBar> createState() => _DrawerSearchBarState();
}

class _DrawerSearchBarState extends State<_DrawerSearchBar> {
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_handleFocus);
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_handleFocus);
    super.dispose();
  }

  void _handleFocus() {
    if (mounted) {
      setState(() => _focused = widget.focusNode.hasFocus);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = ArchitectThemeTokens.of(context);
    final hasText = widget.controller.text.isNotEmpty;

    return Semantics(
      textField: true,
      label: 'Buscar conversaciones',
      child: AnimatedContainer(
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 160),
        decoration: BoxDecoration(
          color: tokens.surfaceSecondary,
          borderRadius: BorderRadius.circular(ArchitectThemeTokens.radiusMd),
          border: Border.all(
            color: _focused ? tokens.accent : tokens.borderSubtle,
            width: 1,
          ),
        ),
        child: TextField(
          controller: widget.controller,
          focusNode: widget.focusNode,
          textInputAction: TextInputAction.search,
          style: ArchitectThemeTokens.appleText(
            color: tokens.textPrimary,
            fontSize: 15,
            fontWeight: FontWeight.w400,
          ),
          decoration: InputDecoration(
            isDense: true,
            hintText: 'Buscar conversaciones',
            hintStyle: ArchitectThemeTokens.appleText(
              color: tokens.textSecondary,
              fontSize: 15,
            ),
            prefixIcon: Icon(
              Icons.search_rounded,
              color: _focused ? tokens.accent : tokens.textSecondary,
              size: 19,
            ),
            prefixIconConstraints: const BoxConstraints(
              minWidth: 40,
              minHeight: 44,
            ),
            suffixIcon: hasText
                ? IconButton(
                    onPressed: widget.onClear,
                    tooltip: 'Limpiar búsqueda',
                    constraints: const BoxConstraints(
                      minWidth: 40,
                      minHeight: 44,
                    ),
                    icon: Icon(
                      Icons.close_rounded,
                      color: tokens.textSecondary,
                      size: 17,
                    ),
                  )
                : null,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 11,
            ),
          ),
        ),
      ),
    );
  }
}

class _NewChatAction extends StatelessWidget {
  const _NewChatAction({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = ArchitectThemeTokens.of(context);

    return Semantics(
      button: true,
      label: 'Iniciar nuevo chat',
      child: Material(
        color: tokens.primaryActionBg,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 46),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.edit_outlined,
                    color: tokens.primaryActionFg,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Nuevo chat',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: ArchitectThemeTokens.appleText(
                      color: tokens.primaryActionFg,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.24,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DrawerNavItem extends StatelessWidget {
  const _DrawerNavItem({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = ArchitectThemeTokens.of(context);

    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(ArchitectThemeTokens.radiusMd),
        child: InkWell(
          onTap: onTap,
          hoverColor: tokens.interactionOverlay,
          splashColor: tokens.interactionOverlay,
          borderRadius: BorderRadius.circular(ArchitectThemeTokens.radiusMd),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 46),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              child: Row(
                children: [
                  Icon(
                    icon,
                    color: tokens.textPrimary,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: ArchitectThemeTokens.appleText(
                        color: tokens.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: tokens.textSecondary,
                    size: 18,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.count,
    required this.expanded,
    required this.reduceMotion,
    required this.onTap,
  });

  final String title;
  final int count;
  final bool expanded;
  final bool reduceMotion;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = ArchitectThemeTokens.of(context);

    return Semantics(
      button: true,
      label: '$title, $count conversaciones. ${expanded ? 'Contraer' : 'Expandir'}',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(ArchitectThemeTokens.radiusSm),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 40),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Text(
                          title.toUpperCase(),
                          style: ArchitectThemeTokens.appleText(
                            color: tokens.textSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1.4,
                          ),
                        ),
                        if (count > 0) ...[
                          const SizedBox(width: 6),
                          Text(
                            '$count',
                            style: ArchitectThemeTokens.appleText(
                              color: tokens.textSecondary,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              letterSpacing: 0,
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  AnimatedRotation(
                    turns: expanded ? 0.5 : 0,
                    duration: reduceMotion
                        ? Duration.zero
                        : const Duration(milliseconds: 180),
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: tokens.textSecondary,
                      size: 20,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HistoryEmptyMessage extends StatelessWidget {
  const _HistoryEmptyMessage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final tokens = ArchitectThemeTokens.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: tokens.textSecondary,
          fontSize: 13.5,
          height: 1.45,
        ),
      ),
    );
  }
}

class _ChatHistoryTile extends StatelessWidget {
  const _ChatHistoryTile({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
    this.pinned = false,
    this.onOptionsTap,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final bool pinned;
  final VoidCallback onTap;
  final ValueChanged<Offset>? onOptionsTap;

  @override
  Widget build(BuildContext context) {
    final tokens = ArchitectThemeTokens.of(context);
    final textScale = MediaQuery.textScalerOf(context).scale(1.0);
    final maxTitleLines = textScale > 1.3 ? 2 : 1;

    void triggerOptionsFromWidget(BuildContext targetContext) {
      if (onOptionsTap == null) return;
      final box = targetContext.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) return;
      final origin = box.localToGlobal(Offset.zero);
      onOptionsTap!(
        origin + Offset(box.size.width - 12, box.size.height / 2),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Semantics(
        selected: selected,
        button: true,
        label: '$title, $subtitle${pinned ? ', fijado' : ''}',
        child: Material(
          color: selected ? tokens.surfaceSelected : Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ArchitectThemeTokens.radiusMd),
            side: selected
                ? BorderSide(color: tokens.borderStrong, width: 1)
                : BorderSide.none,
          ),
          child: InkWell(
            onTap: onTap,
            onLongPress: onOptionsTap == null
                ? null
                : () => triggerOptionsFromWidget(context),
            hoverColor: tokens.interactionOverlay,
            splashColor: tokens.interactionOverlay,
            borderRadius: BorderRadius.circular(ArchitectThemeTokens.radiusMd),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 52),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 9, 4, 9),
                child: Row(
                  children: [
                    AnimatedContainer(
                      duration: MediaQuery.disableAnimationsOf(context)
                          ? Duration.zero
                          : const Duration(milliseconds: 160),
                      width: 2.5,
                      height: selected ? 20 : 0,
                      margin: EdgeInsets.only(right: selected ? 9 : 0),
                      decoration: BoxDecoration(
                        color: tokens.accent,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              if (pinned) ...[
                                Icon(
                                  Icons.push_pin_rounded,
                                  size: 13,
                                  color: tokens.accent,
                                ),
                                const SizedBox(width: 5),
                              ],
                              Expanded(
                                child: Text(
                                  title,
                                  maxLines: maxTitleLines,
                                  overflow: TextOverflow.ellipsis,
                                  style: ArchitectThemeTokens.appleText(
                                    color: tokens.textPrimary,
                                    fontSize: 15.5,
                                    fontWeight: selected
                                        ? FontWeight.w600
                                        : FontWeight.w500,
                                    height: 1.25,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: ArchitectThemeTokens.appleText(
                              color: tokens.textSecondary,
                              fontSize: 13,
                              fontWeight: FontWeight.w400,
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (onOptionsTap != null)
                      Builder(
                        builder: (btnContext) => Semantics(
                          button: true,
                          label: 'Opciones de $title',
                          child: IconButton(
                            onPressed: () => triggerOptionsFromWidget(btnContext),
                            tooltip: 'Opciones',
                            constraints: const BoxConstraints(
                              minWidth: 40,
                              minHeight: 40,
                            ),
                            padding: EdgeInsets.zero,
                            icon: Icon(
                              Icons.more_horiz_rounded,
                              size: 18,
                              color: tokens.textSecondary,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DrawerProfileFooter extends StatelessWidget {
  const _DrawerProfileFooter({
    required this.name,
    required this.initial,
    required this.avatarUrl,
    required this.onNewChat,
    required this.onProfileTap,
  });

  final String name;
  final String initial;
  final String? avatarUrl;
  final VoidCallback onNewChat;
  final VoidCallback onProfileTap;

  @override
  Widget build(BuildContext context) {
    final tokens = ArchitectThemeTokens.of(context);

    Widget buildInitial() {
      return Center(
        child: Text(
          initial,
          style: ArchitectThemeTokens.appleDisplay(
            color: tokens.textPrimary,
            fontWeight: FontWeight.w600,
            fontSize: 17,
            letterSpacing: 0,
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      child: Row(
        children: [
          _NewChatAction(onTap: onNewChat),
          const Spacer(),
          Semantics(
            button: true,
            label: 'Abrir perfil y ajustes de $name',
            child: Tooltip(
              message: 'Perfil y ajustes',
              child: Material(
                color: tokens.surfaceSecondary,
                shape: CircleBorder(
                  side: BorderSide(color: tokens.borderStrong, width: 1),
                ),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: onProfileTap,
                  customBorder: const CircleBorder(),
                  hoverColor: tokens.interactionOverlay,
                  splashColor: tokens.interactionOverlay,
                  child: SizedBox(
                    width: 46,
                    height: 46,
                    child: avatarUrl != null
                        ? Image.network(
                            avatarUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => buildInitial(),
                          )
                        : buildInitial(),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
