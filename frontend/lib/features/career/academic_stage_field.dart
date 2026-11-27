import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../shared/widgets/field_label.dart';
import '../planning/academic_stage.dart';

/// The 현재 학년 a recommendation asks with: the 학업 프로필 stage (set in 설정, or
/// counted from the admission year) until the student picks one on the page. A
/// pick, including 선택 안 함, applies to that page only and leaves the profile alone.
class AcademicStageChoice {
  AcademicStage? _picked;
  bool _isPicked = false;

  AcademicStage? valueWith(ValueListenable<AcademicStage?>? profile) =>
      _isPicked ? _picked : profile?.value;

  /// Whether the value shown is the profile's, not one picked here.
  bool fromProfile(ValueListenable<AcademicStage?>? profile) =>
      !_isPicked && profile?.value != null;

  void pick(AcademicStage? stage) {
    _picked = stage;
    _isPicked = true;
  }

  /// Back to following the profile (another account, a cleared form).
  void reset() {
    _picked = null;
    _isPicked = false;
  }
}

/// `현재 학년 (선택)`: 1~4학년, 졸업예정, 졸업 or 선택 안 함.
class AcademicStageField extends StatelessWidget {
  const AcademicStageField({
    super.key,
    required this.fieldKey,
    required this.value,
    required this.onChanged,
    this.fromProfile = false,
    this.errorText,
  });

  /// The dropdown's own key.
  final Key fieldKey;
  final AcademicStage? value;
  final ValueChanged<AcademicStage?>? onChanged;
  final bool fromProfile;
  final String? errorText;

  @override
  Widget build(BuildContext context) => FieldLabel(
    label: '현재 학년 (선택)',
    // The dropdown keeps the value it started with: a new one (the profile
    // loaded or changed) starts it again.
    child: KeyedSubtree(
      key: ValueKey(('academic-stage', value, fromProfile)),
      child: DropdownButtonFormField<AcademicStage>(
        key: fieldKey,
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(
          helperText: fromProfile ? '설정의 학업 프로필 학년입니다.' : null,
          errorText: errorText,
        ),
        items: [
          const DropdownMenuItem(child: Text('선택 안 함')),
          for (final stage in AcademicStage.values)
            DropdownMenuItem(value: stage, child: Text(stage.label)),
        ],
        onChanged: onChanged,
      ),
    ),
  );
}
