import 'package:flutter/material.dart';
import 'package:movil_architect/core/app_services.dart';
import 'package:movil_architect/core/network/api_exception.dart';
import 'package:movil_architect/core/theme/app_colors.dart';
import 'package:movil_architect/core/utils/app_notifications.dart';
import 'package:movil_architect/core/utils/image_utils.dart';
import 'package:movil_architect/models/analysis_models.dart';
import 'package:movil_architect/views/dashboard/dashboard_view.dart';
import 'package:movil_architect/views/login/widgets/login_widgets.dart';
import 'package:movil_architect/views/shared/app_states.dart';

class AnalysisResultsView extends StatefulWidget {
  const AnalysisResultsView({super.key, required this.result});

  final AnalysisResult result;

  @override
  State<AnalysisResultsView> createState() => _AnalysisResultsViewState();
}

class _AnalysisResultsViewState extends State<AnalysisResultsView> {
  late AnalysisResult _result;
  final _correction = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _result = widget.result;
  }

  @override
  void dispose() {
    _correction.dispose();
    super.dispose();
  }

  Future<void> _applyCorrection({
    required int index,
    required String action,
    String? newClass,
  }) async {
    final analysisId = _result.analysisId;
    if (analysisId == null) return;
    setState(() => _busy = true);
    try {
      _result = await AppServices.instance.mobileApiService.correctDetection(
        analysisId: analysisId,
        detectionIndex: index,
        action: action,
        newClass: newClass,
        chatId: _result.chatId,
      );
      if (mounted) {
        AppNotifications.success(context, 'Corrección aplicada');
      }
    } on ApiException catch (error) {
      if (!mounted) return;
      AppNotifications.error(context, error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _correctFromText() async {
    final analysisId = _result.analysisId;
    final text = _correction.text.trim();
    if (analysisId == null || text.length < 3) return;
    setState(() => _busy = true);
    try {
      _result = await AppServices.instance.mobileApiService.correctFromMessage(
        analysisId: analysisId,
        message: text,
        chatId: _result.chatId,
      );
      _correction.clear();
      if (mounted) {
        AppNotifications.success(context, 'Corrección aplicada');
      }
    } on ApiException catch (error) {
      if (!mounted) return;
      AppNotifications.error(context, error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _relabel(DetectionModel detection) async {
    final selected = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Cambiar clase'),
        children: [
          for (final option in DetectionModel.classOptions)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, option),
              child: Text(option),
            ),
        ],
      ),
    );
    if (selected == null) return;
    await _applyCorrection(
      index: detection.index,
      action: 'relabel',
      newClass: selected,
    );
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    final tone = result.verdict.tone;
    final color = verdictColor(tone);

    return Scaffold(
      backgroundColor: AppColors.dashboardSurface,
      appBar: AppBar(
        backgroundColor: AppColors.dashboardSurface,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.ink),
        title: const Text(
          'Resultado',
          style: TextStyle(color: AppColors.ink, fontWeight: FontWeight.w700),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: color.withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(verdictIcon(tone), color: color),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        result.verdict.headline,
                        style: TextStyle(
                          color: color,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                if (result.verdict.detail.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    result.verdict.detail,
                    style: const TextStyle(
                      color: AppColors.muted,
                      height: 1.4,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          AnalysisCountsRow(counts: result.counts),
          const SizedBox(height: 16),
          if (result.imageBase64 != null && result.imageBase64!.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.memory(
                decodeBase64Image(result.imageBase64!),
                fit: BoxFit.contain,
              ),
            ),
          if (result.issues.isNotEmpty) ...[
            const SizedBox(height: 20),
            const Text(
              'Incidencias',
              style: TextStyle(
                color: AppColors.ink,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            ...result.issues.map(
              (issue) => Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: Icon(
                    verdictIcon(issue.severity),
                    color: verdictColor(issue.severity),
                  ),
                  title: Text(issue.title),
                  subtitle: issue.detail.isNotEmpty ? Text(issue.detail) : null,
                ),
              ),
            ),
          ],
          if (result.detections.isNotEmpty) ...[
            const SizedBox(height: 20),
            const Text(
              'Detecciones',
              style: TextStyle(
                color: AppColors.ink,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            ...result.detections.map(
              (detection) => Card(
                child: ListTile(
                  title: Text(
                    detection.label.isEmpty
                        ? detection.className
                        : detection.label,
                  ),
                  subtitle: Text('Clase: ${detection.className}'),
                  trailing: Wrap(
                    children: [
                      IconButton(
                        tooltip: 'Rechazar',
                        onPressed: _busy
                            ? null
                            : () => _applyCorrection(
                                  index: detection.index,
                                  action: 'reject',
                                ),
                        icon: const Icon(Icons.close),
                      ),
                      IconButton(
                        tooltip: 'Cambiar clase',
                        onPressed: _busy ? null : () => _relabel(detection),
                        icon: const Icon(Icons.edit_outlined),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
          if (result.analysisId != null) ...[
            const SizedBox(height: 16),
            const Text(
              'Corregir en lenguaje natural',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            LoginPillField(
              controller: _correction,
              hint: 'ESA VENTANA NO ES VENTANA…',
            ),
            const SizedBox(height: 10),
            LoginPrimaryButton(
              label: 'Enviar corrección',
              isLoading: _busy,
              onPressed: _correctFromText,
            ),
          ],
          const SizedBox(height: 12),
          if (result.chatId != null && result.chatId!.isNotEmpty)
            FilledButton(
              onPressed: () {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute<void>(
                    builder: (_) => DashboardView(
                      initialChatId: result.chatId,
                    ),
                  ),
                  (_) => false,
                );
              },
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF1B4D8A),
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              child: const Text('Ver conversación'),
            ),
          if (result.chatId != null && result.chatId!.isNotEmpty)
            const SizedBox(height: 12),
          FilledButton(
            onPressed: () {
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute<void>(builder: (_) => const DashboardView()),
                (_) => false,
              );
            },
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.ink,
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            child: const Text('Volver al Dashboard'),
          ),
        ],
      ),
    );
  }
}
