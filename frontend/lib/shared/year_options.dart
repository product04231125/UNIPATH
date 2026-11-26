/// Shared year lists for searchable admission/course year selects.
///
/// Admission uses [maxYear] = current calendar year.
/// Course academic years use [maxYear] = current year + 1.
List<int> yearOptions({
  required int maxYear,
  int minYear = 1900,
  int? include,
}) {
  final years = [for (var year = maxYear; year >= minYear; year--) year];
  if (include != null && !years.contains(include)) {
    years.add(include);
    years.sort((a, b) => b.compareTo(a));
  }
  return years;
}
