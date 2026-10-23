import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:movil_architect/core/network/api_client.dart';
import 'package:movil_architect/core/network/api_exception.dart';
import 'package:movil_architect/core/utils/json_utils.dart';
import 'package:movil_architect/models/auth_models.dart';
import 'package:movil_architect/models/billing_models.dart';

class BillingService {
  BillingService({required ApiClient apiClient}) : _apiClient = apiClient;

  final ApiClient _apiClient;

  Future<BillingConfig> getConfig() async {
    try {
      final response =
          await _apiClient.dio.get<Map<String, dynamic>>('/api/billing/config');
      return BillingConfig.fromJson(response.data ?? {});
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<List<BillingPlan>> listPlans() async {
    try {
      final response = await _apiClient.dio.get<dynamic>('/api/billing/plans');
      final data = response.data;
      final list = data is List ? data : asJsonMap(data)['plans'];
      if (list is! List) return [];
      return list
          .whereType<Map>()
          .map((e) => BillingPlan.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<SubscriptionModel?> getSubscription() async {
    try {
      final response = await _apiClient.dio
          .get<Map<String, dynamic>>('/api/billing/subscription');
      final map = response.data ?? {};
      final nested = map['subscription'];
      if (nested is Map) {
        return SubscriptionModel.fromJson(Map<String, dynamic>.from(nested));
      }
      if (map['plan'] is Map) {
        return SubscriptionModel.fromJson(map);
      }
      return null;
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<void> changePlan(String planSlug) async {
    try {
      await _apiClient.dio.post<Map<String, dynamic>>(
        '/api/billing/change-plan',
        data: {'plan_slug': planSlug},
      );
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<CheckoutSession> checkout({
    required String planSlug,
    required String returnUrl,
  }) async {
    try {
      final response = await _apiClient.dio.post<Map<String, dynamic>>(
        '/api/billing/checkout',
        data: {'plan_slug': planSlug, 'return_url': returnUrl},
      );
      return CheckoutSession.fromJson(response.data ?? {});
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<Map<String, dynamic>> demoSession(String token) async {
    try {
      final response = await _apiClient.dio.get<Map<String, dynamic>>(
        '/api/billing/checkout/session',
        queryParameters: {'token': token},
      );
      return response.data ?? {};
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<void> completeDemoCheckout(String sessionToken) async {
    try {
      await _apiClient.dio.post<Map<String, dynamic>>(
        '/api/billing/checkout/complete',
        data: {'session_token': sessionToken},
      );
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<void> completeStripeCheckout(String sessionId) async {
    try {
      await _apiClient.dio.get<Map<String, dynamic>>(
        '/api/billing/checkout/stripe/complete',
        queryParameters: {'session_id': sessionId},
      );
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<String?> openPortal(String returnUrl) async {
    try {
      final response = await _apiClient.dio.post<Map<String, dynamic>>(
        '/api/billing/portal',
        data: {'return_url': returnUrl},
      );
      return firstNonEmptyString(response.data ?? {}, ['url', 'portal_url']);
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<void> cancel() async {
    try {
      await _apiClient.dio.post<Map<String, dynamic>>('/api/billing/cancel');
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<List<UsageHistoryPoint>> usageHistory({int months = 6}) async {
    try {
      final response = await _apiClient.dio.get<Map<String, dynamic>>(
        '/api/billing/usage-history',
        queryParameters: {'months': months},
      );
      final list = response.data?['history'];
      if (list is! List) return [];
      return list
          .whereType<Map>()
          .map((e) => UsageHistoryPoint.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<List<BillingReceipt>> listReceipts() async {
    try {
      final response = await _apiClient.dio
          .get<Map<String, dynamic>>('/api/billing/receipts');
      final list = response.data?['receipts'];
      if (list is! List) return [];
      return list
          .whereType<Map>()
          .map((e) => BillingReceipt.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<Uint8List> downloadReceiptPdf(String receiptId) async {
    try {
      final response = await _apiClient.dio.get<List<int>>(
        '/api/billing/receipts/$receiptId/pdf',
        options: Options(responseType: ResponseType.bytes),
      );
      return Uint8List.fromList(response.data ?? []);
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<void> emailReceipt(String receiptId) async {
    try {
      await _apiClient.dio.post<Map<String, dynamic>>(
        '/api/billing/receipts/$receiptId/email',
      );
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<Uint8List> exportReceiptsZip() async {
    try {
      final response = await _apiClient.dio.get<List<int>>(
        '/api/billing/receipts/export/zip',
        options: Options(responseType: ResponseType.bytes),
      );
      return Uint8List.fromList(response.data ?? []);
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<bool> refundEligibility() async {
    try {
      final response = await _apiClient.dio
          .get<Map<String, dynamic>>('/api/billing/refund-eligibility');
      final data = response.data ?? {};
      return data['eligible'] == true || data['ok'] == true;
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<List<BillingRefund>> listRefunds() async {
    try {
      final response =
          await _apiClient.dio.get<Map<String, dynamic>>('/api/billing/refunds');
      final list = response.data?['refunds'];
      if (list is! List) return [];
      return list
          .whereType<Map>()
          .map((e) => BillingRefund.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<void> requestRefund(String reason) async {
    try {
      await _apiClient.dio.post<Map<String, dynamic>>(
        '/api/billing/refunds',
        data: {'reason': reason.trim()},
      );
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<File> writeTempFile(Uint8List bytes, String name) async {
    final dir = await Directory.systemTemp.createTemp('architect');
    final file = File('${dir.path}/$name');
    await file.writeAsBytes(bytes);
    return file;
  }
}
