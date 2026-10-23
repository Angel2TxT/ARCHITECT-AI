import 'package:flutter/material.dart';
import 'package:movil_architect/core/app_services.dart';
import 'package:movil_architect/core/network/api_exception.dart';
import 'package:movil_architect/core/theme/app_colors.dart';
import 'package:movil_architect/core/utils/app_notifications.dart';
import 'package:movil_architect/models/support_models.dart';
import 'package:movil_architect/views/login/widgets/login_widgets.dart';

class SupportTicketView extends StatefulWidget {
  const SupportTicketView({super.key, required this.ticketId});

  final String ticketId;

  @override
  State<SupportTicketView> createState() => _SupportTicketViewState();
}

class _SupportTicketViewState extends State<SupportTicketView> {
  SupportTicketDetail? _detail;
  bool _loading = true;
  String? _error;
  final _reply = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _reply.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _detail =
          await AppServices.instance.supportService.getTicket(widget.ticketId);
    } on ApiException catch (error) {
      _error = error.message;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _send() async {
    try {
      await AppServices.instance.supportService.addMessage(
        ticketId: widget.ticketId,
        body: _reply.text,
      );
      _reply.clear();
      await _load();
      if (!mounted) return;
      AppNotifications.success(context, 'Respuesta enviada');
    } on ApiException catch (error) {
      if (!mounted) return;
      AppNotifications.error(context, error.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final closed = _detail?.ticket.isClosed ?? false;
    return Scaffold(
      appBar: AppBar(
        title: Text(_detail?.ticket.subject ?? 'Ticket'),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Colors.redAccent),
                    ),
                  ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      ...?_detail?.messages.map(
                        (message) => Align(
                          alignment: message.isStaff
                              ? Alignment.centerLeft
                              : Alignment.centerRight,
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: message.isStaff
                                  ? AppColors.loginFieldFill
                                  : AppColors.ink,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Text(
                              message.body,
                              style: TextStyle(
                                color: message.isStaff
                                    ? AppColors.ink
                                    : Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (!closed)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: LoginPillField(
                            controller: _reply,
                            hint: 'RESPUESTA',
                          ),
                        ),
                        IconButton(
                          onPressed: _send,
                          icon: const Icon(Icons.send),
                        ),
                      ],
                    ),
                  )
                else
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'Este ticket está cerrado.',
                      style: TextStyle(color: AppColors.muted),
                    ),
                  ),
              ],
            ),
    );
  }
}
