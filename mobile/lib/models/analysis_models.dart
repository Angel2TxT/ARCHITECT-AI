import 'package:movil_architect/models/auth_models.dart';

class AnalysisCounts {
  const AnalysisCounts({
    required this.errors,
    required this.warnings,
    required this.detections,
  });

  final int errors;
  final int warnings;
  final int detections;

  factory AnalysisCounts.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const AnalysisCounts(errors: 0, warnings: 0, detections: 0);
    }
    return AnalysisCounts(
      errors: json['errors'] as int? ?? 0,
      warnings: json['warnings'] as int? ?? 0,
      detections: json['detections'] as int? ?? 0,
    );
  }
}

class AnalysisSummary {
  const AnalysisSummary({
    required this.id,
    required this.chatId,
    required this.filename,
    required this.createdAt,
    required this.counts,
    required this.isDemoModel,
    required this.userPrompt,
  });

  final int id;
  final String chatId;
  final String filename;
  final DateTime? createdAt;
  final AnalysisCounts counts;
  final bool isDemoModel;
  final String? userPrompt;

  factory AnalysisSummary.fromJson(Map<String, dynamic> json) {
    return AnalysisSummary(
      id: json['id'] as int,
      chatId: json['chat_id'] as String? ?? '',
      filename: json['filename'] as String? ?? 'plano',
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String)
          : null,
      counts: AnalysisCounts.fromJson(
        json['counts'] as Map<String, dynamic>?,
      ),
      isDemoModel: json['is_demo_model'] as bool? ?? false,
      userPrompt: json['user_prompt'] as String?,
    );
  }
}

class VerdictModel {
  const VerdictModel({
    required this.tone,
    required this.headline,
    required this.detail,
    required this.suggestions,
  });

  final String tone;
  final String headline;
  final String detail;
  final List<String> suggestions;

  factory VerdictModel.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const VerdictModel(
        tone: 'unknown',
        headline: 'Sin veredicto',
        detail: '',
        suggestions: [],
      );
    }
    return VerdictModel(
      tone: json['tone'] as String? ?? 'unknown',
      headline: json['headline'] as String? ?? '',
      detail: json['detail'] as String? ?? '',
      suggestions: (json['suggestions'] as List<dynamic>? ?? [])
          .map((item) => item.toString())
          .toList(),
    );
  }
}

class IssueModel {
  const IssueModel({
    required this.title,
    required this.detail,
    required this.severity,
  });

  final String title;
  final String detail;
  final String severity;

  factory IssueModel.fromJson(Map<String, dynamic> json) {
    return IssueModel(
      title: json['title'] as String? ??
          json['label'] as String? ??
          json['headline'] as String? ??
          'Incidencia',
      detail: json['detail'] as String? ??
          json['message'] as String? ??
          json['description'] as String? ??
          '',
      severity: json['severity'] as String? ??
          json['level'] as String? ??
          json['tone'] as String? ??
          'warning',
    );
  }
}

class AnalysisResult {
  const AnalysisResult({
    required this.status,
    required this.analysisId,
    required this.chatId,
    required this.verdict,
    required this.issues,
    required this.counts,
    required this.imageBase64,
    required this.markdown,
    required this.subscription,
    this.assistantText,
    this.detections = const [],
  });

  final String status;
  final int? analysisId;
  final String? chatId;
  final VerdictModel verdict;
  final List<IssueModel> issues;
  final AnalysisCounts counts;
  final String? imageBase64;
  final String? markdown;
  final SubscriptionModel? subscription;
  final String? assistantText;
  final List<DetectionModel> detections;

  factory AnalysisResult.fromJson(Map<String, dynamic> json) {
    final detections = json['detections'];
    return AnalysisResult(
      status: json['status'] as String? ?? 'ok',
      analysisId: json['analysis_id'] as int?,
      chatId: json['chat_id'] as String?,
      verdict: VerdictModel.fromJson(json['verdict'] as Map<String, dynamic>?),
      issues: (json['issues'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(IssueModel.fromJson)
          .toList(),
      counts: AnalysisCounts.fromJson(json['counts'] as Map<String, dynamic>?),
      imageBase64: json['image_base64'] as String?,
      markdown: _parseMarkdown(json['markdown']),
      subscription: json['subscription'] is Map<String, dynamic>
          ? SubscriptionModel.fromJson(
              json['subscription'] as Map<String, dynamic>,
            )
          : null,
      assistantText: json['assistant_text'] as String? ??
          json['text'] as String? ??
          json['message'] as String?,
      detections: detections is List
          ? [
              for (var i = 0; i < detections.length; i++)
                if (detections[i] is Map)
                  DetectionModel.fromJson(
                    Map<String, dynamic>.from(detections[i] as Map),
                    fallbackIndex: i,
                  ),
            ]
          : const [],
    );
  }

  static String? _parseMarkdown(dynamic value) {
    if (value == null) return null;
    if (value is String) return value;
    if (value is Map) {
      final detections = value['detections']?.toString() ?? '';
      final issues = value['issues']?.toString() ?? '';
      return '$detections\n\n$issues'.trim();
    }
    return value.toString();
  }
}

class DetectionModel {
  const DetectionModel({
    required this.index,
    required this.className,
    required this.label,
  });

  final int index;
  final String className;
  final String label;

  static const classOptions = ['wall', 'door', 'window', 'room'];

  factory DetectionModel.fromJson(
    Map<String, dynamic> json, {
    int fallbackIndex = 0,
  }) {
    final className = (json['class'] ?? json['new_class'] ?? json['label'] ?? '')
        .toString();
    return DetectionModel(
      index: (json['detection_index'] as num?)?.toInt() ??
          (json['index'] as num?)?.toInt() ??
          fallbackIndex,
      className: className,
      label: json['label'] as String? ?? className,
    );
  }
}
