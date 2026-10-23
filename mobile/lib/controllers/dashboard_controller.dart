import 'dart:io';

import 'package:flutter/material.dart';
import 'package:movil_architect/core/app_services.dart';
import 'package:movil_architect/core/network/api_exception.dart';
import 'package:movil_architect/core/storage/secure_storage_service.dart';
import 'package:movil_architect/core/utils/chat_attachment_cache.dart';
import 'package:movil_architect/models/analysis_models.dart';
import 'package:movil_architect/models/app_config_models.dart';
import 'package:movil_architect/models/auth_models.dart';
import 'package:movil_architect/models/chat_models.dart';
import 'package:movil_architect/services/auth_service.dart';
import 'package:movil_architect/services/mobile_api_service.dart';

enum DashboardState { loading, success, error, empty }

class DashboardController extends ChangeNotifier {
  DashboardController({
    AuthService? authService,
    MobileApiService? mobileApiService,
    SecureStorageService? secureStorage,
  })  : _authService = authService ?? AppServices.instance.authService,
        _mobileApiService =
            mobileApiService ?? AppServices.instance.mobileApiService,
        _secureStorage =
            secureStorage ?? AppServices.instance.secureStorage;

  final AuthService _authService;
  final MobileApiService _mobileApiService;
  final SecureStorageService _secureStorage;
  final TextEditingController askController = TextEditingController();

  DashboardState _state = DashboardState.loading;
  String? _errorMessage;
  List<AnalysisSummary> _analyses = [];
  List<ChatSummary> _chats = [];
  final Set<String> _pinnedChatIds = {};
  bool _isSendingAsk = false;
  String? _askErrorMessage;
  String? _activeChatId;
  String? _pendingAskMessage;
  File? _pendingPlanoFile;
  String? _pendingPlanoName;
  bool _isLoadingPendingPlano = false;
  double _pendingPlanoLoadProgress = 0;
  bool _isAnalyzingPlano = false;
  File? _displayPlanoFile;
  String? _displayPlanoName;
  int _planoLoadGeneration = 0;
  PlanoPreview? _pendingPreview;

  DashboardState get state => _state;
  String? get errorMessage => _errorMessage;
  List<AnalysisSummary> get analyses => _analyses;
  List<ChatSummary> get chats => _chats;
  bool isChatPinned(String chatId) => _pinnedChatIds.contains(chatId);
  UserModel? get user => _authService.currentUser;
  SubscriptionModel? get subscription => _authService.subscription;
  bool get isSendingAsk => _isSendingAsk;
  String? get askErrorMessage => _askErrorMessage;
  String? get activeChatId => _activeChatId;
  String? get pendingAskMessage => _pendingAskMessage;
  bool get hasActiveChat => _activeChatId != null;
  File? get pendingPlanoFile => _pendingPlanoFile;
  String? get pendingPlanoName => _pendingPlanoName;
  bool get hasPendingPlano => _pendingPlanoFile != null;
  bool get isLoadingPendingPlano => _isLoadingPendingPlano;
  double get pendingPlanoLoadProgress => _pendingPlanoLoadProgress;
  bool get isAnalyzingPlano => _isAnalyzingPlano;
  bool get hasPlanoAttachment =>
      _isLoadingPendingPlano ||
      _pendingPlanoFile != null ||
      _displayPlanoFile != null;
  File? get displayPlanoFile => _displayPlanoFile ?? _pendingPlanoFile;
  String? get displayPlanoName => _displayPlanoName ?? _pendingPlanoName;
  double? get displayPlanoLoadProgress =>
      _isLoadingPendingPlano ? _pendingPlanoLoadProgress : null;
  PlanoPreview? get pendingPreview => _pendingPreview;

  void _clearDisplayPlano() {
    _displayPlanoFile = null;
    _displayPlanoName = null;
  }

