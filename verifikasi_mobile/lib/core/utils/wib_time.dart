class WibTime {
  static const Duration offset = Duration(hours: 7);

  static DateTime now() => DateTime.now().toUtc().add(offset);

  static DateTime? parse(String? raw) {
    final value = raw?.trim();
    if (value == null || value.isEmpty || value == '-') return null;

    final normalized = value.replaceFirst(' ', 'T');

    try {
      if (_hasExplicitTimezone(normalized)) {
        return DateTime.parse(normalized).toUtc();
      }

      final parsed = DateTime.parse(normalized);
      return DateTime.utc(
        parsed.year,
        parsed.month,
        parsed.day,
        parsed.hour,
        parsed.minute,
        parsed.second,
        parsed.millisecond,
        parsed.microsecond,
      ).subtract(offset);
    } catch (_) {
      return null;
    }
  }

  static DateTime? toWib(String? raw) {
    final parsed = parse(raw);
    return parsed?.toUtc().add(offset);
  }

  static String formatTime(String? raw, {bool withSeconds = false}) {
    final wib = toWib(raw);
    if (wib == null) return '-';

    final h = wib.hour.toString().padLeft(2, '0');
    final m = wib.minute.toString().padLeft(2, '0');
    if (!withSeconds) return '$h:$m';

    final s = wib.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  static bool _hasExplicitTimezone(String value) {
    return value.endsWith('Z') ||
        RegExp(r'[+-]\d{2}:\d{2}$').hasMatch(value) ||
        RegExp(r'[+-]\d{4}$').hasMatch(value);
  }
}
