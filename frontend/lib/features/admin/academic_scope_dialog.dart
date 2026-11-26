import 'package:flutter/material.dart';

import '../../shared/widgets/anchored_select_field.dart';
import '../../shared/widgets/input_dialog.dart';
import 'academic_scope_form.dart';

class AcademicScopeSelection {
  const AcademicScopeSelection(this.scope);
  final Map<String, dynamic>? scope;
}

Future<AcademicScopeSelection?> editAcademicScope({
  required BuildContext context,
  required String title,
  required Map<String, dynamic>? initial,
  required List<SelectOption<String>> departments,
  required List<Map<String, dynamic>> tracks,
}) async {
  final key = GlobalKey<AcademicScopeFormState>();
  final changes = ValueNotifier<int>(0);
  String? error;
  try {
    return await showInputDialog<AcademicScopeSelection>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => InputDialog(
          title: Text(title),
          editing: initial != null,
          hasContent: () => key.currentState?.dirty ?? false,
          hasUnsavedChanges: () => key.currentState?.dirty ?? false,
          changes: changes,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('공통 적용 대상 안에서 이 항목의 대상을 더 제한합니다.'),
              if (error != null)
                Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              AcademicScopeForm(
                key: key,
                initial: initial ?? {'clauses': <Object>[]},
                resetKey: 'scope-dialog',
                departments: departments,
                tracks: tracks,
                enabled: true,
                onChanged: () => changes.value++,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  InputDialog.cancel<AcademicScopeSelection>(context),
              child: const Text('취소'),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.pop(context, const AcademicScopeSelection(null)),
              child: const Text('공통 대상 사용'),
            ),
            FilledButton(
              onPressed: () {
                try {
                  final value = key.currentState!.value;
                  Navigator.pop(
                    context,
                    AcademicScopeSelection(Map<String, dynamic>.from(value)),
                  );
                } on FormatException catch (e) {
                  setState(() => error = e.message);
                }
              },
              child: const Text('적용 대상 반영'),
            ),
          ],
        ),
      ),
    );
  } finally {
    changes.dispose();
  }
}
