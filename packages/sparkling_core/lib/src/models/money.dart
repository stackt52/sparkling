import 'package:intl/intl.dart';

/// Money and number formatting for South African Rand and loyalty points.
///
/// All API amounts are integer cents in ZAR.
abstract final class Money {
  /// Unicode minus used for negative display values ("−800").
  static const String minus = '−';

  /// `19800` → `"R 198.00"`, `385000` → `"R 3 850.00"`.
  static String formatZar(int cents, {bool showCents = true}) {
    final negative = cents < 0;
    final abs = cents.abs();
    final rand = abs ~/ 100;
    final c = abs % 100;
    final body = showCents
        ? '${group(rand)}.${c.toString().padLeft(2, '0')}'
        : group(rand);
    return '${negative ? minus : ''}R $body';
  }

  /// `12000` → `"R120"` (used in "From R120" copy).
  static String formatZarCompact(int cents) {
    final rand = cents ~/ 100;
    return 'R${group(rand)}';
  }

  /// `1450` → `"1 450"`.
  static String formatPoints(int points) =>
      '${points < 0 ? minus : ''}${group(points.abs())}';

  /// `1450` → `"1 450 pts"`.
  static String formatPointsLabel(int points) => '${formatPoints(points)} pts';

  /// `20` → `"+20"`, `-800` → `"−800"`.
  static String formatDelta(int delta) =>
      delta >= 0 ? '+${group(delta)}' : '$minus${group(delta.abs())}';

  /// Percentage: `12.5` → `"+12.5%"`.
  static String formatTrendPct(double pct) {
    final s = pct.abs() % 1 == 0
        ? pct.abs().toStringAsFixed(0)
        : pct.abs().toStringAsFixed(1);
    return '${pct >= 0 ? '+' : minus}$s%';
  }

  /// Groups thousands with a regular space (SA convention): `3850` → `"3 850"`.
  static String group(int n) {
    final s = n.abs().toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(' ');
      buf.write(s[i]);
    }
    return '${n < 0 ? '-' : ''}$buf';
  }

  /// Parses `"R 198.00"` / `"198,00"` / `"198"` back to cents.
  static int? parseZar(String input) {
    final cleaned = input
        .replaceAll(RegExp(r'[R\s  ]'), '')
        .replaceAll(',', '.');
    final value = double.tryParse(cleaned);
    if (value == null) return null;
    return (value * 100).round();
  }
}

/// Date/time formatting for the apps (Africa/Johannesburg is the outlet
/// timezone; devices are assumed to be local to it).
abstract final class SparklingDates {
  static final DateFormat _hhmm = DateFormat('HH:mm');
  static final DateFormat _hhmmss = DateFormat('HH:mm:ss');
  static final DateFormat _dayMonth = DateFormat('d MMM');
  static final DateFormat _weekday = DateFormat('EEE');
  static final DateFormat _long = DateFormat('EEE d MMM, HH:mm');
  static final DateFormat _isoDay = DateFormat('yyyy-MM-dd');

  /// `"09:41"`
  static String hhmm(DateTime d) => _hhmm.format(d.toLocal());

  /// `"09:41:07"`
  static String hhmmss(DateTime d) => _hhmmss.format(d.toLocal());

  /// `"28 Aug"`
  static String dayMonth(DateTime d) => _dayMonth.format(d.toLocal());

  /// `"Mon"`
  static String weekday(DateTime d) => _weekday.format(d.toLocal());

  /// `"Tue 8 Sep, 10:30"`
  static String long(DateTime d) => _long.format(d.toLocal());

  /// `"2026-09-08"`
  static String isoDay(DateTime d) => _isoDay.format(d.toLocal());

  /// `"Today 10:30"`, `"Tomorrow 09:00"`, else [long].
  static String relativeSlot(DateTime d, {DateTime? now}) {
    final n = (now ?? DateTime.now()).toLocal();
    final l = d.toLocal();
    final today = DateTime(n.year, n.month, n.day);
    final day = DateTime(l.year, l.month, l.day);
    final diff = day.difference(today).inDays;
    if (diff == 0) return 'Today ${hhmm(l)}';
    if (diff == 1) return 'Tomorrow ${hhmm(l)}';
    if (diff == -1) return 'Yesterday ${hhmm(l)}';
    return long(l);
  }

  /// `"2 min ago"`, `"just now"`, `"3 h ago"`.
  static String ago(DateTime d, {DateTime? now}) {
    final diff = (now ?? DateTime.now()).difference(d);
    if (diff.inSeconds < 45) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} h ago';
    return '${diff.inDays} d ago';
  }

  /// `"±10:25"` ETA style.
  static String eta(DateTime d) => '±${hhmm(d)}';
}
