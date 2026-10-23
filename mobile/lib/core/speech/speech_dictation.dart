import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

class SpeechDictationController {
  SpeechDictationController({
    this.onListeningChanged,
    this.onError,
  });

  final void Function(bool listening)? onListeningChanged;
  final void Function(String message)? onError;

  final SpeechToText _speech = SpeechToText();
  bool _initialized = false;
  bool _listening = false;
  String _prefix = '';

  bool get isListening => _listening;
  bool get isAvailable => _speech.isAvailable;

  Future<bool> initialize() async {
    if (_initialized) return _speech.isAvailable;
    _initialized = true;
    return _speech.initialize(
      onStatus: (status) {
        if (status == 'done' || status == 'notListening') {
          _setListening(false);
        }
      },
      onError: (error) {
        _setListening(false);
        onError?.call(error.errorMsg);
      },
    );
  }

  Future<void> toggle({
    required String currentText,
    required void Function(String text) onText,
  }) async {
    if (_listening) {
      await stop();
      return;
    }

    final ready = await initialize();
    if (!ready) {
      onError?.call('El dictado por voz no está disponible.');
      return;
    }

    _prefix = currentText;
    if (_prefix.isNotEmpty && !_prefix.endsWith(' ')) {
      _prefix = '$_prefix ';
    }

    final localeId = await _resolveSpanishLocale();
    _setListening(true);

    await _speech.listen(
      onResult: (SpeechRecognitionResult result) {
        onText('$_prefix${result.recognizedWords}');
      },
      listenOptions: SpeechListenOptions(
        partialResults: true,
        listenMode: ListenMode.dictation,
        localeId: localeId,
      ),
    );
  }

  Future<void> stop() async {
    if (!_listening) return;
    await _speech.stop();
    _setListening(false);
  }

  Future<void> dispose() async {
    await stop();
  }

  void _setListening(bool value) {
    if (_listening == value) return;
    _listening = value;
    onListeningChanged?.call(value);
  }

  Future<String?> _resolveSpanishLocale() async {
    final locales = await _speech.locales();
    const preferred = ['es-MX', 'es-ES', 'es-US', 'es'];
    for (final code in preferred) {
      for (final locale in locales) {
        if (locale.localeId == code) return locale.localeId;
      }
    }
    for (final locale in locales) {
      if (locale.localeId.startsWith('es')) return locale.localeId;
    }
    return null;
  }
}
