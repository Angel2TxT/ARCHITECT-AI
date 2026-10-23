import 'package:movil_architect/core/utils/json_utils.dart';

class BillingPlan {
  const BillingPlan({
    required this.slug,
    required this.name,
    required this.description,
    required this.priceMonthlyCents,
    required this.analysesLimitMonthly,
    required this.allowRealModel,
    required this.maxFileMb,
    required this.storageGb,
    required this.features,
    required this.requiresCheckout,
  });

  final String slug;
  final String name;
  final String description;
  final int priceMonthlyCents;
  final int? analysesLimitMonthly;
  final bool allowRealModel;
  final int maxFileMb;
  final int? storageGb;
  final List<String> features;
  final bool requiresCheckout;

  bool get isFree => slug == 'free' || priceMonthlyCents <= 0;

  String get priceAmountLabel {
    if (isFree) return '\$0';
    final amount = priceMonthlyCents / 100;
    return '\$${amount.toStringAsFixed(amount.truncateToDouble() == amount ? 0 : 2)}';
  }

  String get priceLabel {
    if (isFree) return 'Gratis';
    return '$priceAmountLabel / mes';
  }

  List<String> get displayFeatures {
    if (features.isNotEmpty) return features;
    return [
      if (analysesLimitMonthly == null)
        'Análisis ilimitados'
      else
        '$analysesLimitMonthly análisis / mes',
      if (allowRealModel) 'Modelo de IA avanzado' else 'Modelo de demostración',
      if (maxFileMb > 0) 'Archivos de hasta $maxFileMb MB',
      if (storageGb != null) '$storageGb GB de almacenamiento',
      if (isFree) 'Soporte comunitario' else 'Soporte prioritario',
    ];
  }

  factory BillingPlan.fromJson(Map<String, dynamic> json) {
    return BillingPlan(
      slug: json['slug'] as String? ?? '',
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      priceMonthlyCents: (json['price_monthly_cents'] as num?)?.toInt() ?? 0,
      analysesLimitMonthly: (json['analyses_limit_monthly'] as num?)?.toInt(),
      allowRealModel: json['allow_real_model'] as bool? ?? false,
      maxFileMb: (json['max_file_mb'] as num?)?.toInt() ?? 0,
      storageGb: (json['storage_gb'] as num?)?.toInt(),
      features: _parseFeatures(json['features']),
      requiresCheckout: json['requires_checkout'] as bool? ?? false,
    );
  }

  static List<String> _parseFeatures(dynamic features) {
    if (features is List) {
      return features.map((e) => e.toString()).toList();
    }
    if (features is Map) {
      final benefits = features['benefits'];
      if (benefits is List) {
        return benefits.map((e) => e.toString()).toList();
      }
    }
    return const [];
  }
}

class BillingConfig {
  const BillingConfig({
    required this.raw,
    required this.isDemo,
  });

  final Map<String, dynamic> raw;
  final bool isDemo;

  factory BillingConfig.fromJson(Map<String, dynamic> json) {
    final mode = (json['mode'] ?? json['provider'] ?? '').toString().toLowerCase();
    return BillingConfig(
      raw: json,
      isDemo: json['demo'] == true ||
          json['is_demo'] == true ||
          mode.contains('demo'),
    );
  }
}

class CheckoutSession {
  const CheckoutSession({
    this.url,
    this.sessionToken,
    this.sessionId,
    this.isDemo = false,
  });

  final String? url;
  final String? sessionToken;
  final String? sessionId;
  final bool isDemo;

  factory CheckoutSession.fromJson(Map<String, dynamic> json) {
    return CheckoutSession(
      url: firstNonEmptyString(json, ['url', 'checkout_url', 'portal_url']),
      sessionToken: firstNonEmptyString(json, ['session_token', 'token']),
      sessionId: firstNonEmptyString(json, ['session_id']),
      isDemo: json['demo'] == true || json['is_demo'] == true,
    );
  }
}

class BillingReceipt {
  const BillingReceipt({
    required this.id,
    required this.title,
    required this.createdAt,
    this.amountCents,
  });

  final String id;
  final String title;
  final DateTime? createdAt;
  final int? amountCents;

  factory BillingReceipt.fromJson(Map<String, dynamic> json) {
    return BillingReceipt(
      id: (json['id'] ?? json['receipt_id'] ?? '').toString(),
      title: json['title'] as String? ??
          json['plan_name'] as String? ??
          json['description'] as String? ??
          'Comprobante',
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString())
          : null,
      amountCents: (json['amount_cents'] as num?)?.toInt() ??
          (json['total_cents'] as num?)?.toInt(),
    );
  }
}

class BillingRefund {
  const BillingRefund({
    required this.id,
    required this.status,
    required this.reason,
    this.createdAt,
  });

  final String id;
  final String status;
  final String reason;
  final DateTime? createdAt;

  factory BillingRefund.fromJson(Map<String, dynamic> json) {
    return BillingRefund(
      id: (json['id'] ?? '').toString(),
      status: json['status'] as String? ?? 'pending',
      reason: json['reason'] as String? ?? '',
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString())
          : null,
    );
  }
}

class UsageHistoryPoint {
  const UsageHistoryPoint({
    required this.label,
    required this.analysesUsed,
  });

  final String label;
  final int analysesUsed;

  factory UsageHistoryPoint.fromJson(Map<String, dynamic> json) {
    return UsageHistoryPoint(
      label: (json['period'] ?? json['month'] ?? json['label'] ?? '').toString(),
      analysesUsed: (json['analyses_used'] as num?)?.toInt() ??
          (json['used'] as num?)?.toInt() ??
          0,
    );
  }
}
