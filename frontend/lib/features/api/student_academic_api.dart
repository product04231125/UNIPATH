import 'dart:convert';

import '../auth/auth_api.dart';
import 'student_api.dart';

Map<String, dynamic> academicMap(Object? value) =>
    Map<String, dynamic>.from(value as Map);
List<Map<String, dynamic>> academicMaps(Object? value) =>
    (value as List? ?? []).map(academicMap).toList();

class AcademicOption {
  AcademicOption(Map<String, dynamic> json)
    : id = json['id'] as String,
      name = json['name'] as String,
      revision = json['revision'] as int?;
  final String id, name;
  final int? revision;
  String get label => revision == null ? name : '$name · $revision판';
}

class AcademicStudentOptions {
  AcademicStudentOptions(Map<String, dynamic> json)
    : institutionId = json['institution_id'] as String,
      departments = academicMaps(json['departments'])
          .map(AcademicOption.new)
          .toList(),
      tracks = academicMaps(json['tracks']).map(AcademicOption.new).toList(),
      curricula = academicMaps(json['curricula'])
          .map(AcademicOption.new)
          .toList();
  final String institutionId;
  final List<AcademicOption> departments, tracks, curricula;
}

class AcademicStudentCourse {
  AcademicStudentCourse(Map<String, dynamic> json)
    : id = json['id'] as String,
      name = json['course_name'] as String,
      code = json['course_code'] as String,
      classificationId = json['classification_node_id'] as String,
      classificationLabel = json['classification_label'] as String? ?? '',
      requirement = json['requirement'] as String,
      credits = json['recognized_credits']?.toString() ?? '',
      gradingBasis = json['grading_basis'] as String? ?? 'unspecified';
  final String id,
      name,
      code,
      classificationId,
      classificationLabel,
      requirement,
      credits,
      gradingBasis;
  String get label =>
      '$name · $code · $classificationLabel · ${gradingBasis == 'pass_fail' ? 'P/F · ' : ''}${credits.isEmpty ? '학점 미확인' : '$credits학점'} · ${requirement == 'required'
          ? '필수'
          : requirement == 'elective'
          ? '선택'
          : '필수 여부 미지정'}';
}

class AcademicStudentContext {
  AcademicStudentContext(Map<String, dynamic> json)
    : id = json['id'] as String,
      institutionId = json['institution_id'] as String,
      departmentId = json['department_id'] as String,
      trackId = json['track_id'] as String,
      curriculumId = json['curriculum_revision_id'] as String,
      year = json['admission_year'] as int,
      primary = json['primary'] as bool,
      department = json['department_name'] as String,
      track = json['track_name'] as String,
      curriculum = json['curriculum_name'] as String,
      courses = academicMaps(json['courses'])
          .map(AcademicStudentCourse.new)
          .toList();
  final String id,
      institutionId,
      departmentId,
      trackId,
      curriculumId,
      department,
      track,
      curriculum;
  final int year;
  final bool primary;
  final List<AcademicStudentCourse> courses;
  String get label => '$department · $track · $year';
  Map<String, Object?> toInput() => {
    'id': id,
    'department_id': departmentId,
    'track_id': trackId,
    'curriculum_revision_id': curriculumId,
    'admission_year': year,
    'primary': primary,
  };
}

class AcademicStudentWorkspace {
  AcademicStudentWorkspace(Map<String, dynamic> json)
    : ownerId = json['owner_id'] as String,
      version = json['version'] as int,
      institutionId = json['institution_id'] as String?,
      contexts = academicMaps(json['contexts'])
          .map(AcademicStudentContext.new)
          .toList(),
      issues = List<String>.from(json['issues'] as List);
  final String ownerId;
  final String? institutionId;
  final int version;
  final List<AcademicStudentContext> contexts;
  final List<String> issues;
}

class AcademicStudentRecord {
  AcademicStudentRecord({
    required this.id,
    required this.kind,
    required this.title,
    required this.version,
    this.available = true,
    this.currentVersion,
    this.credits,
    this.completion,
  });
  factory AcademicStudentRecord.fromSnapshot(Map<String, dynamic> j) =>
      AcademicStudentRecord(
        id: j['record_id'] as String,
        kind: j['kind'] as String,
        title: j['title'] as String,
        version: j['version'] as int,
        available: j['available'] as bool,
        currentVersion: j['current_version'] as int?,
      );
  final String id, kind, title;
  final int version;
  final bool available;
  final int? currentVersion;
  final String? credits, completion;
  String get identity => '$kind:$id';
  Map<String, Object?> toReference() => {
    'kind': kind,
    'record_id': id,
    'expected_version': version,
  };
}

