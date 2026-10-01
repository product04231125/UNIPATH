/// Temporary, local-only display data used until the records API contract is
/// available. This is not an API model or school-authoritative record.
class RecordMockEntry {
  const RecordMockEntry({
    required this.title,
    required this.detail,
    required this.status,
  });

  final String title;
  final String detail;
  final String status;
}
