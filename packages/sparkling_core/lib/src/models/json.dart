/// Tolerant JSON parsing helpers shared by the hand-written models.
library;

typedef Json = Map<String, dynamic>;

Json asJson(dynamic v) =>
    v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

Json? asJsonOrNull(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : null;

List<Json> asJsonList(dynamic v) => v is List
    ? v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
    : const [];

List<String> asStringList(dynamic v) =>
    v is List ? v.map((e) => e.toString()).toList() : const [];

String str(dynamic v, [String fallback = '']) =>
    v == null ? fallback : v.toString();

String? strOrNull(dynamic v) => v?.toString();

int intOf(dynamic v, [int fallback = 0]) {
  if (v is int) return v;
  if (v is double) return v.round();
  if (v is String) {
    return int.tryParse(v) ?? double.tryParse(v)?.round() ?? fallback;
  }
  return fallback;
}

int? intOrNull(dynamic v) => v == null ? null : intOf(v);

double dbl(dynamic v, [double fallback = 0]) {
  if (v is double) return v;
  if (v is int) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? fallback;
  return fallback;
}

double? dblOrNull(dynamic v) => v == null ? null : dbl(v);

bool boolOf(dynamic v, [bool fallback = false]) {
  if (v is bool) return v;
  if (v is String) return v == 'true' || v == 't' || v == '1';
  if (v is num) return v != 0;
  return fallback;
}

DateTime? dtOrNull(dynamic v) {
  if (v == null) return null;
  if (v is DateTime) return v;
  return DateTime.tryParse(v.toString());
}

DateTime dt(dynamic v) =>
    dtOrNull(v) ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

/// ISO-8601 UTC string or null.
String? iso(DateTime? d) => d?.toUtc().toIso8601String();

/// `yyyy-MM-dd` or null.
String? isoDate(DateTime? d) {
  if (d == null) return null;
  final y = d.year.toString().padLeft(4, '0');
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '$y-$m-$day';
}

/// Removes null values so `toJson` output matches what the API expects.
Json compact(Json json) =>
    Map.fromEntries(json.entries.where((e) => e.value != null));