class AcademicStudentResponse {
  AcademicStudentResponse(Map<String, dynamic> j)
    : itemId = j['item_id'] as String,
      value = j['value'] as bool?,
      previousValue = j['previous_value'] as bool?,
      version = j['version'] as int,
      stale = j['stale'] as bool,
      records = academicMaps(j['records'])
          .map(AcademicStudentRecord.fromSnapshot)
          .toList();
  final String itemId;
  final bool? value, previousValue;
  final int version;
  final bool stale;
  final List<AcademicStudentRecord> records;
}

class AcademicStudentItem {
  AcademicStudentItem(Map<String, dynamic> j)
    : id = j['id'] as String,
      text = (j['text'] ?? j['label']) as String;
  final String id, text;
}

class AcademicStudentGroup {
  AcademicStudentGroup(Map<String, dynamic> j)
    : id = j['id'] as String,
      label = j['label'] as String,
      choice = j['choice'] as String,
      count = j['pick_count'] as int?,
      exemptions = List<String>.from(j['exemptions'] as List? ?? []),
      items = academicMaps(j['items']).map(AcademicStudentItem.new).toList(),
      groups = academicMaps(j['groups']).map(AcademicStudentGroup.new).toList();
  final String id, label, choice;
  final int? count;
  final List<String> exemptions;
  final List<AcademicStudentItem> items;
  final List<AcademicStudentGroup> groups;
  String get choiceLabel => choice == 'all'
      ? '모두'
      : choice == 'pickOne'
      ? '택1'
      : '택${count ?? '?'}';
}

class AcademicStudentExplanation {
  AcademicStudentExplanation(Map<String, dynamic> j)
    : title = j['title'] as String,
      columns = List<String>.from(j['columns'] as List),
      rows = (j['rows'] as List)
          .map((r) => List<String>.from(r as List))
          .toList();
  final String title;
  final List<String> columns;
  final List<List<String>> rows;
}

class AcademicStudentDocument {
  AcademicStudentDocument(Map<String, dynamic> j)
    : id = j['id'] as String,
      name = j['name'] as String,
      kind = j['kind'] as String,
      revision = j['revision'] as int,
      status = j['status'] as String,
      usable = j['usable'] as bool? ?? true,
      effectiveFrom = j['effective_from'] as String?,
      effectiveTo = j['effective_to'] as String?,
      nodeContexts = {
        for (final e in (j['node_contexts'] as Map? ?? {}).entries)
          e.key as String: List<String>.from(e.value as List),
      },
      content = academicMap(j['content']),
      contextIds = List<String>.from(j['context_ids'] as List),
      responses = academicMaps(j['responses'])
          .map(AcademicStudentResponse.new)
          .toList(),
      groupResults = Map<String, String>.from(j['group_results'] as Map? ?? {});
  final String id, name, kind, status;
  final bool usable;
  final String? effectiveFrom, effectiveTo;
  final Map<String, List<String>> nodeContexts;
  final int revision;
  final Map<String, dynamic> content;
  final List<String> contextIds;
  final List<AcademicStudentResponse> responses;
  final Map<String, String> groupResults;
  List<AcademicStudentItem> get lines =>
      academicMaps(content['lines']).map(AcademicStudentItem.new).toList();
  List<AcademicStudentGroup> get groups =>
      academicMaps(content['groups']).map(AcademicStudentGroup.new).toList();
  List<AcademicStudentExplanation> get tables =>
      academicMaps(content['tables'])
          .map(AcademicStudentExplanation.new)
          .toList();
  AcademicStudentResponse? response(String id) =>
      responses.where((r) => r.itemId == id).firstOrNull;
}

class AcademicStudentRequirements {
  AcademicStudentRequirements(Map<String, dynamic> j)
    : ownerId = j['owner_id'] as String,
      version = j['workspace_version'] as int,
      activationId = j['activation_id'] as String?,
      issues = List<String>.from(j['issues'] as List),
      documents = academicMaps(j['documents'])
          .map(AcademicStudentDocument.new)
          .toList();
  final String ownerId;
  final String? activationId;
  final int version;
  final List<String> issues;
  final List<AcademicStudentDocument> documents;
}

