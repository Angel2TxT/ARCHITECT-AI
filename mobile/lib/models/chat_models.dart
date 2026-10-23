import 'package:movil_architect/models/analysis_models.dart';

class ChatSummary {
  const ChatSummary({
    required this.id,
    required this.title,
    required this.updatedAt,
    required this.messageCount,
  });

  final String id;
  final String title;
  final DateTime? updatedAt;
  final int messageCount;

  factory ChatSummary.fromJson(Map<String, dynamic> json) {
    final count = json['message_count'] as int? ??
        json['messages_count'] as int? ??
        (json['messages'] is List ? (json['messages'] as List).length : 0);
    return ChatSummary(
      id: (json['id'] ?? '').toString(),
      title: json['title'] as String? ?? 'Conversación',
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'] as String)
          : null,
      messageCount: count,
    );
  }

  ChatSummary copyWith({
    String? id,
    String? title,
    DateTime? updatedAt,
    int? messageCount,
  }) {
    return ChatSummary(
      id: id ?? this.id,
      title: title ?? this.title,
      updatedAt: updatedAt ?? this.updatedAt,
      messageCount: messageCount ?? this.messageCount,
    );
  }
}

class MessageContent {
  const MessageContent({
    this.text,
    this.filename,
    this.analysisId,
    this.verdict,
    this.imageBase64,
    this.stats,
    this.hasImage = false,
  });

  final String? text;
  final String? filename;
  final int? analysisId;
  final VerdictModel? verdict;
  final String? imageBase64;
  final AnalysisCounts? stats;
  final bool hasImage;

  /// True cuando el historial no trae `image_base64` pero hay `analysis_id`.
  bool get needsAnnotatedImage {
    if (imageBase64 != null && imageBase64!.trim().isNotEmpty) return false;
    return analysisId != null;
  }

  factory MessageContent.fromJson(dynamic json) {
    if (json == null) return const MessageContent();
    if (json is String) return MessageContent(text: json);

    final map = json as Map<String, dynamic>;
    final analysisId = (map['analysis_id'] as num?)?.toInt();
    final imageBase64 = _readImageBase64(map);
    final hasImageFlag = map['has_image'] == true || map['hasImage'] == true;
    return MessageContent(
      text: map['text'] as String?,
      filename: map['filename'] as String? ??
          map['original_filename'] as String? ??
          map['file_name'] as String?,
      analysisId: analysisId,
      verdict: map['verdict'] is Map<String, dynamic>
          ? VerdictModel.fromJson(map['verdict'] as Map<String, dynamic>)
          : null,
      imageBase64: imageBase64,
      stats: map['stats'] is Map<String, dynamic>
          ? AnalysisCounts.fromJson(map['stats'] as Map<String, dynamic>)
          : null,
      hasImage: hasImageFlag ||
          (imageBase64 != null && imageBase64.trim().isNotEmpty),
    );
  }

  MessageContent copyWith({
    String? text,
    String? filename,
    int? analysisId,
    VerdictModel? verdict,
    String? imageBase64,
    AnalysisCounts? stats,
    bool? hasImage,
  }) {
    return MessageContent(
      text: text ?? this.text,
      filename: filename ?? this.filename,
      analysisId: analysisId ?? this.analysisId,
      verdict: verdict ?? this.verdict,
      imageBase64: imageBase64 ?? this.imageBase64,
      stats: stats ?? this.stats,
      hasImage: hasImage ?? this.hasImage,
    );
  }

  static String? _readImageBase64(Map<String, dynamic> map) {
    for (final key in [
      'image_base64',
      'imageBase64',
      'thumbnail_base64',
      'file_base64',
      'image',
    ]) {
      final value = map[key];
      if (value is String && value.trim().isNotEmpty) return value;
    }
    return null;
  }
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.createdAt,
  });

  final int id;
  final String role;
  final MessageContent content;
  final DateTime? createdAt;

  bool get isUser => role == 'user';
  bool get isAssistant => role == 'assistant';

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: (json['id'] as num?)?.toInt() ?? 0,
      role: json['role'] as String? ?? 'user',
      content: MessageContent.fromJson(json['content']),
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String)
          : null,
    );
  }

  ChatMessage copyWith({
    int? id,
    String? role,
    MessageContent? content,
    DateTime? createdAt,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      role: role ?? this.role,
      content: content ?? this.content,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

class ChatDetail {
  const ChatDetail({
    required this.chat,
    required this.messages,
  });

  final ChatSummary chat;
  final List<ChatMessage> messages;

  factory ChatDetail.fromJson(Map<String, dynamic> json) {
    final chatJson = json['chat'] as Map<String, dynamic>? ?? {};
    return ChatDetail(
      chat: ChatSummary.fromJson(chatJson),
      messages: (json['messages'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(ChatMessage.fromJson)
          .toList(),
    );
  }

  int? get lastAnalysisId {
    for (var i = messages.length - 1; i >= 0; i--) {
      final id = messages[i].content.analysisId;
      if (id != null) return id;
    }
    return null;
  }

  ChatDetail withAnnotatedImage({
    required int analysisId,
    required String imageBase64,
  }) {
    final value = imageBase64.trim();
    if (value.isEmpty) return this;
    return ChatDetail(
      chat: chat,
      messages: [
        for (final message in messages)
          if (message.isAssistant &&
              message.content.analysisId == analysisId &&
              (message.content.imageBase64 == null ||
                  message.content.imageBase64!.trim().isEmpty))
            message.copyWith(
              content: message.content.copyWith(
                imageBase64: value,
                hasImage: true,
              ),
            )
          else
            message,
      ],
    );
  }
}

class AskResponse {
  const AskResponse({this.chatId, this.text});

  final String? chatId;
  final String? text;

  factory AskResponse.fromJson(Map<String, dynamic> json) {
    String? text = json['text'] as String? ??
        json['answer'] as String? ??
        json['message'] as String? ??
        json['markdown'] as String?;
    final content = json['content'];
    if ((text == null || text.isEmpty) && content is Map) {
      text = content['text'] as String?;
    }
    return AskResponse(
      chatId: json['chat_id'] as String?,
      text: text,
    );
  }
}
