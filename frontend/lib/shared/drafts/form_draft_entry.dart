/// One client-only form draft slot. Not a server DTO or formal record.
class FormDraftEntry {
  const FormDraftEntry({
    required this.id,
    required this.savedAt,
    required this.summary,
    required this.payload,
  });

  final String id;
  final DateTime savedAt;
  final String summary;
  final Map<String, Object?> payload;

  Map<String, Object?> toJson() => {
    'id': id,
    'savedAt': savedAt.toUtc().toIso8601String(),
    'summary': summary,
    'payload': payload,
  };

  factory FormDraftEntry.fromJson(Map<String, Object?> json) {
    final rawPayload = json['payload'];
    return FormDraftEntry(
      id: json['id'] as String? ?? '',
      savedAt:
          DateTime.tryParse(json['savedAt'] as String? ?? '')?.toLocal() ??
          DateTime.fromMillisecondsSinceEpoch(0),
      summary: (json['summary'] as String?)?.trim().isNotEmpty == true
          ? (json['summary'] as String).trim()
          : '(내용 없음)',
      payload: rawPayload is Map
          ? Map<String, Object?>.from(rawPayload)
          : const {},
    );
  }
}
