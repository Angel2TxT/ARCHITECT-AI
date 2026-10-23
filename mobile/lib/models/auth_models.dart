class UserModel {
  const UserModel({
    required this.id,
    required this.email,
    required this.fullName,
    required this.role,
    this.avatarUrl,
    this.hasPassword = true,
    this.oauthProvider,
  });

  final int id;
  final String email;
  final String fullName;
  final String role;
  final String? avatarUrl;
  final bool hasPassword;
  final String? oauthProvider;

  bool get isGoogleAccount =>
      hasPassword == false ||
      (oauthProvider != null && oauthProvider!.toLowerCase().contains('google'));

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: (json['id'] as num?)?.toInt() ?? 0,
      email: json['email'] as String? ?? '',
      fullName: json['full_name'] as String? ?? '',
      role: json['role'] as String? ?? 'user',
      avatarUrl: json['avatar_url'] as String?,
      hasPassword: json['has_password'] as bool? ?? true,
      oauthProvider: json['oauth_provider'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        'full_name': fullName,
        'role': role,
        'avatar_url': avatarUrl,
        'has_password': hasPassword,
        'oauth_provider': oauthProvider,
      };
}

class PlanModel {
  const PlanModel({
    required this.slug,
    required this.name,
    required this.analysesLimitMonthly,
    required this.maxFileMb,
  });

  final String slug;
  final String name;
  final int? analysesLimitMonthly;
  final int maxFileMb;

  factory PlanModel.fromJson(Map<String, dynamic> json) {
    return PlanModel(
      slug: json['slug'] as String? ?? '',
      name: json['name'] as String? ?? '',
      analysesLimitMonthly: json['analyses_limit_monthly'] as int?,
      maxFileMb: json['max_file_mb'] as int? ?? 0,
    );
  }
}

class UsageModel {
  const UsageModel({
    required this.periodKey,
    required this.analysesUsed,
    required this.analysesRemaining,
    required this.limitReached,
  });

  final String periodKey;
  final int analysesUsed;
  final int? analysesRemaining;
  final bool limitReached;

  factory UsageModel.fromJson(Map<String, dynamic> json) {
    return UsageModel(
      periodKey: json['period_key'] as String? ?? '',
      analysesUsed: json['analyses_used'] as int? ?? 0,
      analysesRemaining: json['analyses_remaining'] as int?,
      limitReached: json['limit_reached'] as bool? ?? false,
    );
  }
}

class SubscriptionModel {
  const SubscriptionModel({
    required this.plan,
    required this.isUnlimited,
    required this.status,
    required this.usage,
  });

  final PlanModel plan;
  final bool isUnlimited;
  final String status;
  final UsageModel usage;

  bool get isPro => isUnlimited || plan.slug.toLowerCase().contains('pro');

  factory SubscriptionModel.fromJson(Map<String, dynamic> json) {
    return SubscriptionModel(
      plan: PlanModel.fromJson(json['plan'] as Map<String, dynamic>? ?? {}),
      isUnlimited: json['is_unlimited'] as bool? ?? false,
      status: json['status'] as String? ?? 'inactive',
      usage: UsageModel.fromJson(json['usage'] as Map<String, dynamic>? ?? {}),
    );
  }
}

class AuthResponse {
  const AuthResponse({
    required this.accessToken,
    required this.tokenType,
    required this.user,
    required this.subscription,
  });

  final String accessToken;
  final String tokenType;
  final UserModel user;
  final SubscriptionModel? subscription;

  factory AuthResponse.fromJson(Map<String, dynamic> json) {
    return AuthResponse(
      accessToken: json['access_token'] as String,
      tokenType: json['token_type'] as String? ?? 'bearer',
      user: UserModel.fromJson(json['user'] as Map<String, dynamic>),
      subscription: json['subscription'] is Map<String, dynamic>
          ? SubscriptionModel.fromJson(
              json['subscription'] as Map<String, dynamic>,
            )
          : null,
    );
  }
}

class MeResponse {
  const MeResponse({
    required this.user,
    required this.subscription,
  });

  final UserModel user;
  final SubscriptionModel? subscription;

  factory MeResponse.fromJson(Map<String, dynamic> json) {
    return MeResponse(
      user: UserModel.fromJson(json['user'] as Map<String, dynamic>),
      subscription: json['subscription'] is Map<String, dynamic>
          ? SubscriptionModel.fromJson(
              json['subscription'] as Map<String, dynamic>,
            )
          : null,
    );
  }
}

class HealthResponse {
  const HealthResponse({
    required this.ok,
    required this.service,
    required this.message,
    required this.version,
  });

  final bool ok;
  final String service;
  final String message;
  final String version;

  factory HealthResponse.fromJson(Map<String, dynamic> json) {
    final ok = json['ok'] as bool? ?? false;
    return HealthResponse(
      ok: ok,
      service: json['service'] as String? ?? 'ARCHITECT',
      message: json['message'] as String? ??
          (ok ? 'Servicio disponible' : 'Servicio no disponible'),
      version: json['version'] as String? ??
          (json['model_ready'] == true ? 'modelo listo' : ''),
    );
  }
}
