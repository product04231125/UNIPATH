/// Student menu order: everyday pages (홈·일정·학사) first, then the career
/// flow 자료 → 준비 → 채용공고 분석 → 자기소개서·포트폴리오.
abstract final class StudentPages {
  static const home = 0;
  static const schedule = 1;
  static const academics = 2;

  /// 내 자료: 활동·자격증 기록과 파일 자료.
  static const materials = 3;

  /// 준비: 활동 추천 · 자격증 추천 · 시험 일정.
  static const prepare = 4;
  static const jobs = 5;
  static const writing = 6;

  static const labels = ['홈', '일정', '학사', '자료', '준비', '채용공고 분석', '자기소개서·포트폴리오'];
}
