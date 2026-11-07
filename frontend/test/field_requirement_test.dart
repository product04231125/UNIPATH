import 'package:flutter_test/flutter_test.dart';
import 'package:university_path_frontend/shared/credits_format.dart';
import 'package:university_path_frontend/shared/widgets/field_requirement.dart';

void main() {
  test('fieldRequirementLabel uses Korean required and optional suffixes', () {
    expect(fieldRequirementLabel('이름', required: true), '이름 (필수)');
    expect(fieldRequirementLabel('메모', required: false), '메모 (선택)');
  });

  test('formatCreditsLabel drops trailing zeros and keeps the 학점 suffix', () {
    expect(formatCreditsLabel('3'), '3학점');
    expect(formatCreditsLabel('3.0'), '3학점');
    expect(formatCreditsLabel('3.50'), '3.5학점');
    expect(formatCreditsLabel(' 3.5 '), '3.5학점');
    expect(formatCreditsLabel(''), '');
    expect(formatCreditsLabel('미정'), '미정학점');
  });
}
