import 'package:flutter_test/flutter_test.dart';
import 'package:university_path_frontend/shared/year_options.dart';

void main() {
  test('yearOptions lists newest first and keeps out-of-range values', () {
    expect(yearOptions(maxYear: 1902, minYear: 1900), [1902, 1901, 1900]);
    expect(
      yearOptions(maxYear: 2026, minYear: 1900, include: 1899).first,
      2026,
    );
    expect(
      yearOptions(maxYear: 2026, minYear: 1900, include: 1899),
      contains(1899),
    );
    expect(
      yearOptions(maxYear: 2026, minYear: 1900, include: 2027),
      contains(2027),
    );
    expect(
      yearOptions(maxYear: 2026, minYear: 1900, include: 2020)
          .where((year) => year == 2020)
          .length,
      1,
    );
  });
}
