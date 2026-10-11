import 'package:flutter/material.dart';
import 'package:movil_architect/controllers/dashboard_controller.dart';
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
  bool _searchVisible = false;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _toggleSearch() {
    setState(() {
      _searchVisible = !_searchVisible;
      if (!_searchVisible) {
        _searchController.clear();
        _searchFocusNode.unfocus();
      }
    });
    if (_searchVisible) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _searchFocusNode.requestFocus();
      });
    }
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar conversación'),
        content: Text('¿Borrar "${chat.title}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar', style: TextStyle(color: Colors.red)),
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

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final drawerColor = colorScheme.brightness == Brightness.dark
        ? colorScheme.surface
        : const Color(0xFFEFEFEF);

    return Drawer(
      backgroundColor: drawerColor,
      width: (MediaQuery.sizeOf(context).width * 0.80).clamp(280.0, 320.0),
      child: SafeArea(
        child: ListenableBuilder(
          listenable: widget.controller,
          builder: (context, _) {
            final user = widget.controller.user;
            final userLabel = user?.fullName.isNotEmpty == true
                ? user!.fullName
                : user?.email ?? 'Usuario';
            final chats = _filteredChats;
            final activeChatId = widget.controller.activeChatId;
            if (activeChatId != null) {
              _selectedChatId = activeChatId;
            } else if (_selectedChatId != null &&
                chats.every((chat) => chat.id != _selectedChatId)) {
              _selectedChatId = null;
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: Text(
                            'ARCHITECT',
                            style: TextStyle(
                              color: colorScheme.onSurface,
                              fontSize: 28,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 3,
                            ),
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: _toggleSearch,
                        tooltip: _searchVisible
                            ? 'Cerrar búsqueda'
                            : 'Buscar chats',
                        icon: Icon(
                          _searchVisible ? Icons.close_rounded : Icons.search,
                          color: colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.topCenter,
                  child: _searchVisible
                      ? Padding(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                          child: _SearchField(
                            controller: _searchController,
                            focusNode: _searchFocusNode,
                            onClear: () {
                              _searchController.clear();
                              _searchFocusNode.requestFocus();
                            },
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
                  child: Column(
                    children: [
                      _DrawerNavModule(
                        icon: Icons.home_work_outlined,
                        label: 'Casa hogar',
                        onTap: () {
                          Navigator.of(context).pop();
                          widget.onStageAdmin();
                        },
                      ),
                      const SizedBox(height: 8),
                      _DrawerNavModule(
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
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(10, 16, 10, 0),
                        child: _CollapsibleHistoryHeader(
                          title: 'RECIENTES',
                          expanded: _chatsExpanded,
                          onTap: () =>
                              setState(() => _chatsExpanded = !_chatsExpanded),
                        ),
                      ),
                      if (_chatsExpanded)
                        Expanded(
                          child: RefreshIndicator(
                            onRefresh: () =>
                                widget.controller.load(refresh: true),
                            child: widget.controller.state ==
                                    DashboardState.loading
                                ? const ChatHistorySkeleton()
                                : chats.isEmpty
                                ? LayoutBuilder(
                                    builder: (context, constraints) {
                                      return SingleChildScrollView(
                                        physics:
                                            const AlwaysScrollableScrollPhysics(),
                                        child: ConstrainedBox(
                                          constraints: BoxConstraints(
                                            minHeight: constraints.maxHeight,
                                          ),
                                            child: const Center(
                                            child: _HistoryEmptyMessage(
                                              message:
                                                  'No hay chats recientes.\nUsa Chat abajo.',
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                                  )
                                : ListView(
                                    physics:
                                        const AlwaysScrollableScrollPhysics(),
                                    padding: const EdgeInsets.fromLTRB(
                                      10,
                                      4,
                                      10,
                                      8,
                                    ),
                                    children: [
                                      for (final item in chats)
                                        _ChatHistoryTile(
                                          title: item.title,
                                          subtitle: formatRelativeTime(
                                            item.updatedAt,
                                          ),
                                          selected:
                                              item.id == _selectedChatId,
                                          pinned: widget.controller
                                              .isChatPinned(item.id),
                                          onTap: () => _openChat(item),
                                          onLongPress: (position) =>
                                              _showChatOptions(item, position),
                                        ),
                                    ],
                                  ),
                          ),
                        ),
                    ],
                  ),
                ),
                _DrawerUserFooter(
                  name: userLabel,
                  onSettings: () {
                    Navigator.of(context).pop();
                    widget.onSettings();
                  },
                  onNewChat: () {
                    Navigator.of(context).pop();
                    widget.onNewChat();
                  },
                ),
              ],
            );
          },
        ),
      ),
    );
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
    final isPinned = widget.controller.isChatPinned(chat.id);
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;

    final selected = await showMenu<String>(
      context: context,
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
                isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                size: 20,
                color: colorScheme.onSurface,
              ),
              const SizedBox(width: 12),
              Text(isPinned ? 'Desfijar' : 'Fijar'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete_outline, size: 20, color: Colors.red),
              SizedBox(width: 12),
              Text('Eliminar', style: TextStyle(color: Colors.red)),
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
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    this.focusNode,
    this.onClear,
  });

  final TextEditingController controller;
  final FocusNode? focusNode;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final fillColor = colorScheme.brightness == Brightness.dark
        ? colorScheme.surfaceContainerHighest
        : const Color(0xFFE4E4E6);
    final hasText = controller.text.isNotEmpty;

    return TextField(
      controller: controller,
      focusNode: focusNode,
      autofocus: true,
      style: TextStyle(color: colorScheme.onSurface, fontSize: 15),
      decoration: InputDecoration(
        hintText: 'Buscar chats',
        hintStyle: TextStyle(color: colorScheme.onSurfaceVariant),
        prefixIcon: Icon(
          Icons.search,
          color: colorScheme.onSurfaceVariant,
          size: 22,
        ),
        suffixIcon: hasText
            ? IconButton(
                onPressed: onClear,
                icon: Icon(
                  Icons.clear_rounded,
                  color: colorScheme.onSurfaceVariant,
                  size: 20,
                ),
              )
            : null,
        filled: true,
        fillColor: fillColor,
        contentPadding: const EdgeInsets.symmetric(vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(999),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

class _NewChatButton extends StatelessWidget {
  const _NewChatButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = colorScheme.brightness == Brightness.dark;
    final bgColor = isDark ? colorScheme.onSurface : Colors.black;
    final fgColor = isDark ? colorScheme.surface : Colors.white;

    return Material(
      color: bgColor,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add, color: fgColor, size: 22),
              const SizedBox(width: 6),
              Text(
                'Chat',
                style: TextStyle(
                  color: fgColor,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DrawerNavModule extends StatelessWidget {
  const _DrawerNavModule({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final fillColor = colorScheme.brightness == Brightness.dark
        ? colorScheme.surfaceContainerHighest
        : const Color(0xFFE4E4E6);

    return Material(
      color: fillColor,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(
                icon,
                color: colorScheme.onSurface,
                size: 22,
              ),
              const SizedBox(width: 10),
              Text(
                label,
                style: TextStyle(
                  color: colorScheme.onSurface,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CollapsibleHistoryHeader extends StatelessWidget {
  const _CollapsibleHistoryHeader({
    required this.title,
    required this.expanded,
    required this.onTap,
  });

  final String title;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: colorScheme.onSurfaceVariant,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              AnimatedRotation(
                turns: expanded ? 0.5 : 0,
                duration: const Duration(milliseconds: 200),
                child: Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: colorScheme.onSurfaceVariant,
                  size: 22,
                ),
              ),
            ],
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
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: colorScheme.onSurfaceVariant,
          fontSize: 13,
          height: 1.4,
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
    this.onLongPress,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final bool pinned;
  final VoidCallback onTap;
  final ValueChanged<Offset>? onLongPress;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final selectedColor = colorScheme.brightness == Brightness.dark
        ? colorScheme.surfaceContainerHighest
        : Colors.white;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: selected ? selectedColor : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress == null
              ? null
              : () {
                  final box = context.findRenderObject() as RenderBox?;
                  if (box == null || !box.hasSize) return;
                  final origin = box.localToGlobal(Offset.zero);
                  onLongPress!(
                    origin + Offset(box.size.width - 24, box.size.height / 2),
                  );
                },
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                if (pinned) ...[
                  Icon(
                    Icons.push_pin,
                    size: 16,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colorScheme.onSurface,
                          fontSize: 15,
                          fontWeight:
                              selected ? FontWeight.w800 : FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: colorScheme.onSurfaceVariant,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DrawerUserFooter extends StatelessWidget {
  const _DrawerUserFooter({
    required this.name,
    required this.onSettings,
    required this.onNewChat,
  });

  final String name;
  final VoidCallback onSettings;
  final VoidCallback onNewChat;

  @override
  Widget build(BuildContext context) {
    final initial = name.isNotEmpty ? name[0].toUpperCase() : 'U';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Row(
        children: [
          _NewChatButton(onTap: onNewChat),
          const Spacer(),
          Material(
            color: const Color(0xFFF4CFCF),
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onSettings,
              customBorder: const CircleBorder(),
              child: SizedBox(
                width: 52,
                height: 52,
                child: Center(
                  child: Text(
                    initial,
                    style: const TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.w800,
                      fontSize: 20,
                    ),
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
