import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:movil_architect/core/app_services.dart';
import 'package:movil_architect/core/network/api_exception.dart';
import 'package:movil_architect/core/utils/app_notifications.dart';
import 'package:movil_architect/core/utils/external_url.dart';
import 'package:movil_architect/models/auth_models.dart';
import 'package:movil_architect/models/billing_models.dart';
import 'package:movil_architect/views/billing/widgets/plan_pricing_card.dart';
import 'package:movil_architect/views/login/widgets/login_widgets.dart';
import 'package:open_filex/open_filex.dart';

class BillingView extends StatefulWidget {
  const BillingView({super.key});

  @override
  State<BillingView> createState() => _BillingViewState();
}

class _BillingViewState extends State<BillingView> {
  bool _loading = true;
  String? _error;
  List<BillingPlan> _plans = [];
  SubscriptionModel? _subscription;
  List<BillingReceipt> _receipts = [];
  List<BillingRefund> _refunds = [];
  bool _canRefund = false;
  String? _selectingSlug;
  String? _selectedReceiptId;
  bool _openingReceipt = false;
  final _refundReason = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _refundReason.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final billing = AppServices.instance.billingService;
      final api = AppServices.instance.mobileApiService;
      final auth = AppServices.instance.authService;
      final results = await Future.wait([
        billing.listPlans(),
        billing.getSubscription(),
        billing.listReceipts(),
        billing.listRefunds(),
        billing.refundEligibility(),
        api.me(),
      ]);
      _plans = results[0] as List<BillingPlan>;
      _subscription = results[1] as SubscriptionModel?;
      _receipts = List<BillingReceipt>.from(results[2] as List<BillingReceipt>)
        ..sort((a, b) {
          final aDate = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          final bDate = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          return bDate.compareTo(aDate);
        });
      _refunds = results[3] as List<BillingRefund>;
      _canRefund = results[4] as bool;
      final me = results[5] as MeResponse;
      auth.updateSession(user: me.user, subscription: me.subscription);
      _subscription ??= me.subscription;
      if (_receipts.isEmpty) {
        _selectedReceiptId = null;
      } else if (_selectedReceiptId == null ||
          _receipts.every((r) => r.id != _selectedReceiptId)) {
        _selectedReceiptId = _receipts.first.id;
      }
    } on ApiException catch (error) {
      _error = error.message;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _selectPlan(BillingPlan plan) async {
    if (_selectingSlug != null) return;
    setState(() => _selectingSlug = plan.slug);
    final billing = AppServices.instance.billingService;
    try {
      if (!plan.requiresCheckout || plan.isFree) {
        await billing.changePlan(plan.slug);
      } else {
        final session = await billing.checkout(
          planSlug: plan.slug,
          returnUrl: '${AppServices.instance.apiClient.dio.options.baseUrl}/',
        );
        if (session.sessionToken != null &&
            (session.isDemo || session.url == null)) {
          await billing.completeDemoCheckout(session.sessionToken!);
        } else if (session.url != null) {
          await openExternalUrl(session.url!);
          if (session.sessionId != null) {
            await billing.completeStripeCheckout(session.sessionId!);
          }
        }
      }
      await _load();
      if (mounted) {
        AppNotifications.success(context, 'Plan actualizado');
      }
    } on ApiException catch (error) {
      if (!mounted) return;
      AppNotifications.error(context, error.message);
    } finally {
      if (mounted) setState(() => _selectingSlug = null);
    }
  }

  Future<void> _openPortal() async {
    try {
      final url = await AppServices.instance.billingService.openPortal(
        '${AppServices.instance.apiClient.dio.options.baseUrl}/',
      );
      if (url != null) await openExternalUrl(url);
    } on ApiException catch (error) {
      if (!mounted) return;
      AppNotifications.error(context, error.message);
    }
  }

  Future<void> _cancel() async {
    try {
      await AppServices.instance.billingService.cancel();
      await _load();
      if (mounted) {
        AppNotifications.success(context, 'Plan cancelado');
      }
    } on ApiException catch (error) {
      if (!mounted) return;
      AppNotifications.error(context, error.message);
    }
  }

  Future<void> _openSelectedReceipt() async {
    final receipt = _selectedReceipt;
    if (receipt == null || _openingReceipt) return;
    setState(() => _openingReceipt = true);
    try {
      final bytes = await AppServices.instance.billingService
          .downloadReceiptPdf(receipt.id);
      final file = await AppServices.instance.billingService
          .writeTempFile(bytes, 'recibo-${receipt.id}.pdf');
      await OpenFilex.open(file.path);
    } on ApiException catch (error) {
      if (!mounted) return;
      AppNotifications.error(context, error.message);
    } catch (_) {
      if (!mounted) return;
      AppNotifications.error(context, 'No se pudo abrir el comprobante');
    } finally {
      if (mounted) setState(() => _openingReceipt = false);
    }
  }

  BillingReceipt? get _selectedReceipt {
    if (_receipts.isEmpty || _selectedReceiptId == null) return null;
    for (final receipt in _receipts) {
      if (receipt.id == _selectedReceiptId) return receipt;
    }
    return _receipts.first;
  }

  String _receiptLabel(BillingReceipt receipt) {
    final date = receipt.createdAt == null
        ? ''
        : DateFormat('dd/MM/yyyy').format(receipt.createdAt!);
    if (date.isEmpty) return receipt.title;
    return '${receipt.title} · $date';
  }

  Future<void> _downloadReceiptsZip() async {
    try {
      final bytes =
          await AppServices.instance.billingService.exportReceiptsZip();
      final file = await AppServices.instance.billingService
          .writeTempFile(bytes, 'comprobantes.zip');
      await OpenFilex.open(file.path);
    } on ApiException catch (error) {
      if (!mounted) return;
      AppNotifications.error(context, error.message);
    }
  }

  Future<void> _submitRefund() async {
    try {
      await AppServices.instance.billingService
          .requestRefund(_refundReason.text);
      _refundReason.clear();
      await _load();
      if (!mounted) return;
      AppNotifications.success(
        context,
        'Reembolso solicitado',
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      AppNotifications.error(context, error.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Planes y facturación'),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  if (_error != null)
                    Text(_error!, style: const TextStyle(color: Colors.redAccent)),
                  if (_subscription != null) ...[
                    Text(
                      'Plan actual: ${_subscription!.plan.name}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      children: [
                        OutlinedButton(
                          onPressed: _openPortal,
                          child: const Text('Portal Stripe'),
                        ),
                        FilledButton(
                          onPressed: _cancel,
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFFD64545),
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('Cancelar plan'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                  ],
                  const Text(
                    'Planes',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
                  ),
                  const SizedBox(height: 12),
                  PlanCarousel(
                    plans: _plans,
                    currentPlanSlug: _subscription?.plan.slug,
                    selectingSlug: _selectingSlug,
                    onSelect: _selectPlan,
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Comprobantes',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
                  ),
                  const SizedBox(height: 12),
                  if (_receipts.isEmpty)
                    Text(
                      'Sin comprobantes',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    )
                  else ...[
                    _ReceiptSelector(
                      receipts: _receipts,
                      selectedId: _selectedReceiptId ?? _receipts.first.id,
                      labelBuilder: _receiptLabel,
                      isOpening: _openingReceipt,
                      onChanged: (id) {
                        setState(() => _selectedReceiptId = id);
                      },
                      onOpen: _openSelectedReceipt,
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: _downloadReceiptsZip,
                        icon: const Icon(Icons.folder_zip_outlined, size: 18),
                        label: const Text('Descargar ZIP'),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  const Text(
                    'Reembolsos',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
                  ),
                  ..._refunds.map(
                    (item) => ListTile(
                      title: Text(item.status),
                      subtitle: Text(item.reason),
                    ),
                  ),
                  if (_canRefund) ...[
                    const SizedBox(height: 8),
                    LoginPillField(
                      controller: _refundReason,
                      hint: 'MOTIVO DEL REEMBOLSO',
                    ),
                    const SizedBox(height: 10),
                    LoginPrimaryButton(
                      label: 'Solicitar reembolso',
                      onPressed: _submitRefund,
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}

class _ReceiptSelector extends StatelessWidget {
  const _ReceiptSelector({
    required this.receipts,
    required this.selectedId,
    required this.labelBuilder,
    required this.onChanged,
    required this.onOpen,
    this.isOpening = false,
  });

  final List<BillingReceipt> receipts;
  final String selectedId;
  final String Function(BillingReceipt receipt) labelBuilder;
  final ValueChanged<String> onChanged;
  final VoidCallback onOpen;
  final bool isOpening;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = colorScheme.brightness == Brightness.dark;
    final cardBg =
        isDark ? colorScheme.surfaceContainerHighest : Colors.white;
    final fieldBg =
        isDark ? colorScheme.surfaceContainerHigh : const Color(0xFFF4F4F6);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.06)
              : const Color(0xFFE8E8EC),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Seleccionar comprobante',
            style: TextStyle(
              color: colorScheme.onSurfaceVariant,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: fieldBg,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: selectedId,
                      isExpanded: true,
                      borderRadius: BorderRadius.circular(14),
                      icon: Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      items: [
                        for (final receipt in receipts)
                          DropdownMenuItem<String>(
                            value: receipt.id,
                            child: Text(
                              labelBuilder(receipt),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: colorScheme.onSurface,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                      ],
                      onChanged: (value) {
                        if (value != null) onChanged(value);
                      },
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: isOpening ? null : onOpen,
                tooltip: 'Ver / descargar',
                style: IconButton.styleFrom(
                  backgroundColor: colorScheme.onSurface,
                  foregroundColor: isDark ? Colors.black : Colors.white,
                  disabledBackgroundColor:
                      colorScheme.onSurface.withValues(alpha: 0.35),
                ),
                icon: isOpening
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: isDark ? Colors.black : Colors.white,
                        ),
                      )
                    : const Icon(Icons.download_rounded),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
