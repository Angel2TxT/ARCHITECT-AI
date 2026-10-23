import 'dart:io';

import 'package:flutter/material.dart';
import 'package:movil_architect/core/app_services.dart';
import 'package:movil_architect/core/network/api_exception.dart';
import 'package:movil_architect/core/utils/chat_attachment_cache.dart';
import 'package:movil_architect/models/analysis_models.dart';
import 'package:movil_architect/models/chat_models.dart';
import 'package:movil_architect/services/mobile_api_service.dart';

enum ChatState { loading, success, error, sending }

class ChatController extends ChangeNotifier {
  ChatController({
    required this.chatId,
    MobileApiService? mobileApiService,
  }) : _mobileApiService =
            mobileApiService ?? AppServices.instance.mobileApiService;

  final String chatId;
  final MobileApiService _mobileApiService;
  final TextEditingController messageController = TextEditingController();

  ChatState _state = ChatState.loading;
  String? _errorMessage;
  int? _errorStatusCode;
  ChatDetail? _detail;
  String? _pendingUserMessage;
  File? _pendingPlanoFile;
  String? _pendingPlanoName;
  bool _isAnalyzingPlano = false;
  bool _disposed = false;
  int? _activeAnalysisId;

  ChatState get state => _state;
  String? get errorMessage => _errorMessage;
  int? get errorStatusCode => _errorStatusCode;
  ChatDetail? get detail => _detail;
  List<ChatMessage> get messages => _detail?.messages ?? [];
  String? get pendingUserMessage => _pendingUserMessage;
  String get title => _detail?.chat.title ?? 'Chat';
  bool get isSending => _state == ChatState.sending || _isAnalyzingPlano;
  bool get isAnalyzingPlano => _isAnalyzingPlano;
  File? get pendingPlanoFile => _pendingPlanoFile;
  String? get pendingPlanoName => _pendingPlanoName;
  bool get hasPendingPlano => _pendingPlanoFile != null;
  int? get activeAnalysisId =>
      _activeAnalysisId ?? _detail?.lastAnalysisId;

  Future<void> load({bool showLoading = true}) async {
    if (showLoading) {
      _state = ChatState.loading;
      _errorMessage = null;
      _errorStatusCode = null;
      notifyListeners();
    }

    try {
      _detail = await _mobileApiService.getChat(chatId);
      if (_disposed) return;
      _activeAnalysisId = _detail?.lastAnalysisId ?? _activeAnalysisId;
      if (_state != ChatState.sending && !_isAnalyzingPlano) {
        _state = ChatState.success;
        _errorMessage = null;
        _errorStatusCode = null;
      }
      notifyListeners();
      await _hydrateUserAttachments();
      await _hydrateAnnotatedImages();
    } on ApiException catch (error) {
      if (_disposed) return;
      if (_state != ChatState.sending && !_isAnalyzingPlano) {
        _state = ChatState.error;
        _errorStatusCode = error.statusCode;
        _errorMessage = _mapLoadError(error);
      }
    } catch (_) {
      if (_disposed) return;
      if (_state != ChatState.sending && !_isAnalyzingPlano) {
        _state = ChatState.error;
        _errorMessage = 'No se pudo cargar la conversación.';
        _errorStatusCode = null;
      }
    }

    if (!_disposed) notifyListeners();
  }

  /// Aplica de inmediato la imagen anotada tras analyze/followup.
  Future<void> applyAnalysisResult(AnalysisResult result) async {
    final analysisId = result.analysisId;
    final image = result.imageBase64?.trim();
    if (analysisId != null) {
      _activeAnalysisId = analysisId;
      if (image != null && image.isNotEmpty) {
        await ChatAttachmentCache.instance.putAnnotated(analysisId, image);
        if (_detail != null) {
          _detail = _detail!.withAnnotatedImage(
            analysisId: analysisId,
            imageBase64: image,
          );
        }
      }
    }
    if (!_disposed) notifyListeners();
  }

