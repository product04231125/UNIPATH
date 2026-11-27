/// 1~4학년, 졸업예정, 졸업: the student's stage in the 학업 프로필, and what the
/// 공고 찾기·활동 추천·자격증 추천 requests send (`academic_stage`).
enum AcademicStage {
  year1('1학년'),
  year2('2학년'),
  year3('3학년'),
  year4('4학년'),
  graduating('졸업예정'),
  graduate('졸업');

  const AcademicStage(this.label);
  final String label;

  /// The stage of a study year, 1~4.
  static AcademicStage ofYear(int year) => values[year.clamp(1, 4) - 1];

  /// The stage stored or sent under [name]; null for anything else.
  static AcademicStage? fromName(Object? name) =>
      values.where((stage) => stage.name == name).firstOrNull;
}
