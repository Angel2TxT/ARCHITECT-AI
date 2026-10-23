class GuestStatus {
  const GuestStatus({
    required this.guest,
    required this.analysesUsed,
    required this.analysesLimit,
    required this.analysesRemaining,
    required this.asksUsed,
    required this.asksLimit,
    required this.asksRemaining,
    required this.trialAvailable,
    required this.trialExhausted,
    required this.maxFileMb,
  });

  final bool guest;
  final int analysesUsed;
  final int analysesLimit;
  final int analysesRemaining;
  final int asksUsed;
  final int asksLimit;
  final int asksRemaining;
  final bool trialAvailable;
  final bool trialExhausted;
  final int maxFileMb;

  factory GuestStatus.fromJson(Map<String, dynamic> json) {
    return GuestStatus(
      guest: json['guest'] as bool? ?? true,
      analysesUsed: (json['analyses_used'] as num?)?.toInt() ?? 0,
      analysesLimit: (json['analyses_limit'] as num?)?.toInt() ?? 1,
      analysesRemaining: (json['analyses_remaining'] as num?)?.toInt() ?? 0,
      asksUsed: (json['asks_used'] as num?)?.toInt() ?? 0,
      asksLimit: (json['asks_limit'] as num?)?.toInt() ?? 1,
      asksRemaining: (json['asks_remaining'] as num?)?.toInt() ?? 0,
      trialAvailable: json['trial_available'] as bool? ?? false,
      trialExhausted: json['trial_exhausted'] as bool? ?? false,
      maxFileMb: (json['max_file_mb'] as num?)?.toInt() ?? 8,
    );
  }
}

class PlanoPreview {
  const PlanoPreview({
    required this.imageBase64,
    this.mime,
    this.previewNote,
    this.filename,
  });

  final String imageBase64;
  final String? mime;
  final String? previewNote;
  final String? filename;

  factory PlanoPreview.fromJson(Map<String, dynamic> json) {
    return PlanoPreview(
      imageBase64: json['image_base64'] as String? ?? '',
      mime: json['mime'] as String?,
      previewNote: json['preview_note'] as String?,
      filename: json['filename'] as String?,
    );
  }
}

class AppRemoteConfig {
  const AppRemoteConfig({
    required this.defaultPpm,
    required this.defaultConf,
    required this.autoCalibrateDefault,
    required this.raw,
  });

  final double? defaultPpm;
  final double? defaultConf;
  final bool autoCalibrateDefault;
  final Map<String, dynamic> raw;

  factory AppRemoteConfig.fromJson(Map<String, dynamic> json) {
    return AppRemoteConfig(
      defaultPpm: (json['default_ppm'] as num?)?.toDouble(),
      defaultConf: (json['default_conf'] as num?)?.toDouble(),
      autoCalibrateDefault: json['auto_calibrate_default'] as bool? ?? true,
      raw: json,
    );
  }
}

class AskStatus {
  const AskStatus({
    required this.knowledgeReady,
    required this.webSearchEnabled,
    required this.knowledgePages,
  });

  final bool knowledgeReady;
  final bool webSearchEnabled;
  final int knowledgePages;

  factory AskStatus.fromJson(Map<String, dynamic> json) {
    return AskStatus(
      knowledgeReady: json['knowledge_ready'] as bool? ?? false,
      webSearchEnabled: json['web_search_enabled'] as bool? ?? false,
      knowledgePages: (json['knowledge_pages'] as num?)?.toInt() ?? 0,
    );
  }
}
