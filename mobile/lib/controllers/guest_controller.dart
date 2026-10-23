import 'dart:io';

import 'package:flutter/material.dart';
import 'package:movil_architect/core/app_services.dart';
import 'package:movil_architect/core/network/api_exception.dart';
import 'package:movil_architect/core/utils/chat_attachment_cache.dart';
import 'package:movil_architect/models/analysis_models.dart';
import 'package:movil_architect/models/app_config_models.dart';
import 'package:movil_architect/models/chat_models.dart';
import 'package:movil_architect/services/guest_service.dart';
import 'package:movil_architect/services/mobile_api_service.dart';

enum GuestUiState { loading, ready, error }

class GuestController extends ChangeNotifier {
  GuestController({
    GuestService? guestService,
    MobileApiService? mobileApiService,
  })  : _guestService = guestService ?? AppServices.instance.guestService,
        _mobileApiService =
            mobileApiService ?? AppServices.instance.mobileApiService;

  final GuestService _guestService;
  final MobileApiService _mobileApiService;
  final TextEditingController messageController = TextEditingController();

  GuestUiState _state = GuestUiState.loading;
  GuestStatus? _status;
  String? _errorMessage;
  String? _actionError;
  final List<ChatMessage> _messages = [];
  int _nextMessageId = 1;

  File? _pendingPlanoFile;
  String? _pendingPlanoName;
  bool _isLoadingPendingPlano = false;
  double _pendingPlanoLoadProgress = 0;
  bool _isSending = false;
  bool _isAnalyzing = false;
  String? _pendingUserMessage;
  File? _displayPlanoFile;
  String? _displayPlanoName;
  int _planoLoadGeneration = 0;
  bool _disposed = false;

  GuestUiState get state => _state;
  GuestStatus? get status => _status;
  String? get errorMessage => _errorMessage;
  String? get actionError => _actionError;
  List<ChatMessage> get messages => List.unmodifiable(_messages);
  File? get pendingPlanoFile => _pendingPlanoFile;
  String? get pendingPlanoName => _pendingPlanoName;
  bool get hasPendingPlano => _pendingPlanoFile != null;
  bool get isLoadingPendingPlano => _isLoadingPendingPlano;
  double get pendingPlanoLoadProgress => _pendingPlanoLoadProgress;
  bool get isSending => _isSending || _isAnalyzing;
  bool get isAnalyzing => _isAnalyzing;
  String? get pendingUserMessage => _pendingUserMessage;
  File? get displayPlanoFile => _displayPlanoFile ?? _pendingPlanoFile;
  String? get displayPlanoName => _displayPlanoName ?? _pendingPlanoName;
  bool get hasConversation =>
      _messages.isNotEmpty ||
      _pendingUserMessage != null ||
      _isSending ||
      _isAnalyzing;

  int get analysesRemaining => _status?.analysesRemaining ?? 0;
  int get asksRemaining => _status?.asksRemaining ?? 0;
  bool get canAnalyze => analysesRemaining > 0 && !trialExhausted;
  bool get canAsk => asksRemaining > 0 && !trialExhausted;
  bool get trialExhausted => _status?.trialExhausted ?? false;
  bool get canContinueTrial => canAnalyze || canAsk || hasPendingPlano;

  Future<void> load() async {
    _state = GuestUiState.loading;
    _errorMessage = null;
    notifyListeners();

    try {
      _status = await _guestService.status();
      if (_disposed) return;
      _state = GuestUiState.ready;
    } on ApiException catch (error) {
      if (_disposed) return;
      if (error.isPlanLimit) {
        _status = _exhaustedStatus();
        _state = GuestUiState.ready;
      } else {
        _state = GuestUiState.error;
        _errorMessage = error.message;
      }
    } catch (_) {
      if (_disposed) return;
      _state = GuestUiState.error;
      _errorMessage = 'No se pudo cargar el modo de prueba.';
    }

    if (!_disposed) notifyListeners();
  }

  Future<void> preparePendingPlano(File file, String name) async {
    if (!canAnalyze) {
      _actionError = 'Ya usaste el análisis de prueba. Crea una cuenta para continuar.';
      notifyListeners();
      return;
    }

    final generation = ++_planoLoadGeneration;
    _isLoadingPendingPlano = true;
    _pendingPlanoLoadProgress = 0;
    _pendingPlanoName = name;
    _pendingPlanoFile = null;
    _actionError = null;
    notifyListeners();

    try {
      if (!await file.exists()) {
        if (generation != _planoLoadGeneration) return;
        _actionError = 'No se pudo acceder al archivo.';
        _pendingPlanoName = null;
        return;
      }

      final total = await file.length();
      if (total == 0) {
        if (generation != _planoLoadGeneration) return;
        _actionError = 'El archivo está vacío.';
        _pendingPlanoName = null;
        return;
      }

      _pendingPlanoFile = file;
      _pendingPlanoLoadProgress = 1;
    } catch (_) {
      if (generation != _planoLoadGeneration) return;
      _actionError = 'No se pudo cargar el plano.';
      _pendingPlanoName = null;
      _pendingPlanoFile = null;
    } finally {
      if (generation == _planoLoadGeneration) {
        _isLoadingPendingPlano = false;
        notifyListeners();
      }
    }
  }

  void clearPendingPlano() {
    if (_isLoadingPendingPlano || _isAnalyzing) return;
    _planoLoadGeneration++;
    _pendingPlanoFile = null;
    _pendingPlanoName = null;
    _pendingPlanoLoadProgress = 0;
    _clearDisplayPlano();
    notifyListeners();
  }

  void cancelPendingPlanoLoad() {
    _planoLoadGeneration++;
    _isLoadingPendingPlano = false;
    _pendingPlanoFile = null;
    _pendingPlanoName = null;
    _pendingPlanoLoadProgress = 0;
    _clearDisplayPlano();
    notifyListeners();
  }

