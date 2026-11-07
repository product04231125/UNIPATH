import '../api/academic_guidance_models.dart';
import '../api/student_api.dart';
import '../api/student_api_models.dart';

class AiRecordOption {
  const AiRecordOption({
    required this.kind,
    required this.id,
    required this.version,
    required this.title,
  });
  final String kind, id, title;
  final int version;
  String get key => '$kind/$id';
  String get kindLabel => switch (kind) {
    'course' => '수강',
    'activity' => '활동',
    'experience' => '경험',
    'credential' => '자격',
    'achievement' => '성과',
    _ => '기록',
  };
  GuidanceRecordSelection get selection => GuidanceRecordSelection(
    kind: kind,
    recordId: id,
    expectedVersion: version,
  );
  Map<String, Object?> toJson() => {
    'kind': kind,
    'id': id,
    'version': version,
    'title': title,
  };
  factory AiRecordOption.fromJson(Map<String, dynamic> value) => AiRecordOption(
    kind: value['kind'] as String,
    id: value['id'] as String,
    version: value['version'] as int,
    title: value['title'] as String,
  );
}

/// Reads only owner-checked server records; no PDFs or device-local fixtures.
Future<List<AiRecordOption>> loadAiRecords(
  StudentApi api, {
  bool includeCourses = true,
}) async {
  final resources = <String, StudentResource<StudentPayload>>{
    if (includeCourses) 'course': StudentResources.courseRecords,
    'activity': StudentResources.activityRecords,
    'experience': StudentResources.experienceRecords,
    'credential': StudentResources.credentialRecords,
    'achievement': StudentResources.achievementRecords,
  };
  final records = <AiRecordOption>[];
  for (final entry in resources.entries) {
    String? cursor;
    final cursors = <String>{};
    final identifiers = <String>{};
    do {
      final page = await api.list(entry.value, cursor: cursor);
      for (final record in page.items) {
        if (!identifiers.add(record.id))
          throw const FormatException('Repeated record');
        final json = record.data.toJson();
        records.add(
          AiRecordOption(
            kind: entry.key,
            id: record.id,
            version: record.version,
            title:
                (json['title'] ?? json['course_name'] ?? '이름 확인 필요') as String,
          ),
        );
      }
      cursor = page.nextCursor;
      if (cursor != null && !cursors.add(cursor))
        throw const FormatException('Repeated record cursor');
    } while (cursor != null);
  }
  return List.unmodifiable(records);
}
