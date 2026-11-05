/// Client presentation of the existing free-text `term` contract.
/// Unrecognized text is preserved; a missing year is never inferred.
class CourseTerm {
  const CourseTerm(this.year, this.semester);

  factory CourseTerm.parse(String raw) {
    final value = raw.trim();
    final named = RegExp(r'^([1-9]\d{3})(?:년|학년도)\s+(.+)$').firstMatch(value);
    if (named != null) return CourseTerm(named[1]!, named[2]!);
    final numeric = RegExp(r'^([1-9]\d{3})[-/]([12])(?:학기)?$')
        .firstMatch(value);
    if (numeric != null) return CourseTerm(numeric[1]!, '${numeric[2]}학기');
    return CourseTerm('', raw);
  }

  final String year;
  final String semester;
  static const unspecified = 'unspecified';
  String get yearFilter => year.isEmpty ? unspecified : year;
  String get label => year.isEmpty ? '연도 미지정 · $semester' : '$year년 $semester';

  static String encode(String year, String semester) => year.trim().isEmpty
      ? semester.trim()
      : '${year.trim()}년 ${semester.trim()}';

  static String? validateYear(String? value, {required bool required}) {
    final year = (value ?? '').trim();
    if (year.isEmpty && !required) return null;
    if (!RegExp(r'^[1-9]\d{3}$').hasMatch(year)) {
      return '수강 연도를 네 자리 숫자로 입력하세요.';
    }
    return null;
  }
}
