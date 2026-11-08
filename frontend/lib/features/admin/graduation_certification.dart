import '../records/personal_record_repository.dart';

/// Editor model; the academic workspace adapter owns its wire representation.
enum GraduationCertificationChoice { all, pickOne, pickN }

enum GraduationCertificationKind {
  text,
  certificate,
  volunteer,
  credits,
  grade,
  document,
  exemption,
}

class GraduationCertificationItem {
  GraduationCertificationItem({
    required this.id,
    this.label = '',
    this.kind = GraduationCertificationKind.text,
    this.scope,
  });
  final String id;
  String label;
  GraduationCertificationKind kind;
  Map<String, dynamic>? scope;
}

class GraduationCertificationGroup {
  GraduationCertificationGroup({
    required this.id,
    this.label = '',
    this.choice = GraduationCertificationChoice.all,
    this.pickCount = 1,
    List<GraduationCertificationItem>? items,
    List<GraduationCertificationGroup>? groups,
    List<String>? exemptions,
    this.scope,
  }) : items = items ?? [],
       groups = groups ?? [],
       exemptions = exemptions ?? [];

  final String id;
  String label;
  GraduationCertificationChoice choice;

  /// Null when 택 N was cleared. Zero and oversized counts stay as typed.
  int? pickCount;
  final List<GraduationCertificationItem> items;
  final List<GraduationCertificationGroup> groups;
  final List<String> exemptions;
  Map<String, dynamic>? scope;
}

class GraduationCertificationDraft {
  GraduationCertificationDraft({
    required this.departmentId,
    List<GraduationCertificationGroup>? groups,
  }) : groups = groups ?? [];

  String departmentId;
  final List<GraduationCertificationGroup> groups;

  static String newId([String prefix = 'cert']) => PersonalRecord.newId();
}

GraduationCertificationDraft copyCertificationDraft(
  GraduationCertificationDraft source,
) {
  GraduationCertificationGroup copyGroup(GraduationCertificationGroup group) =>
      GraduationCertificationGroup(
        id: group.id,
        label: group.label,
        choice: group.choice,
        scope: group.scope,
        pickCount: group.pickCount,
        items: [
          for (final item in group.items)
            GraduationCertificationItem(
              id: item.id,
              label: item.label,
              kind: item.kind,
              scope: item.scope,
            ),
        ],
        groups: group.groups.map(copyGroup).toList(),
        exemptions: [...group.exemptions],
      );
  return GraduationCertificationDraft(
    departmentId: source.departmentId,
    groups: source.groups.map(copyGroup).toList(),
  );
}

/// Visible when 택 N is blank, below 1, or greater than the criteria lines.
/// Does not decide whether preview can open.
String? certificationPickCountError(String raw, int itemCount) {
  final text = raw.trim();
  if (text.isEmpty) return '택하는 개수를 입력하세요.';
  final value = int.tryParse(text);
  if (value == null || value < 1) {
    return '택하는 개수는 1 이상의 숫자로 입력하세요.';
  }
  if (value > itemCount) {
    return '기준은 $itemCount개입니다. 택하는 개수는 기준 수를 넘지 않게 입력하세요.';
  }
  return null;
}

String certificationChoiceLabel(GraduationCertificationChoice choice) =>
    switch (choice) {
      GraduationCertificationChoice.all => '모두',
      GraduationCertificationChoice.pickOne => '택 1',
      GraduationCertificationChoice.pickN => '택 N',
    };

String certificationKindLabel(GraduationCertificationKind kind) =>
    switch (kind) {
      GraduationCertificationKind.text => '문장',
      GraduationCertificationKind.certificate => '자격',
      GraduationCertificationKind.volunteer => '봉사시간',
      GraduationCertificationKind.credits => '학점',
      GraduationCertificationKind.grade => '성적',
      GraduationCertificationKind.document => '서류',
      GraduationCertificationKind.exemption => '면제',
    };
