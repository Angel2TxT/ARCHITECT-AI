class SupportTicket {
  const SupportTicket({
    required this.id,
    required this.subject,
    required this.status,
    required this.priority,
    this.preview,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String subject;
  final String status;
  final String priority;
  final String? preview;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isClosed => status.toLowerCase() == 'closed';

  factory SupportTicket.fromJson(Map<String, dynamic> json) {
    return SupportTicket(
      id: (json['id'] ?? json['ticket_id'] ?? '').toString(),
      subject: json['subject'] as String? ?? 'Ticket',
      status: json['status'] as String? ?? 'open',
      priority: json['priority'] as String? ?? 'normal',
      preview: json['preview'] as String? ?? json['body'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString())
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'].toString())
          : null,
    );
  }
}

class SupportMessage {
  const SupportMessage({
    required this.id,
    required this.body,
    required this.isStaff,
    this.createdAt,
  });

  final String id;
  final String body;
  final bool isStaff;
  final DateTime? createdAt;

  factory SupportMessage.fromJson(Map<String, dynamic> json) {
    final role = (json['role'] ?? json['sender'] ?? '').toString().toLowerCase();
    return SupportMessage(
      id: (json['id'] ?? '').toString(),
      body: json['body'] as String? ?? json['message'] as String? ?? '',
      isStaff: json['is_staff'] == true ||
          role.contains('admin') ||
          role.contains('support') ||
          role.contains('staff'),
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString())
          : null,
    );
  }
}

class SupportTicketDetail {
  const SupportTicketDetail({
    required this.ticket,
    required this.messages,
  });

  final SupportTicket ticket;
  final List<SupportMessage> messages;

  factory SupportTicketDetail.fromJson(Map<String, dynamic> json) {
    final ticketJson = json['ticket'] is Map
        ? Map<String, dynamic>.from(json['ticket'] as Map)
        : json;
    final list = json['messages'] ?? json['thread'] ?? json['items'];
    return SupportTicketDetail(
      ticket: SupportTicket.fromJson(Map<String, dynamic>.from(ticketJson)),
      messages: list is List
          ? list
              .whereType<Map>()
              .map((e) => SupportMessage.fromJson(Map<String, dynamic>.from(e)))
              .toList()
          : const [],
    );
  }
}
