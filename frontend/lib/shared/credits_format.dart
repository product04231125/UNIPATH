/// Display-only credit amount. Storage and API values stay unchanged.
String formatCreditsLabel(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return '';
  final value = num.tryParse(trimmed);
  if (value == null || !value.isFinite) return '$trimmed학점';
  final formatted = value == value.roundToDouble()
      ? '${value.round()}'
      : value.toString();
  return '$formatted학점';
}
