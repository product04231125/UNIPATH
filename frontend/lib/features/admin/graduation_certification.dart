/// Local certification-requirement draft. Not a rule-programs DTO.
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
  });
  final String id;
  String label;
  GraduationCertificationKind kind;
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
  }) : items = items ?? [],
       groups = groups ?? [],
       exemptions = exemptions ?? [];

  final String id;
  String label;
  GraduationCertificationChoice choice;
  int pickCount;
  final List<GraduationCertificationItem> items;
  final List<GraduationCertificationGroup> groups;
  final List<String> exemptions;
}

class GraduationCertificationDraft {
  GraduationCertificationDraft({
    required this.departmentId,
    List<GraduationCertificationGroup>? groups,
  }) : groups = groups ?? [];

  String departmentId;
  final List<GraduationCertificationGroup> groups;

  static String newId([String prefix = 'cert']) =>
      '$prefix-${DateTime.now().microsecondsSinceEpoch}';
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