  Future<bool> sendMessage() async {
    if (_pendingPlanoFile != null) {
      return analyzePendingPlano();
    }

    final text = messageController.text.trim();
    if (text.length < 3 || _state == ChatState.sending) {
      if (text.isNotEmpty && text.length < 3) {
        _errorMessage = 'El mensaje debe tener al menos 3 caracteres.';
        notifyListeners();
      }
      return false;
    }

    _pendingUserMessage = text;
    messageController.clear();
    _state = ChatState.sending;
    _errorMessage = null;
    _errorStatusCode = null;
    notifyListeners();

    try {
      final analysisId = activeAnalysisId;
      if (analysisId != null) {
        final result = await _mobileApiService.sendFollowup(
          message: text,
          analysisId: analysisId,
          chatId: chatId,
        );
        if (_disposed) return false;
        await applyAnalysisResult(result);
      } else {
        await _mobileApiService.sendAsk(
          message: text,
          chatId: chatId,
        );
      }
      if (_disposed) return false;
      await load(showLoading: false);
      if (_disposed) return false;
      _pendingUserMessage = null;
      _state = ChatState.success;
      notifyListeners();
      return true;
    } on ApiException catch (error) {
      if (_disposed) return false;
      _pendingUserMessage = null;
      _state = ChatState.success;
      _errorMessage = _mapSendError(error);
      _errorStatusCode = error.statusCode;
      notifyListeners();
      return false;
    } catch (_) {
      if (_disposed) return false;
      _pendingUserMessage = null;
      _state = ChatState.success;
      _errorMessage = 'No se pudo enviar el mensaje.';
      _errorStatusCode = null;
      notifyListeners();
      return false;
    }
  }

  void setPendingPlano(File file, String name) {
    _pendingPlanoFile = file;
    _pendingPlanoName = name;
    _errorMessage = null;
    notifyListeners();
  }

  void clearPendingPlano() {
    if (_isAnalyzingPlano) return;
    _pendingPlanoFile = null;
    _pendingPlanoName = null;
    notifyListeners();
  }

  Future<bool> analyzePendingPlano() async {
    final file = _pendingPlanoFile;
    if (file == null || _isAnalyzingPlano) return false;

    final text = messageController.text.trim();
    messageController.clear();
    _pendingUserMessage = text.isEmpty ? 'Analiza este plano' : text;
    _isAnalyzingPlano = true;
    _state = ChatState.sending;
    _errorMessage = null;
    _errorStatusCode = null;
    notifyListeners();

    final cacheName = _pendingPlanoName;
    if (cacheName != null && cacheName.isNotEmpty) {
      await ChatAttachmentCache.instance.putFile(cacheName, file);
    }

    try {
      final result = await _mobileApiService.analyze(
        file: file,
        message: text.isEmpty ? null : text,
        chatId: chatId,
      );
      if (_disposed) return false;

      _pendingPlanoFile = null;
      _pendingPlanoName = null;
      await applyAnalysisResult(result);
      await load(showLoading: false);
      if (_disposed) return false;
      _pendingUserMessage = null;
      _isAnalyzingPlano = false;
      _state = ChatState.success;
      notifyListeners();
      return true;
    } on ApiException catch (error) {
      if (_disposed) return false;
      _pendingUserMessage = null;
      _isAnalyzingPlano = false;
      _state = ChatState.success;
      _errorMessage = _mapSendError(error);
      _errorStatusCode = error.statusCode;
      notifyListeners();
      return false;
    } catch (_) {
      if (_disposed) return false;
      _pendingUserMessage = null;
      _isAnalyzingPlano = false;
      _state = ChatState.success;
      _errorMessage = 'No se pudo analizar el plano.';
      _errorStatusCode = null;
      notifyListeners();
      return false;
    }
  }

  Future<bool> correctFromMessage(String message) async {
    final analysisId = activeAnalysisId;
    if (analysisId == null || message.trim().length < 3) return false;
    _state = ChatState.sending;
    notifyListeners();
    try {
      final result = await _mobileApiService.correctFromMessage(
        analysisId: analysisId,
        message: message,
        chatId: chatId,
      );
      if (_disposed) return false;
      await applyAnalysisResult(result);
      await load(showLoading: false);
      _state = ChatState.success;
      notifyListeners();
      return true;
    } on ApiException catch (error) {
      _errorMessage = error.message;
      _state = ChatState.success;
      notifyListeners();
      return false;
    }
  }