  Future<void> preparePendingPlano(File file, String name) async {
    final generation = ++_planoLoadGeneration;
    _isLoadingPendingPlano = true;
    _pendingPlanoLoadProgress = 0;
    _pendingPlanoName = name;
    _pendingPlanoFile = null;
    _askErrorMessage = null;
    notifyListeners();

    try {
      if (!await file.exists()) {
        if (generation != _planoLoadGeneration) return;
        _askErrorMessage = 'No se pudo acceder al archivo.';
        _pendingPlanoName = null;
        return;
      }

      final total = await file.length();
      if (total == 0) {
        if (generation != _planoLoadGeneration) return;
        _askErrorMessage = 'El archivo está vacío.';
        _pendingPlanoName = null;
        return;
      }

      final raf = await file.open();
      try {
        const chunkSize = 64 * 1024;
        var read = 0;
        while (read < total) {
          if (generation != _planoLoadGeneration) return;
          final toRead =
              read + chunkSize > total ? total - read : chunkSize;
          await raf.read(toRead);
          read += toRead;
          if (generation != _planoLoadGeneration) return;
          _pendingPlanoLoadProgress = read / total;
          notifyListeners();
        }
      } finally {
        await raf.close();
      }

      if (generation != _planoLoadGeneration) return;
      _pendingPlanoFile = file;
      _pendingPlanoLoadProgress = 1;
      await ChatAttachmentCache.instance.putFile(name, file);
      try {
        _pendingPreview = await _mobileApiService.previewPlano(file);
      } catch (_) {
        _pendingPreview = null;
      }
    } catch (_) {
      if (generation != _planoLoadGeneration) return;
      _askErrorMessage = 'No se pudo cargar el plano.';
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
    if (_isLoadingPendingPlano || _isAnalyzingPlano) return;
    _pendingPlanoFile = null;
    _pendingPlanoName = null;
    _pendingPlanoLoadProgress = 0;
    _pendingPreview = null;
    _clearDisplayPlano();
    notifyListeners();
  }

  void cancelPendingPlanoLoad() {
    _planoLoadGeneration++;
    _isLoadingPendingPlano = false;
    _pendingPlanoFile = null;
    _pendingPlanoName = null;
    _pendingPlanoLoadProgress = 0;
    _pendingPreview = null;
    _clearDisplayPlano();
    notifyListeners();
  }

  /// Analiza el plano adjunto con el mensaje indicado.
  Future<AnalysisResult?> analyzePendingPlano({required String message}) async {
    if (_pendingPlanoFile == null ||
        _isAnalyzingPlano ||
        _isLoadingPendingPlano) {
      return null;
    }

    final text = message.trim();
    _pendingAskMessage = text.isEmpty ? 'Analiza este plano' : text;
    _isAnalyzingPlano = true;
    _askErrorMessage = null;

    final file = _pendingPlanoFile!;
    _displayPlanoFile = file;
    _displayPlanoName = _pendingPlanoName;
    _pendingPlanoFile = null;
    _pendingPlanoName = null;
    _pendingPlanoLoadProgress = 0;
    notifyListeners();

    final cacheName = _displayPlanoName;
    if (cacheName != null && cacheName.isNotEmpty) {
      await ChatAttachmentCache.instance.putFile(cacheName, file);
    }

    try {
      final result = await _mobileApiService.analyze(
        file: file,
        message: text.isEmpty ? null : text,
        chatId: _activeChatId,
      );

      final chatId = result.chatId ?? _activeChatId;
      if (chatId != null && chatId.isNotEmpty) {
        _activeChatId = chatId;
      }

      final analysisId = result.analysisId;
      final annotated = result.imageBase64?.trim();
      if (analysisId != null &&
          annotated != null &&
          annotated.isNotEmpty) {
        await ChatAttachmentCache.instance.putAnnotated(
          analysisId,
          annotated,
        );
      }

      _pendingAskMessage = null;
      _clearDisplayPlano();

      if (result.chatId != null && result.chatId!.isNotEmpty) {
        _activeChatId = result.chatId;
      }

      await load(refresh: true);
      return result;
    } on ApiException catch (error) {
      _pendingAskMessage = null;
      _pendingPlanoFile = _displayPlanoFile;
      _pendingPlanoName = _displayPlanoName;
      _clearDisplayPlano();
      _askErrorMessage = error.message;
      return null;
    } catch (_) {
      _pendingAskMessage = null;
      _pendingPlanoFile = _displayPlanoFile;
      _pendingPlanoName = _displayPlanoName;
      _clearDisplayPlano();
      _askErrorMessage = 'No se pudo analizar el plano.';
      return null;
    } finally {
      _isAnalyzingPlano = false;
      notifyListeners();
    }
  }

  void setActiveChat(String chatId) {
    _activeChatId = chatId;
    notifyListeners();
  }

  Future<String?> createNewChat() async {
    try {
      final chat = await _mobileApiService.createChat();
      _chats = [chat, ..._chats.where((item) => item.id != chat.id)];
      _activeChatId = chat.id;
      _pendingAskMessage = null;
      notifyListeners();
      return chat.id;
    } on ApiException catch (error) {
      _askErrorMessage = error.message;
      notifyListeners();
      return null;
    }
  }

  void clearActiveChat() {
    _activeChatId = null;
    _pendingAskMessage = null;
    clearPendingPlano();
    notifyListeners();
  }

  Future<void> load({bool refresh = false}) async {
    if (!refresh) {
      _state = DashboardState.loading;
      _errorMessage = null;
      notifyListeners();
    }

    try {
      final me = await _mobileApiService.me();
      _authService.updateSession(
        user: me.user,
        subscription: me.subscription,
      );

      final rawChats = await _mobileApiService.listChats();
      final validChats = <ChatSummary>[];
      for (final chat in rawChats) {
        if (chat.title == 'Nuevo chat' && chat.messageCount == 0) {
          // Chat huérfano sin mensajes creado previamente: limpiar del servidor
          _mobileApiService.deleteChat(chat.id).catchError((_) {});
        } else {
          validChats.add(chat);
        }
      }
      _chats = validChats;
      await _loadPinnedChats();
      _sortChats();
      _analyses = await _mobileApiService.listAnalyses();
      _state = DashboardState.success;
      _errorMessage = null;
    } on ApiException catch (error) {
      _state = DashboardState.error;
      _errorMessage = error.message;
    } catch (_) {
      _state = DashboardState.error;
      _errorMessage = 'No se pudo cargar el dashboard.';
    }

    notifyListeners();
  }

  Future<void> logout() => _authService.logout();

  Future<void> deleteChat(String chatId) async {
    await _mobileApiService.deleteChat(chatId);
    _chats.removeWhere((chat) => chat.id == chatId);
    _pinnedChatIds.remove(chatId);
    await _savePinnedChats();
    if (_activeChatId == chatId) {
      _activeChatId = null;
      _pendingAskMessage = null;
    }
    notifyListeners();
  }

  Future<void> renameChat({
    required String chatId,
    required String title,
  }) async {
    final trimmed = title.trim();
    if (trimmed.isEmpty) {
      throw ApiException(message: 'El nombre no puede estar vacío.');
    }

    final updated = await _mobileApiService.renameChat(
      chatId: chatId,
      title: trimmed,
    );

    final index = _chats.indexWhere((chat) => chat.id == chatId);
    if (index >= 0) {
      final current = _chats[index];
      _chats[index] = current.copyWith(
        title: updated.title.isNotEmpty ? updated.title : trimmed,
        updatedAt: updated.updatedAt ?? DateTime.now(),
        messageCount: updated.messageCount > 0
            ? updated.messageCount
            : current.messageCount,
      );
    }
    _sortChats();
    notifyListeners();
  }

  Future<void> togglePinChat(String chatId) async {
    if (_pinnedChatIds.contains(chatId)) {
      _pinnedChatIds.remove(chatId);
    } else {
      _pinnedChatIds.add(chatId);
    }
    await _savePinnedChats();
    _sortChats();
    notifyListeners();
  }

  Future<void> _loadPinnedChats() async {
    try {
      final ids = await _secureStorage.getPinnedChatIds();
      _pinnedChatIds
        ..clear()
        ..addAll(ids);
    } catch (_) {
      _pinnedChatIds.clear();
    }
    _pinnedChatIds.removeWhere(
      (id) => !_chats.any((chat) => chat.id == id),
    );
  }

  Future<void> _savePinnedChats() async {
    try {
      await _secureStorage.savePinnedChatIds(_pinnedChatIds.toList());
    } catch (_) {}
  }

  void _sortChats() {
    _chats.sort((a, b) {
      final aPinned = _pinnedChatIds.contains(a.id);
      final bPinned = _pinnedChatIds.contains(b.id);
      if (aPinned != bPinned) return aPinned ? -1 : 1;
      final aTime = a.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bTime = b.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bTime.compareTo(aTime);
    });
  }

  Future<void> deleteAllChats() async {
    final ids = _chats.map((chat) => chat.id).toList();
    var failed = 0;
    for (final id in ids) {
      try {
        await _mobileApiService.deleteChat(id);
        _chats.removeWhere((chat) => chat.id == id);
        if (_activeChatId == id) {
          _activeChatId = null;
          _pendingAskMessage = null;
        }
      } catch (_) {
        failed++;
      }
    }
    _pinnedChatIds.clear();
    await _savePinnedChats();
    notifyListeners();
    if (failed > 0) {
      throw ApiException(
        message: failed == ids.length
            ? 'No se pudieron eliminar las conversaciones.'
            : 'Se eliminaron algunas conversaciones, pero $failed fallaron.',
      );
    }
  }

  /// Envía una pregunta general (sin plano). Mantiene el chat activo en el dashboard.
  Future<String?> sendAsk() async {
    final text = askController.text.trim();
    if (text.length < 3 || _isSendingAsk) {
      if (text.isNotEmpty && text.length < 3) {
        _askErrorMessage = 'El mensaje debe tener al menos 3 caracteres.';
        notifyListeners();
      }
      return null;
    }

    _pendingAskMessage = text;
    askController.clear();
    _isSendingAsk = true;
    _askErrorMessage = null;
    notifyListeners();

    try {
      var chatId = _activeChatId;
      if (chatId == null || chatId.isEmpty) {
        final created = await _mobileApiService.createChat();
        chatId = created.id;
        _activeChatId = chatId;
      }
      final response = await _mobileApiService.sendAsk(
        message: text,
        chatId: chatId,
      );
      _activeChatId = response.chatId ?? chatId;
      await load(refresh: true);
      _pendingAskMessage = null;
      _isSendingAsk = false;
      notifyListeners();
      return _activeChatId;
    } on ApiException catch (error) {
      _pendingAskMessage = null;
      _isSendingAsk = false;
      _askErrorMessage = error.message;
      notifyListeners();
      return null;
    } catch (_) {
      _pendingAskMessage = null;
      _isSendingAsk = false;
      _askErrorMessage = 'No se pudo enviar la pregunta.';
      notifyListeners();
      return null;
    }
  }

  @override
  void dispose() {
    askController.dispose();
    super.dispose();
  }
}