class AcademicStudentChange {
  AcademicStudentChange(Map<String, dynamic> j)
    : name = j['name'] as String,
      kind = j['kind'] as String,
      detail = j['detail'] as String;
  final String name, kind, detail;
}

class AcademicStudentPreview {
  AcademicStudentPreview(Map<String, dynamic> j)
    : ownerId = j['owner_id'] as String,
      version = j['workspace_version'] as int,
      digest = j['digest'] as String,
      issues = List<String>.from(j['issues'] as List),
      documents = academicMaps(j['documents'])
          .map(AcademicStudentDocument.new)
          .toList(),
      changes = academicMaps(j['changes'])
          .map(AcademicStudentChange.new)
          .toList(),
      curriculumUpdates = academicMaps(j['curriculum_updates'])
          .map(
            (update) =>
                '${update['name']} · ${update['revision']}판이 게시됐습니다. 학업 기준 설정에서 비교·선택하세요.',
          )
          .toList();
  final String ownerId, digest;
  final int version;
  final List<String> issues;
  final List<AcademicStudentDocument> documents;
  final List<AcademicStudentChange> changes;
  final List<String> curriculumUpdates;
}

class AcademicStudentCourseLink {
  AcademicStudentCourseLink(Map<String, dynamic> j)
    : recordId = j['course_record_id'] as String,
      contextId = j['context_id'] as String,
      entryId = j['entry_id'] as String,
      result = j['result'] as String,
      version = j['version'] as int,
      earned = j['earned_credits']?.toString(),
      included = j['included'] as bool;
  final String recordId, contextId, entryId, result;
  final int version;
  final String? earned;
  final bool included;
}

class AcademicStudentEvidence {
  AcademicStudentEvidence(Map<String, dynamic> j)
    : title = j['title'] as String,
      state = j['state'] as String,
      reason = j['reason'] as String,
      credits = j['credits']?.toString();
  final String title, state, reason;
  final String? credits;
}

class AcademicStudentCreditCell {
  AcademicStudentCreditCell(Map<String, dynamic> j)
    : rowId = j['row_id'] as String,
      headerId = j['header_id'] as String,
      target = j['target']?.toString(),
      earned = j['earned']?.toString(),
      remaining = j['remaining']?.toString(),
      status = j['status'] as String,
      issues = List<String>.from(j['issues'] as List? ?? []),
      evidence = academicMaps(j['evidence'])
          .map(AcademicStudentEvidence.new)
          .toList();
  final String rowId, headerId, status;
  final String? target, earned, remaining;
  final List<AcademicStudentEvidence> evidence;
  final List<String> issues;
}

class AcademicStudentHistoryItem {
  AcademicStudentHistoryItem(Map<String, dynamic> j)
    : id = j['id'] as String,
      createdAt = DateTime.parse(j['created_at'] as String),
      active = j['active'] as bool,
      count = j['document_count'] as int;
  final String id;
  final DateTime createdAt;
  final bool active;
  final int count;
}

class AcademicStudentProgress {
  AcademicStudentProgress(Map<String, dynamic> j)
    : ownerId = j['owner_id'] as String,
      activationId = j['activation_id'] as String?,
      issues = List<String>.from(j['issues'] as List),
      links = academicMaps(j['links'])
          .map(AcademicStudentCourseLink.new)
          .toList(),
      tables = {
        for (final t in academicMaps(j['tables']))
          t['requirement_revision_id'] as String: academicMaps(t['cells'])
              .map(AcademicStudentCreditCell.new)
              .toList(),
      };
  final String ownerId;
  final String? activationId;
  final List<String> issues;
  final List<AcademicStudentCourseLink> links;
  final Map<String, List<AcademicStudentCreditCell>> tables;
}

