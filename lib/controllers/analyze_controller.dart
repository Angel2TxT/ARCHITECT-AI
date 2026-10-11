import 'dart:io';

import 'package:flutter/material.dart';
import 'package:movil_architect/core/app_services.dart';
import 'package:movil_architect/core/network/api_exception.dart';
import 'package:movil_architect/models/analysis_models.dart';
import 'package:movil_architect/models/app_config_models.dart';
import 'package:movil_architect/services/mobile_api_service.dart';

enum AnalyzeState { idle, uploading, success, error }

class AnalyzeController extends ChangeNotifier {
  AnalyzeController({MobileApiService? mobileApiService})
      : _mobileApiService =
            mobileApiService ?? AppServices.instance.mobileApiService;

  final MobileApiService _mobileApiService;
  final TextEditingController messageController = TextEditingController();

  AnalyzeState _state = AnalyzeState.idle;
  String? _errorMessage;
  File? _selectedFile;
  String? _selectedFileName;
  AnalysisResult? _result;
  PlanoPreview? _preview;
  bool _disposed = false;

  AnalyzeState get state => _state;
  String? get errorMessage => _errorMessage;
  File? get selectedFile => _selectedFile;
  String? get selectedFileName => _selectedFileName;
  AnalysisResult? get result => _result;
  PlanoPreview? get preview => _preview;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void setFile(File file, String name) {
    _selectedFile = file;
    _selectedFileName = name;
    _errorMessage = null;
    _notify();
    _loadPreview(file);
  }

  void clearFile() {
    _selectedFile = null;
    _selectedFileName = null;
    _preview = null;
    _notify();
  }

  Future<void> _loadPreview(File file) async {
    try {
      final preview = await _mobileApiService.previewPlano(file);
      if (_disposed) return;
      _preview = preview;
      _notify();
    } catch (_) {}
  }

  Future<bool> analyze() async {
    if (_selectedFile == null) {
      _errorMessage = 'Selecciona un plano para analizar.';
      _notify();
      return false;
    }

    _state = AnalyzeState.uploading;
    _errorMessage = null;
    _notify();

    try {
      _result = await _mobileApiService.analyze(
        file: _selectedFile!,
        message: messageController.text,
      );
      _state = AnalyzeState.success;
      return !_disposed;
    } on ApiException catch (error) {
      _state = AnalyzeState.error;
      _errorMessage = error.message;
      return false;
    } catch (error) {
      _state = AnalyzeState.error;
      _errorMessage = 'No se pudo procesar la respuesta del análisis.';
      assert(() {
        debugPrint('AnalyzeController error: $error');
        return true;
      }());
      return false;
    } finally {
      _notify();
    }
  }

  void reset() {
    _state = AnalyzeState.idle;
    _errorMessage = null;
    _result = null;
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    messageController.dispose();
    super.dispose();
  }
}
