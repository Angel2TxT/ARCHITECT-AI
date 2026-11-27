import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:movil_architect/core/app_services.dart';
import 'package:movil_architect/core/network/api_exception.dart';
import 'package:movil_architect/core/theme/architect_theme_tokens.dart';
import 'package:movil_architect/core/utils/app_notifications.dart';
import 'package:movil_architect/core/utils/external_url.dart';
import 'package:movil_architect/models/auth_models.dart';
import 'package:movil_architect/models/billing_models.dart';
import 'package:movil_architect/views/billing/widgets/plan_pricing_card.dart';
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
  bool _openingPortal = false;
  bool _canceling = false;
  bool _submittingRefund = false;
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
            (session.isDemo ||
                session.url == null ||
                session.url!.startsWith('/checkout'))) {
          await billing.completeDemoCheckout(session.sessionToken!);
        } else if (session.url != null) {
          await openExternalUrl(_resolveUrl(session.url!));
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

  String _resolveUrl(String rawUrl) {
    final trimmed = rawUrl.trim();
    final parsed = Uri.tryParse(trimmed);
    if (parsed != null && parsed.hasScheme) {
      return trimmed;
    }
    final base = AppServices.instance.apiClient.dio.options.baseUrl;
    return Uri.parse(base).resolve(trimmed).toString();
  }

  Future<void> _openPortal() async {
    if (_openingPortal) return;
    setState(() => _openingPortal = true);
    try {
      final url = await AppServices.instance.billingService.openPortal(
        '${AppServices.instance.apiClient.dio.options.baseUrl}/',
      );
      if (url != null) await openExternalUrl(_resolveUrl(url));
    } on ApiException catch (error) {
      if (!mounted) return;
      AppNotifications.error(context, error.message);
    } finally {
      if (mounted) setState(() => _openingPortal = false);
    }
  }

  Future<void> _confirmAndCancel() async {
    final subscription = _subscription;
    if (subscription == null || _canceling) return;
    final tokens = ArchitectThemeTokens.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: tokens.surfaceSecondary,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ArchitectThemeTokens.radiusLg),
            side: BorderSide(color: tokens.borderSubtle, width: 1),
          ),
          title: Text(
            'Cancelar plan ${subscription.plan.name}',
            style: ArchitectThemeTokens.appleDisplay(
              color: tokens.textPrimary,
              fontSize: 19,
              fontWeight: FontWeight.w500,
            ),
          ),
          content: Text(
            'Se cancelará tu suscripción actual (${subscription.plan.name}). '
            'Perderás los beneficios y límites asociados a este plan conforme '
            'a las reglas de facturación vigentes.',
            style: ArchitectThemeTokens.appleText(
              color: tokens.textSecondary,
              fontSize: 14,
              height: 1.45,
            ),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(
                'Mantener plan',
                style: ArchitectThemeTokens.appleText(
                  color: tokens.textPrimary,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(
                'Cancelar plan',
                style: ArchitectThemeTokens.appleText(
                  color: tokens.statusError,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        );
      },
    );

    if (confirmed == true && mounted) {
      await _cancel();
    }
  }

  Future<void> _cancel() async {
    if (_canceling) return;
    setState(() => _canceling = true);
    try {
      await AppServices.instance.billingService.cancel();
      await _load();
      if (mounted) {
        AppNotifications.success(context, 'Plan cancelado');
      }
    } on ApiException catch (error) {
      if (!mounted) return;
      AppNotifications.error(context, error.message);
    } finally {
      if (mounted) setState(() => _canceling = false);
    }
  }

  Future<void> _openSelectedReceipt() async {
    final receipt = _selectedReceipt;
    if (receipt == null || _openingReceipt) return;
    setState(() => _openingReceipt = true);
    try {
      final bytes = await AppServices.instance.billingService
          .downloadReceiptPdf(receipt.id);
      final file = await AppServices.instance.billingService.writeTempFile(
        bytes,
        'recibo-${receipt.id}.pdf',
      );
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
      final bytes = await AppServices.instance.billingService
          .exportReceiptsZip();
      final file = await AppServices.instance.billingService.writeTempFile(
        bytes,
        'comprobantes.zip',
      );
      await OpenFilex.open(file.path);
    } on ApiException catch (error) {
      if (!mounted) return;
      AppNotifications.error(context, error.message);
    }
  }

  Future<void> _submitRefund() async {
    if (_submittingRefund) return;
    setState(() => _submittingRefund = true);
    try {
      await AppServices.instance.billingService.requestRefund(
        _refundReason.text,
      );
      _refundReason.clear();
      await _load();
      if (!mounted) return;
      AppNotifications.success(context, 'Reembolso solicitado');
    } on ApiException catch (error) {
      if (!mounted) return;
      AppNotifications.error(context, error.message);
    } finally {
      if (mounted) setState(() => _submittingRefund = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = ArchitectThemeTokens.of(context);

    return Scaffold(
      backgroundColor: tokens.drawerBackground,
      appBar: AppBar(
        centerTitle: true,
        backgroundColor: tokens.drawerBackground,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_rounded,
            color: tokens.textPrimary,
            size: 22,
          ),
          tooltip: 'Regresar',
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(
          'Planes y facturación',
          style: ArchitectThemeTokens.appleDisplay(
            color: tokens.textPrimary,
            fontSize: 19,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      body: _loading
          ? Center(
              child: CircularProgressIndicator(
                strokeWidth: 2.2,
                color: tokens.accent,
              ),
            )
          : RefreshIndicator(
              color: tokens.accent,
              backgroundColor: tokens.surfaceSecondary,
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                children: [
                  if (_error != null) ...[
                    _ErrorBanner(message: _error!),
                    const SizedBox(height: 16),
                  ],
                  if (_subscription != null) ...[
                    _CurrentPlanCard(
                      subscription: _subscription!,
                      openingPortal: _openingPortal,
                      canceling: _canceling,
                      onOpenPortal: _openPortal,
                      onCancel: _confirmAndCancel,
                    ),
                    const SizedBox(height: 28),
                  ],
                  Text(
                    'Planes disponibles',
                    style: ArchitectThemeTokens.appleDisplay(
                      color: tokens.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 12),
                  PlanCarousel(
                    plans: _plans,
                    currentPlanSlug: _subscription?.plan.slug,
                    selectingSlug: _selectingSlug,
                    onSelect: _selectPlan,
                  ),
                  const SizedBox(height: 28),
                  Text(
                    'Comprobantes',
                    style: ArchitectThemeTokens.appleDisplay(
                      color: tokens.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_receipts.isEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: tokens.surfaceSecondary,
                        borderRadius: BorderRadius.circular(
                          ArchitectThemeTokens.radiusLg,
                        ),
                        border: Border.all(
                          color: tokens.borderSubtle,
                          width: 1,
                        ),
                      ),
                      child: Text(
                        'Sin comprobantes disponibles.',
                        style: ArchitectThemeTokens.appleText(
                          color: tokens.textSecondary,
                          fontSize: 14,
                        ),
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
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: _downloadReceiptsZip,
                        style: TextButton.styleFrom(
                          foregroundColor: tokens.accent,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 10,
                          ),
                          minimumSize: const Size(44, 44),
                        ),
                        icon: const Icon(Icons.folder_zip_outlined, size: 18),
                        label: Text(
                          'Descargar ZIP',
                          style: ArchitectThemeTokens.appleText(
                            color: tokens.accent,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ],
                  if (_refunds.isNotEmpty || _canRefund) ...[
                    const SizedBox(height: 24),
                    Text(
                      'Reembolsos',
                      style: ArchitectThemeTokens.appleDisplay(
                        color: tokens.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 12),
                    for (int i = 0; i < _refunds.length; i++) ...[
                      if (i > 0) const SizedBox(height: 8),
                      _RefundTile(refund: _refunds[i]),
                    ],
                    if (_canRefund) ...[
                      if (_refunds.isNotEmpty) const SizedBox(height: 12),
                      _RefundComposer(
                        controller: _refundReason,
                        submitting: _submittingRefund,
                        onSubmit: _submitRefund,
                      ),
                    ],
                  ],
                ],
              ),
            ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final tokens = ArchitectThemeTokens.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tokens.statusError.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(ArchitectThemeTokens.radiusMd),
        border: Border.all(
          color: tokens.statusError.withValues(alpha: 0.35),
          width: 1,
        ),
      ),
      child: Text(
        message,
        style: ArchitectThemeTokens.appleText(
          color: tokens.statusError,
          fontSize: 14,
        ),
      ),
    );
  }
}

class _CurrentPlanCard extends StatelessWidget {
  const _CurrentPlanCard({
    required this.subscription,
    required this.openingPortal,
    required this.canceling,
    required this.onOpenPortal,
    required this.onCancel,
  });

  final SubscriptionModel subscription;
  final bool openingPortal;
  final bool canceling;
  final VoidCallback onOpenPortal;
  final VoidCallback onCancel;

  String _formatStatus(String raw) {
    switch (raw.trim().toLowerCase()) {
      case 'active':
        return 'Activa';
      case 'trialing':
        return 'En prueba';
      case 'past_due':
        return 'Pago pendiente';
      case 'canceled':
      case 'cancelled':
        return 'Cancelada';
      case 'inactive':
        return 'Inactiva';
      default:
        return raw.trim();
    }
  }

  Color _statusColor(ArchitectThemeTokens tokens, String raw) {
    switch (raw.trim().toLowerCase()) {
      case 'active':
      case 'trialing':
        return tokens.statusPositive;
      case 'past_due':
        return tokens.statusWarning;
      case 'canceled':
      case 'cancelled':
      case 'inactive':
        return tokens.statusError;
      default:
        return tokens.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = ArchitectThemeTokens.of(context);
    final rawStatus = subscription.status.trim();
    final hasStatus = rawStatus.isNotEmpty;
    final statusLabel = _formatStatus(rawStatus);
    final statusColor = _statusColor(tokens, rawStatus);
    final periodKey = subscription.usage.periodKey.trim();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: tokens.surfaceSecondary,
        borderRadius: BorderRadius.circular(ArchitectThemeTokens.radiusLg),
        border: Border.all(color: tokens.borderSubtle, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Tu plan actual',
                style: ArchitectThemeTokens.appleText(
                  color: tokens.accent,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              if (hasStatus)
                Text(
                  statusLabel,
                  style: ArchitectThemeTokens.appleText(
                    color: statusColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            subscription.plan.name,
            style: ArchitectThemeTokens.appleDisplay(
              color: tokens.textPrimary,
              fontSize: 24,
              fontWeight: FontWeight.w500,
              height: 1.18,
            ),
          ),
          if (periodKey.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Ciclo actual · $periodKey',
              style: ArchitectThemeTokens.appleText(
                color: tokens.textSecondary,
                fontSize: 13.5,
              ),
            ),
          ],
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: SizedBox(
                  height: 46,
                  child: FilledButton(
                    onPressed: openingPortal ? null : onOpenPortal,
                    style: FilledButton.styleFrom(
                      backgroundColor: tokens.primaryActionBg,
                      foregroundColor: tokens.primaryActionFg,
                      disabledBackgroundColor:
                          tokens.primaryActionBg.withValues(alpha: 0.55),
                      disabledForegroundColor: tokens.primaryActionFg,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          ArchitectThemeTokens.radiusMd,
                        ),
                      ),
                    ),
                    child: openingPortal
                        ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: tokens.primaryActionFg,
                            ),
                          )
                        : FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.open_in_new_rounded,
                                  size: 16,
                                  color: tokens.primaryActionFg,
                                ),
                                const SizedBox(width: 7),
                                Text(
                                  'Gestionar facturación',
                                  style: ArchitectThemeTokens.appleText(
                                    color: tokens.primaryActionFg,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: SizedBox(
                  height: 46,
                  child: FilledButton(
                    onPressed: canceling ? null : onCancel,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFC94A4A),
                      foregroundColor: Colors.white,
                      disabledBackgroundColor:
                          const Color(0xFFC94A4A).withValues(alpha: 0.55),
                      disabledForegroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          ArchitectThemeTokens.radiusMd,
                        ),
                      ),
                    ),
                    child: canceling
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              'Cancelar plan',
                              style: ArchitectThemeTokens.appleText(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                  ),
                ),
              ),
            ],
          ),
        ],
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
    final tokens = ArchitectThemeTokens.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tokens.surfaceSecondary,
        borderRadius: BorderRadius.circular(ArchitectThemeTokens.radiusLg),
        border: Border.all(color: tokens.borderSubtle, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Seleccionar comprobante',
            style: ArchitectThemeTokens.appleText(
              color: tokens.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: tokens.drawerBackground,
                    borderRadius: BorderRadius.circular(
                      ArchitectThemeTokens.radiusMd,
                    ),
                    border: Border.all(color: tokens.borderSubtle, width: 1),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: selectedId,
                      isExpanded: true,
                      dropdownColor: tokens.surfaceSecondary,
                      borderRadius: BorderRadius.circular(
                        ArchitectThemeTokens.radiusMd,
                      ),
                      icon: Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: tokens.textSecondary,
                      ),
                      items: [
                        for (final receipt in receipts)
                          DropdownMenuItem<String>(
                            value: receipt.id,
                            child: Text(
                              labelBuilder(receipt),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: ArchitectThemeTokens.appleText(
                                color: tokens.textPrimary,
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
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
              const SizedBox(width: 10),
              Semantics(
                button: true,
                label: 'Descargar comprobante',
                child: Material(
                  color: tokens.primaryActionBg,
                  borderRadius: BorderRadius.circular(
                    ArchitectThemeTokens.radiusMd,
                  ),
                  child: InkWell(
                    onTap: isOpening ? null : onOpen,
                    borderRadius: BorderRadius.circular(
                      ArchitectThemeTokens.radiusMd,
                    ),
                    child: SizedBox(
                      width: 46,
                      height: 46,
                      child: Center(
                        child: isOpening
                            ? SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: tokens.primaryActionFg,
                                ),
                              )
                            : Icon(
                                Icons.download_rounded,
                                size: 20,
                                color: tokens.primaryActionFg,
                              ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RefundTile extends StatelessWidget {
  const _RefundTile({required this.refund});

  final BillingRefund refund;

  @override
  Widget build(BuildContext context) {
    final tokens = ArchitectThemeTokens.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tokens.surfaceSecondary,
        borderRadius: BorderRadius.circular(ArchitectThemeTokens.radiusMd),
        border: Border.all(color: tokens.borderSubtle, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            refund.status,
            style: ArchitectThemeTokens.appleText(
              color: tokens.accent,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (refund.reason.trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              refund.reason,
              style: ArchitectThemeTokens.appleText(
                color: tokens.textPrimary,
                fontSize: 14,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _RefundComposer extends StatelessWidget {
  const _RefundComposer({
    required this.controller,
    required this.submitting,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final bool submitting;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final tokens = ArchitectThemeTokens.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tokens.surfaceSecondary,
        borderRadius: BorderRadius.circular(ArchitectThemeTokens.radiusLg),
        border: Border.all(color: tokens.borderSubtle, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: controller,
            enabled: !submitting,
            minLines: 2,
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
            style: ArchitectThemeTokens.appleText(
              color: tokens.textPrimary,
              fontSize: 14,
            ),
            decoration: InputDecoration(
              hintText: 'Motivo del reembolso',
              hintStyle: ArchitectThemeTokens.appleText(
                color: tokens.textSecondary,
                fontSize: 14,
              ),
              filled: true,
              fillColor: tokens.drawerBackground,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(
                  ArchitectThemeTokens.radiusMd,
                ),
                borderSide: BorderSide(color: tokens.borderSubtle, width: 1),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(
                  ArchitectThemeTokens.radiusMd,
                ),
                borderSide: BorderSide(color: tokens.borderSubtle, width: 1),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(
                  ArchitectThemeTokens.radiusMd,
                ),
                borderSide: BorderSide(color: tokens.accent, width: 1),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton(
              onPressed: submitting ? null : onSubmit,
              style: FilledButton.styleFrom(
                backgroundColor: tokens.primaryActionBg,
                foregroundColor: tokens.primaryActionFg,
                disabledBackgroundColor:
                    tokens.primaryActionBg.withValues(alpha: 0.55),
                disabledForegroundColor: tokens.primaryActionFg,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(
                    ArchitectThemeTokens.radiusMd,
                  ),
                ),
              ),
              child: submitting
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: tokens.primaryActionFg,
                      ),
                    )
                  : Text(
                      'Solicitar reembolso',
                      style: ArchitectThemeTokens.appleText(
                        color: tokens.primaryActionFg,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
