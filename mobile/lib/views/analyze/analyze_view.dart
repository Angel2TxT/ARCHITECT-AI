import 'dart:io';

import 'package:flutter/material.dart';
import 'package:movil_architect/controllers/analyze_controller.dart';
import 'package:movil_architect/core/utils/image_utils.dart';
import 'package:movil_architect/views/analysis/analysis_results_view.dart';
import 'package:movil_architect/views/dashboard/widgets/dashboard_shell.dart';
import 'package:movil_architect/views/shared/app_states.dart';
import 'package:movil_architect/views/shared/attachment_picker_sheet.dart';

class AnalyzeView extends StatefulWidget {
  const AnalyzeView({
    super.key,
    this.initialFile,
    this.initialFileName,
  });

  final File? initialFile;
  final String? initialFileName;

  @override
  State<AnalyzeView> createState() => _AnalyzeViewState();
}

class _AnalyzeViewState extends State<AnalyzeView> {
  late final AnalyzeController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnalyzeController();
    if (widget.initialFile != null) {
      _controller.setFile(
        widget.initialFile!,
        widget.initialFileName ?? 'plano',
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _openPicker() async {
    final pick = await showAttachmentPickerSheet(context);
    if (pick == null) return;
    _controller.setFile(pick.file, pick.name);
  }

  Future<void> _analyze() async {
    if (!await _controller.analyze()) return;
    if (!mounted || _controller.result == null) return;

    await Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => AnalysisResultsView(result: _controller.result!),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        iconTheme: IconThemeData(color: colorScheme.onSurface),
        title: Text(
          'Tu plano',
          style: TextStyle(
            color: colorScheme.onSurface,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) {
          if (_controller.state == AnalyzeState.uploading) {
            return const AppLoadingView(
              message: 'Analizando plano...\nEsto puede tardar unos segundos.',
            );
          }

          final file = _controller.selectedFile;
          final fileName = _controller.selectedFileName;
          final isImage =
              fileName != null && isPlanoImageFile(fileName);

          return Column(
            children: [
              Expanded(
                child: file == null
                    ? _EmptyPlanoState(onPick: _openPicker)
                    : SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                        physics: const BouncingScrollPhysics(),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (_controller.preview != null &&
                                _controller.preview!.imageBase64.isNotEmpty)
                              ClipRRect(
                                borderRadius: BorderRadius.circular(20),
                                child: AspectRatio(
                                  aspectRatio: 4 / 3,
                                  child: Image.memory(
                                    decodeBase64Image(
                                      _controller.preview!.imageBase64,
                                    ),
                                    fit: BoxFit.contain,
                                  ),
                                ),
                              )
                            else if (isImage)
                              ClipRRect(
                                borderRadius: BorderRadius.circular(20),
                                child: AspectRatio(
                                  aspectRatio: 4 / 3,
                                  child: Image.file(
                                    file,
                                    fit: BoxFit.contain,
                                  ),
                                ),
                              )
                            else
                              _FilePreviewCard(
                                fileName: fileName!,
                                onChange: _openPicker,
                                onRemove: _controller.clearFile,
                              ),
                            if (isImage) ...[
                              const SizedBox(height: 12),
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton.icon(
                                  onPressed: _openPicker,
                                  icon: const Icon(Icons.swap_horiz_rounded),
                                  label: const Text('Cambiar plano'),
                                ),
                              ),
                            ],
                            const SizedBox(height: 8),
                            Text(
                              'Escribe abajo qué quieres revisar: medidas, puertas, normativa, o simplemente pregunta si está bien.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: colorScheme.onSurfaceVariant,
                                fontSize: 14,
                                height: 1.4,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
              ),
              if (_controller.errorMessage != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Text(
                    _controller.errorMessage!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.redAccent,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              DashboardAskBar(
                controller: _controller.messageController,
                hintText: 'Indica qué revisar en tu plano',
                onAttachTap: _openPicker,
                onSendTap: _analyze,
                isSending: false,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _EmptyPlanoState extends StatelessWidget {
  const _EmptyPlanoState({required this.onPick});

  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.add_photo_alternate_outlined,
              size: 56,
              color: colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              'Selecciona un plano para analizar',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colorScheme.onSurface,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onPick,
              icon: const Icon(Icons.attach_file),
              label: const Text('Elegir archivo'),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilePreviewCard extends StatelessWidget {
  const _FilePreviewCard({
    required this.fileName,
    required this.onChange,
    required this.onRemove,
  });

  final String fileName;
  final VoidCallback onChange;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(Icons.description_outlined, color: colorScheme.onSurface),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              fileName,
              style: TextStyle(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          IconButton(
            onPressed: onChange,
            icon: const Icon(Icons.swap_horiz_rounded),
            tooltip: 'Cambiar',
          ),
          IconButton(
            onPressed: onRemove,
            icon: const Icon(Icons.close),
            tooltip: 'Quitar',
          ),
        ],
      ),
    );
  }
}
