import 'admin_models.dart';

class AdminField {
  const AdminField(
    this.key,
    this.label, {
    this.required = true,
    this.relation,
    this.options = const {},
    this.multiline = false,
  });
  final String key, label;
  final bool required, multiline;
  final AdminKind? relation;
  final Map<String, String> options;
}

/// Presentation groups only. Field keys, validators and repository contracts
/// remain unchanged, and every field is rendered once.
Map<String, List<AdminField>> adminFieldGroups(List<AdminField> fields) {
  final groups = <String, List<AdminField>>{};
  for (final field in fields) {
    final group = switch (field.key) {
      'institutionId' ||
      'departmentId' ||
      'curriculumId' ||
      'userId' ||
      'scopeType' => '적용 대상과 범위',
      'sourceUrl' ||
      'officialUrl' ||
      'documentType' ||
      'ruleId' ||
      'ruleSetId' => '출처와 연결',
      'effectiveFrom' || 'effectiveTo' => '적용 기간',
      'ruleType' ||
      'definition' ||
      'category' ||
      'required' ||
      'courseId' => '규칙과 이수 기준',
      'reason' || 'accountStatus' => '관리 설정',
      _ => '기본 정보',
    };
    (groups[group] ??= []).add(field);
  }
  return groups;
}

/// Isolated client mock schema; candidate fields, not OpenAPI types/enums.
List<AdminField> adminFields(AdminKind kind) => [
  const AdminField('name', '이름'),
  if ([
    AdminKind.department,
    AdminKind.course,
    AdminKind.ruleSet,
    AdminKind.rule,
    AdminKind.document,
    AdminKind.scope,
  ].contains(kind))
    const AdminField('institutionId', '학교', relation: AdminKind.institution),
  if (kind == AdminKind.institution) ...[
    const AdminField('countryCode', '국가 코드', required: false),
    const AdminField('officialUrl', '공식 사이트 HTTP(S)', required: false),
  ],
  if (kind == AdminKind.department || kind == AdminKind.course)
    const AdminField('code', '코드'),
  if (kind == AdminKind.curriculum) ...[
    const AdminField('departmentId', '학과', relation: AdminKind.department),
    const AdminField('year', '적용 연도'),
  ],
  if (kind == AdminKind.course) const AdminField('credits', '학점'),
  if (kind == AdminKind.curriculumCourse) ...[
    const AdminField('curriculumId', '교육과정', relation: AdminKind.curriculum),
    const AdminField('courseId', '과목', relation: AdminKind.course),
    const AdminField(
      'category',
      '이수구분',
      options: {'major': '전공', 'general': '교양', 'other': '기타'},
    ),
    const AdminField(
      'required',
      '필수 여부',
      options: {'true': '필수', 'false': '선택'},
    ),
  ],
  if (kind == AdminKind.ruleSet ||
      kind == AdminKind.rule ||
      kind == AdminKind.document ||
      kind == AdminKind.scope) ...[
    const AdminField(
      'departmentId',
      '학과',
      relation: AdminKind.department,
      required: false,
    ),
    const AdminField(
      'curriculumId',
      '교육과정',
      relation: AdminKind.curriculum,
      required: false,
    ),
  ],
  if (kind == AdminKind.rule) ...[
    const AdminField(
      'ruleSetId',
      '규칙 묶음 초안',
      relation: AdminKind.ruleSet,
      required: false,
    ),
    const AdminField(
      'ruleType',
      '규칙 종류',
      options: {
        'credits': '학점',
        'required_course': '필수과목',
        'volunteer': '봉사',
        'thesis': '논문·캡스톤',
        'certificate': '자격',
        'custom': '기타',
      },
    ),
    const AdminField('definition', '조건·대체 요건 설명', multiline: true),
    const AdminField('sourceUrl', '근거 HTTP(S) URL', required: false),
  ],
  if (kind == AdminKind.document) ...[
    const AdminField('sourceUrl', '원문 HTTP(S) URL'),
    const AdminField(
      'documentType',
      '문서 종류',
      options: {'academic': '학사 규정', 'graduation': '졸업요건', 'other': '기타 공식 문서'},
    ),
    const AdminField(
      'ruleId',
      '관련 규칙 버전',
      relation: AdminKind.rule,
      required: false,
    ),
  ],
  if (kind == AdminKind.ruleSet ||
      kind == AdminKind.rule ||
      kind == AdminKind.document) ...[
    const AdminField('effectiveFrom', '적용 시작일 YYYY-MM-DD', required: false),
    const AdminField('effectiveTo', '적용 종료일 YYYY-MM-DD', required: false),
  ],
  if (kind == AdminKind.scope) ...[
    const AdminField('userId', '사용자', relation: AdminKind.account),
    const AdminField(
      'scopeType',
      '관리 범위',
      options: {
        'institution': '학교 전체',
        'department': '학과',
        'curriculum': '교육과정',
      },
    ),
    const AdminField('reason', '부여·변경 사유', multiline: true),
  ],
  if (kind == AdminKind.account)
    const AdminField(
      'accountStatus',
      '계정 상태',
      options: {'active': '활성', 'suspended': '정지'},
    ),
];