  Future<void> _hydrateUserAttachments() async {
    final detail = _detail;
    if (detail == null || _disposed) return;

    final pending = <({int index, String filename})>[];
    for (var i = 0; i < detail.messages.length; i++) {
      final message = detail.messages[i];
      if (!message.isUser) continue;
      final filename = message.content.filename?.trim();
      if (filename == null || filename.isEmpty) continue;
      final existing = message.content.imageBase64?.trim();
      if (existing != null && existing.isNotEmpty) continue;
      pending.add((index: i, filename: filename));
    }
    if (pending.isEmpty) return;

    final images = await Future.wait(
      pending.map((item) async {
        final cached =
            await ChatAttachmentCache.instance.getAsync(item.filename);
        return (index: item.index, image: cached);
      }),
    );

    if (_disposed || _detail == null) return;

    var changed = false;
    final updated = List<ChatMessage>.from(_detail!.messages);
    final lastUpload = ChatAttachmentCache.instance.lastUserUpload;

    for (var i = 0; i < images.length; i++) {
      final item = images[i];
      var image = item.image;
      if ((image == null || image.isEmpty) &&
          i == images.length - 1 &&
          lastUpload != null &&
          lastUpload.isNotEmpty) {
        image = lastUpload;
      }
      if (image == null || image.isEmpty) continue;
      final message = updated[item.index];
      updated[item.index] = message.copyWith(
        content: message.content.copyWith(
          imageBase64: image,
          hasImage: true,
        ),
      );
      changed = true;
    }

    if (!changed) return;
    _detail = ChatDetail(chat: _detail!.chat, messages: updated);
    notifyListeners();
  }

  Future<void> _hydrateAnnotatedImages() async {
    final detail = _detail;
    if (detail == null || _disposed) return;

    final pending = <({int index, int analysisId})>[];
    for (var i = 0; i < detail.messages.length; i++) {
      final message = detail.messages[i];
      if (!message.isAssistant || !message.content.needsAnnotatedImage) {
        continue;
      }
      pending.add((index: i, analysisId: message.content.analysisId!));
    }
    if (pending.isEmpty) return;

    final images = await Future.wait(
      pending.map((item) async {
        final cached =
            await ChatAttachmentCache.instance.getAnnotated(item.analysisId);
        if (cached != null && cached.isNotEmpty) {
          return (index: item.index, image: cached);
        }
        try {
          final fetched =
              await _mobileApiService.getAnnotatedImage(item.analysisId);
          if (fetched != null && fetched.isNotEmpty) {
            await ChatAttachmentCache.instance.putAnnotated(
              item.analysisId,
              fetched,
            );
            return (index: item.index, image: fetched);
          }
        } catch (_) {
          // 404 u otros errores: ocultar preview, no romper el chat.
        }
        return (index: item.index, image: null as String?);
      }),
    );

    if (_disposed || _detail == null) return;

    var changed = false;
    final updated = List<ChatMessage>.from(_detail!.messages);
    for (final item in images) {
      final image = item.image;
      if (image == null || image.isEmpty) continue;
      final message = updated[item.index];
      updated[item.index] = message.copyWith(
        content: message.content.copyWith(
          imageBase64: image,
          hasImage: true,
        ),
      );
      changed = true;
    }

    if (!changed) return;
    _detail = ChatDetail(chat: _detail!.chat, messages: updated);
    notifyListeners();
  }

  String _mapLoadError(ApiException error) {
    if (error.statusCode == 404) return 'Conversación no encontrada.';
    if (error.statusCode == 403) {
      return error.message.isNotEmpty
          ? error.message
          : 'No tienes permiso o alcanzaste el límite de tu plan.';
    }
    return error.message;
  }

  String _mapSendError(ApiException error) {
    if (error.statusCode == 403) {
      return error.message.isNotEmpty
          ? error.message
          : 'No tienes permiso o alcanzaste el límite de tu plan.';
    }
    if (error.statusCode == 404) return 'Conversación no encontrada.';
    return error.message;
  }

  @override
  void dispose() {
    _disposed = true;
    messageController.dispose();
    super.dispose();
  }
}
