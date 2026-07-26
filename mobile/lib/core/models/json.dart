/// Defensive JSON coercion helpers.
///
/// Postgres/PostgREST payloads arrive as `Map<String, dynamic>`; the RPCs in
/// `docs/BACKEND_API.md` return partial projections (a closeup's `item` has no
/// counters, a sibling has no description). Every model therefore parses
/// through these helpers so a missing key is a default, never a crash.
library;

/// Casts an arbitrary decoded value to a JSON object, or `{}`.
Map<String, dynamic> asMap(Object? v) {
  if (v is Map<String, dynamic>) return v;
  if (v is Map) {
    return v.map((key, value) => MapEntry(key.toString(), value));
  }
  return const <String, dynamic>{};
}

/// Casts to a list of JSON objects, dropping anything that is not an object.
List<Map<String, dynamic>> asMapList(Object? v) {
  if (v is! List) return const <Map<String, dynamic>>[];
  return <Map<String, dynamic>>[
    for (final e in v)
      if (e is Map) asMap(e),
  ];
}

/// Casts to a list of strings, coercing scalars via `toString()`.
List<String> asStringList(Object? v) {
  if (v is! List) return const <String>[];
  return <String>[
    for (final e in v)
      if (e != null) e.toString(),
  ];
}

/// A string, or `null` when absent/empty.
String? asStringOrNull(Object? v) {
  if (v == null) return null;
  final s = v is String ? v : v.toString();
  return s.isEmpty ? null : s;
}

/// A string, falling back to [fallback].
String asString(Object? v, [String fallback = '']) =>
    asStringOrNull(v) ?? fallback;

/// An int, tolerating numeric strings and doubles.
int asInt(Object? v, [int fallback = 0]) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? fallback;
  return fallback;
}

/// A nullable int.
int? asIntOrNull(Object? v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v);
  return null;
}

/// A nullable double.
double? asDoubleOrNull(Object? v) {
  if (v == null) return null;
  if (v is double) return v;
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v);
  return null;
}

/// A double, falling back to [fallback].
double asDouble(Object? v, [double fallback = 0]) =>
    asDoubleOrNull(v) ?? fallback;

/// A bool, tolerating `'true'` / `1`.
bool asBool(Object? v, {bool fallback = false}) {
  if (v is bool) return v;
  if (v is num) return v != 0;
  if (v is String) {
    final s = v.toLowerCase();
    if (s == 'true' || s == 't' || s == '1') return true;
    if (s == 'false' || s == 'f' || s == '0') return false;
  }
  return fallback;
}

/// A UTC [DateTime], or `null`.
DateTime? asDateOrNull(Object? v) {
  if (v == null) return null;
  if (v is DateTime) return v;
  final s = v is String ? v : v.toString();
  return DateTime.tryParse(s)?.toLocal();
}

/// A [DateTime], falling back to the epoch so list sorts never throw.
DateTime asDate(Object? v) =>
    asDateOrNull(v) ?? DateTime.fromMillisecondsSinceEpoch(0);

/// ISO-8601 encoding used for every timestamp we send back.
String? isoOrNull(DateTime? v) => v?.toUtc().toIso8601String();
