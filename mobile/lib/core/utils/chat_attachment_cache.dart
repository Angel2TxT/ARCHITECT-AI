import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Cache de adjuntos de chat:
/// - RAM + disco por nombre de archivo (plano enviado por el usuario)
/// - Disco + RAM por `analysis_id` (imagen anotada del análisis)
class ChatAttachmentCache {
  ChatAttachmentCache._();

  static final ChatAttachmentCache instance = ChatAttachmentCache._();

  final Map<String, String> _byFilename = {};
  final Map<int, String> _byAnalysisId = {};
  String? _lastUserUpload;
  Future<Directory>? _annotatedDirFuture;
  Future<Directory>? _userDirFuture;

  Future<Directory> _annotatedDir() {
    return _annotatedDirFuture ??= () async {
      final support = await getApplicationSupportDirectory();
      final dir = Directory('${support.path}/annotated_plans');
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      return dir;
    }();
  }

  Future<Directory> _userDir() {
    return _userDirFuture ??= () async {
      final support = await getApplicationSupportDirectory();
      final dir = Directory('${support.path}/user_plan_uploads');
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      return dir;
    }();
  }

  Future<void> putFile(String filename, File file) async {
    final name = filename.trim();
    if (name.isEmpty) return;
    try {
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) return;
      await putBase64(name, base64Encode(bytes));
    } catch (_) {
      // Si no se puede leer el archivo, la burbuja seguirá con el nombre.
    }
  }

  Future<void> putBase64(String filename, String base64) async {
    final value = _normalizeBase64(base64);
    if (value == null) return;
    final keys = _lookupKeys(filename);
    if (keys.isEmpty) return;

    for (final key in keys) {
      _byFilename[key] = value;
    }
    _lastUserUpload = value;

    try {
      final dir = await _userDir();
      final file = File('${dir.path}/${_diskName(keys.first)}.b64');
      await file.writeAsString(value, flush: true);
    } catch (_) {
      // Queda en memoria aunque falle el disco.
    }
  }

  String? get(String? filename) {
    for (final key in _lookupKeys(filename)) {
      final cached = _byFilename[key];
      if (cached != null && cached.isNotEmpty) return cached;
    }
    return null;
  }

  /// Último plano que el usuario adjuntó en esta sesión (fallback de preview).
  String? get lastUserUpload => _lastUserUpload;

  Future<String?> getAsync(String? filename) async {
    final memory = get(filename);
    if (memory != null && memory.isNotEmpty) return memory;

    for (final key in _lookupKeys(filename)) {
      try {
        final dir = await _userDir();
        final file = File('${dir.path}/${_diskName(key)}.b64');
        if (!await file.exists()) continue;
        final value = _normalizeBase64(await file.readAsString());
        if (value == null) continue;
        _byFilename[key] = value;
        for (final alias in _lookupKeys(filename)) {
          _byFilename[alias] = value;
        }
        return value;
      } catch (_) {
        // Probar siguiente clave.
      }
    }
    return null;
  }

  Future<void> putAnnotated(int analysisId, String base64) async {
    final value = _normalizeBase64(base64);
    if (value == null) return;
    _byAnalysisId[analysisId] = value;
    try {
      final dir = await _annotatedDir();
      final file = File('${dir.path}/$analysisId.b64');
      await file.writeAsString(value, flush: true);
    } catch (_) {
      // La imagen queda en memoria de la sesión aunque falle el disco.
    }
  }

  Future<String?> getAnnotated(int analysisId) async {
    final cached = _byAnalysisId[analysisId];
    if (cached != null && cached.isNotEmpty) return cached;

    try {
      final dir = await _annotatedDir();
      final file = File('${dir.path}/$analysisId.b64');
      if (!await file.exists()) return null;
      final value = _normalizeBase64(await file.readAsString());
      if (value == null) return null;
      _byAnalysisId[analysisId] = value;
      return value;
    } catch (_) {
      return null;
    }
  }

  String? getAnnotatedSync(int analysisId) {
    final cached = _byAnalysisId[analysisId];
    if (cached == null || cached.isEmpty) return null;
    return cached;
  }

  static List<String> _lookupKeys(String? filename) {
    if (filename == null) return const [];
    final raw = filename.trim().toLowerCase();
    if (raw.isEmpty) return const [];
    final base = raw.replaceAll('\\', '/').split('/').last;
    if (base.isEmpty) return [raw];
    if (base == raw) return [raw];
    return [raw, base];
  }

  static String _diskName(String key) {
    final base = key.replaceAll('\\', '/').split('/').last;
    final safe = base.replaceAll(RegExp(r'[^a-z0-9._-]'), '_');
    return safe.isEmpty ? 'plano' : safe;
  }

  static String? _normalizeBase64(String? raw) {
    if (raw == null) return null;
    final value = raw.trim();
    if (value.isEmpty) return null;
    return value.contains(',') ? value.split(',').last.trim() : value;
  }
}
