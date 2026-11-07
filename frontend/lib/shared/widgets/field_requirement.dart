/// Display suffix for form labels. Validation still uses the base field name.
String fieldRequirementLabel(String label, {required bool required}) =>
    required ? '$label (필수)' : '$label (선택)';
