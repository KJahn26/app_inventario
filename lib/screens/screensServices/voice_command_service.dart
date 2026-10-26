import 'package:speech_to_text/speech_to_text.dart' as stt;

/// Envuelve el reconocimiento de voz nativo de Android. No interpreta
/// el significado del texto — eso lo hace [VoiceParserService].
class VoiceCommandService {
  static final stt.SpeechToText _speech = stt.SpeechToText();
  static bool _disponible = false;
  static String? _localeId;

  static Future<bool> inicializar() async {
    _disponible = await _speech.initialize(onError: (_) {}, onStatus: (_) {});

    if (_disponible) {
      // Busca un locale en español entre los disponibles del
      // dispositivo; si no hay ninguno, usa el que venga por defecto.
      final locales = await _speech.locales();
      final esLocale = locales.where((l) => l.localeId.toLowerCase().startsWith('es'));
      _localeId = esLocale.isNotEmpty ? esLocale.first.localeId : null;
    }
    return _disponible;
  }

  static Future<void> escuchar({
    required void Function(String texto, bool esFinal) onResultado,
  }) async {
    if (!_disponible) return;
    await _speech.listen(
      // ignore: deprecated_member_use
      localeId: _localeId,
      onResult: (r) => onResultado(r.recognizedWords, r.finalResult),
    );
  }

  static Future<void> detener() => _speech.stop();
  static void cancelar() => _speech.cancel();
  static bool get disponible => _disponible;
}