  Future<bool> send() async {
    if (_isSending || _isAnalyzing || _isLoadingPendingPlano) return false;

    if (hasPendingPlano) {
      return _analyzePendingPlano();
    }
    return _ask();
  }

  Future<bool> _ask() async {
    final text = messageController.text.trim();
    if (text.length < 3) {
      _actionError = 'Escribe al menos 3 caracteres.';
      notifyListeners();
      return false;
    }
    if (!canAsk) {
      _actionError =
          'Ya usaste tu pregunta de prueba. Crea una cuenta para continuar.';
      notifyListeners();
      return false;
    }

    messageController.clear();
    _pendingUserMessage = text;
    _isSending = true;
    _actionError = null;
    notifyListeners();

    try {
      final result = await _guestService.ask(text);
      if (_disposed) return false;
      _appendUserMessage(text: text);
      _appendAssistantMessage(text: result.text ?? 'Listo.');
      _pendingUserMessage = null;
      await _refreshStatus();
      return true;
    } on ApiException catch (error) {
      return _handleSendError(error);
    } catch (_) {
      _pendingUserMessage = null;
      _actionError = 'No se pudo enviar la pregunta.';
      return false;
    } finally {
      _isSending = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<bool> _analyzePendingPlano() async {
    if (_pendingPlanoFile == null) return false;
    if (!canAnalyze) {
      _actionError =
          'Ya usaste el análisis de prueba. Crea una cuenta para continuar.';
      notifyListeners();
      return false;
    }

    final text = messageController.text.trim();
    messageController.clear();
    _pendingUserMessage = text.isEmpty ? 'Analiza este plano' : text;
    _isAnalyzing = true;
    _actionError = null;
    _displayPlanoFile = _pendingPlanoFile;
    _displayPlanoName = _pendingPlanoName;
    _pendingPlanoFile = null;
    _pendingPlanoName = null;
    notifyListeners();

    try {
      final config = await _mobileApiService.getConfig();
      if (_disposed) return false;
      final result = await _guestService.analyze(
        file: _displayPlanoFile!,
        message: text,
        autoCalibrate: config.autoCalibrateDefault,
        ppm: config.defaultPpm,
        conf: config.defaultConf,
      );
      if (_disposed) return false;

      final planoName = _displayPlanoName;
      final planoFile = _displayPlanoFile;
      if (planoName != null && planoFile != null) {
        await ChatAttachmentCache.instance.putFile(planoName, planoFile);
      }
      _appendUserMessage(
        text: _pendingUserMessage,
        filename: planoName,
        imageBase64: ChatAttachmentCache.instance.get(planoName),
      );
      _appendAssistantFromAnalysis(result);
      _pendingUserMessage = null;
      _clearDisplayPlano();
      await _refreshStatus();
      return true;
    } on ApiException catch (error) {
      _pendingPlanoFile = _displayPlanoFile;
      _pendingPlanoName = _displayPlanoName;
      _clearDisplayPlano();
      return _handleSendError(error);
    } catch (_) {
      _pendingUserMessage = null;
      _pendingPlanoFile = _displayPlanoFile;
      _pendingPlanoName = _displayPlanoName;
      _clearDisplayPlano();
      _actionError = 'No se pudo analizar el plano.';
      return false;
    } finally {
      _isAnalyzing = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> _refreshStatus() async {
    try {
      _status = await _guestService.status();
    } on ApiException catch (error) {
      if (error.isPlanLimit) {
        _status = _exhaustedStatus();
      }
    }
  }

  bool _handleSendError(ApiException error) {
    _pendingUserMessage = null;
    if (error.isPlanLimit) {
      _status = _exhaustedStatus();
      _actionError =
          'Tu prueba se agotó. Crea una cuenta o inicia sesión.';
    } else {
      _actionError = error.message;
    }
    return false;
  }

  void _appendUserMessage({
    String? text,
    String? filename,
    String? imageBase64,
  }) {
    _messages.add(
      ChatMessage(
        id: _nextMessageId++,
        role: 'user',
        content: MessageContent(
          text: text,
          filename: filename,
          imageBase64: imageBase64,
        ),
        createdAt: DateTime.now(),
      ),
    );
  }

  void _appendAssistantMessage({String? text}) {
    _messages.add(
      ChatMessage(
        id: _nextMessageId++,
        role: 'assistant',
        content: MessageContent(text: text),
        createdAt: DateTime.now(),
      ),
    );
  }

  void _appendAssistantFromAnalysis(AnalysisResult result) {
    _messages.add(
      ChatMessage(
        id: _nextMessageId++,
        role: 'assistant',
        content: MessageContent(
          text: result.assistantText ?? result.markdown,
          analysisId: result.analysisId,
          verdict: result.verdict,
          imageBase64: result.imageBase64,
          stats: result.counts,
        ),
        createdAt: DateTime.now(),
      ),
    );
  }

  void _clearDisplayPlano() {
    _displayPlanoFile = null;
    _displayPlanoName = null;
  }

  GuestStatus _exhaustedStatus() {
    return GuestStatus(
      guest: true,
      analysesUsed: _status?.analysesLimit ?? 1,
      analysesLimit: _status?.analysesLimit ?? 1,
      analysesRemaining: 0,
      asksUsed: _status?.asksLimit ?? 1,
      asksLimit: _status?.asksLimit ?? 1,
      asksRemaining: 0,
      trialAvailable: false,
      trialExhausted: true,
      maxFileMb: _status?.maxFileMb ?? 8,
    );
  }

  @override
  void dispose() {
    _disposed = true;
    messageController.dispose();
    super.dispose();
  }
}
