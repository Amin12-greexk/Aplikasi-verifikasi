import 'dart:core';

String _extractBarcodeInfo(String fullBarcode) {
  final raw = fullBarcode.trim();
  if (raw.isEmpty) return '';

  try {
    final patterns = {
      'PIN': RegExp(r'PIN\s*:\s*(.*?)(?=NAMA|NIK|BAGIAN|ALAMAT|ALAMAT|$)', caseSensitive: false, dotAll: true),
      'Nama': RegExp(r'NAMA\s*:\s*(.*?)(?=PIN|NIK|BAGIAN|ALAMAT|ALAMAT|$)', caseSensitive: false, dotAll: true),
      'NIK': RegExp(r'NIK\s*:\s*(.*?)(?=PIN|NAMA|BAGIAN|ALAMAT|ALAMAT|$)', caseSensitive: false, dotAll: true),
      'Bagian': RegExp(r'BAGIAN\s*:\s*(.*?)(?=PIN|NAMA|NIK|ALAMAT|ALAMAT|$)', caseSensitive: false, dotAll: true),
    };

    final info = <String, String>{};
    bool foundAny = false;

    patterns.forEach((key, regex) {
      final match = regex.firstMatch(raw);
      if (match != null) {
        var val = match.group(1)?.trim() ?? '';
        val = val.replaceAll(RegExp(r'[|,\r\n]+$'), '').trim();
        if (val.isNotEmpty) {
          info[key] = val;
          foundAny = true;
        }
      }
    });

    if (foundAny) {
      final pin = info['PIN'] ?? '';
      final nik = info['NIK'] ?? '';
      final nama = info['Nama'] ?? '';
      final bagian = info['Bagian'] ?? '';

      final parts = <String>[];
      if (nik.isNotEmpty) {
        parts.add('NIK: $nik');
      } else if (pin.isNotEmpty) {
        parts.add('PIN: $pin');
      }

      if (parts.isNotEmpty) {
        if (nama.isNotEmpty) parts.add('Nama: $nama');
        if (bagian.isNotEmpty) parts.add('Bagian: $bagian');
        return parts.join(' | ');
      }
    }
  } catch (e) {
    print('[Scanner] Error parsing barcode: $e');
  }

  return raw.replaceAll(RegExp(r'[\r\n\t]+'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
}

void main() {
  final input = "PIN:194024NAMA:ALIFATUN NURIYAHNIK:3321056604080002BAGIAN:Borong One ManALAMAT:KLITIH RT 04 RW 02 KARANGTENGAH DEMAK";
  print(_extractBarcodeInfo(input));
}