class StudentAcademicApi {
  const StudentAcademicApi(this.gateway, this.ownerId);
  factory StudentAcademicApi.forOwner(AuthApi auth, String ownerId) =>
      StudentAcademicApi(auth.forOwner(ownerId), ownerId);
  factory StudentAcademicApi.fromStudent(StudentApi api) =>
      StudentAcademicApi(api.api, api.ownerId);
  final ApiGateway gateway;
  final String ownerId;
  Future<List<AcademicStudentHistoryItem>> history() async => academicMaps(
    owned(
      await gateway.request('GET', 'me/academic-requirements/history'),
    )['items'],
  ).map(AcademicStudentHistoryItem.new).toList();
  Future<AcademicStudentRequirements> historical(String id) async {
    final result = AcademicStudentRequirements(
      owned(
        await gateway.request('GET', 'me/academic-requirements/history/$id'),
      ),
    );
    if (result.activationId != id) {
      throw const FormatException('Academic history mismatch');
    }
    return result;
  }

  Map<String, dynamic> owned(Map<String, dynamic>? value) {
    if (value == null || value['owner_id'] != ownerId) {
      throw const FormatException('Student academic owner mismatch');
    }
    return value;
  }

  Future<AcademicStudentWorkspace> workspace() async =>
      AcademicStudentWorkspace(
        owned(await gateway.request('GET', 'me/academic-contexts')),
      );
  Future<AcademicStudentRequirements> requirements() async =>
      AcademicStudentRequirements(
        owned(await gateway.request('GET', 'me/academic-requirements')),
      );
  Future<AcademicStudentPreview> preview() async => AcademicStudentPreview(
    owned(await gateway.request('GET', 'me/academic-requirements/preview')),
  );
  Future<AcademicStudentProgress> progress() async => AcademicStudentProgress(
    owned(await gateway.request('GET', 'me/academic-credit-progress')),
  );
  Future<AcademicStudentOptions> options(String school) async {
    final result = AcademicStudentOptions(
      (await gateway.request(
        'GET',
        'catalog/academic/options?institution_id=${Uri.encodeQueryComponent(school)}',
      ))!,
    );
    if (result.institutionId != school) {
      throw const FormatException('School mismatch');
    }
    return result;
  }

  Future<List<AcademicStudentRecord>> records({
    bool onlyCourses = false,
  }) async {
    const resources = {
      'course': 'course-records',
      'activity': 'activity-records',
      'credential': 'credential-records',
      'experience': 'experience-records',
      'achievement': 'achievement-records',
    };
    final result = <AcademicStudentRecord>[];
    for (final entry in resources.entries.where(
      (e) => !onlyCourses || e.key == 'course',
    )) {
      String? cursor;
      final seen = <String>{};
      do {
        final query = Uri(queryParameters: {'limit': '100', 'cursor': ?cursor})
            .query;
        final page = (await gateway.request(
          'GET',
          'me/${entry.value}?$query',
        ))!;
        for (final r in academicMaps(page['items'])) {
          owned(r);
          result.add(
            AcademicStudentRecord(
              id: r['id'] as String,
              kind: entry.key,
              title: r['title'] as String,
              version: r['version'] as int,
              credits: r['credits']?.toString(),
              completion: r['completion'] as String?,
            ),
          );
        }
        cursor = page['next_cursor'] as String?;
        if (cursor != null && !seen.add(cursor)) {
          throw const FormatException('Repeated cursor');
        }
      } while (cursor != null);
    }
    return result;
  }

  Future<Map<String, dynamic>> write(
    String method,
    String path,
    Map<String, Object?> body,
  ) async {
    final result = owned(await gateway.request(method, path, body));
    if (path.endsWith('academic-contexts')) {
      final state = AcademicStudentWorkspace(result);
      if (state.version != (body['expected_version'] as int) + 1) {
        throw const FormatException('Academic workspace version mismatch');
      }
    } else if (path.endsWith('academic-link')) {
      final link = AcademicStudentCourseLink(result);
      if (link.recordId != path.split('/')[2] ||
          link.contextId != body['context_id'] ||
          link.entryId != body['entry_id']) {
        throw const FormatException('Academic course link mismatch');
      }
    } else {
      final state = AcademicStudentRequirements(result);
      if (path.contains('/responses/') &&
          state.activationId != body['activation_id']) {
        throw const FormatException('Academic activation mismatch');
      }
      if (state.activationId == null) {
        throw const FormatException('Missing academic activation');
      }
    }
    return result;
  }

  static Map<String, Object?> freeze(Map<String, Object?> value) =>
      Map<String, Object?>.from(jsonDecode(jsonEncode(value)) as Map);
}
