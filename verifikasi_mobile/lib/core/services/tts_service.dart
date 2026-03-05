import 'package:flutter_tts/flutter_tts.dart';

class TtsService {
  static final FlutterTts _flutterTts = FlutterTts();
  static bool _isInitialized = false;

  // Initialize TTS with Indonesian voice
  static Future<void> initialize() async {
    if (_isInitialized) return;

    await _flutterTts.setLanguage("id-ID");
    await _flutterTts.setSpeechRate(0.5);
    await _flutterTts.setVolume(1.0);
    await _flutterTts.setPitch(1.0);

    _isInitialized = true;
  }

  // Stop any ongoing speech
  static Future<void> stop() async {
    await _flutterTts.stop();
  }

  // Speak the given text
  static Future<void> speak(String text) async {
    await initialize();
    await stop();
    await _flutterTts.speak(text);
  }

  // Layer 1: Pengawas
  static Future<void> scanPengawasBerhasil() async {
    await speak("Berhasil.");
  }

  static Future<void> duplikatPengawas() async {
    await speak("Sudah Scan.");
  }

  // Layer 2: Security
  static Future<void> scanSecurityBerhasil() async {
    await speak("Silakan Pulang.");
  }

  static Future<void> ditolakBelumPengawas() async {
    await speak("Ditolak.");
  }

  static Future<void> duplikatSecurity() async {
    await speak("Sudah Checkout.");
  }

  // Sistem / Error
  static Future<void> qrTidakDikenal() async {
    await speak("Tidak Dikenal.");
  }

  static Future<void> gagalKoneksi() async {
    await speak("Gagal Koneksi.");
  }
}
