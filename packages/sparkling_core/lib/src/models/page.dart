import 'json.dart';

/// Cursor-paginated response (API-006): `{ data: [...], next_cursor }`.
class Page<T> {
  const Page({required this.items, this.nextCursor});

  final List<T> items;
  final String? nextCursor;

  bool get hasMore => nextCursor != null;
  bool get isEmpty => items.isEmpty;

  static Page<T> fromJson<T>(dynamic json, T Function(Json) fromItem) {
    if (json is List) {
      return Page(items: asJsonList(json).map(fromItem).toList());
    }
    final map = asJson(json);
    final raw = map['data'] ?? map['items'] ?? map['rows'] ?? const [];
    return Page(
      items: asJsonList(raw).map(fromItem).toList(),
      nextCursor: strOrNull(map['next_cursor']),
    );
  }

  Page<R> map<R>(R Function(T) f) =>
      Page(items: items.map(f).toList(), nextCursor: nextCursor);

  /// Appends the next page (for infinite lists).
  Page<T> append(Page<T> next) =>
      Page(items: [...items, ...next.items], nextCursor: next.nextCursor);
}
