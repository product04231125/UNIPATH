import 'package:flutter/material.dart';

import '../../shared/widgets/field_label.dart';
import '../api/job_recommendation_api.dart';

/// Work24 1차 직종 and optional 2차 직종 dropdowns, shared by job search and the career goal.
class JobCategoryFields extends StatelessWidget {
  const JobCategoryFields({
    super.key,
    required this.future,
    required this.categoryCode,
    required this.subcategoryCode,
    required this.onChanged,
    this.onRetry,
    this.enabled = true,
    this.error,
    this.keyPrefix = 'recommend',
  });

  final Future<List<JobCategory>> future;
  final String categoryCode, subcategoryCode, keyPrefix;
  final void Function(String category, String subcategory) onChanged;
  final VoidCallback? onRetry;
  final bool enabled;
  final String? error;

  Widget _field({
    required String label,
    required Key key,
    required String value,
    required String emptyLabel,
    required List<JobCategory> options,
    required ValueChanged<String> onChanged,
    String? error,
  }) => FieldLabel(
    label: label,
    child: Semantics(
      label: label,
      child: DropdownButtonFormField<String>(
        key: key,
        initialValue: value,
        isExpanded: true,
        itemHeight: null,
        decoration: InputDecoration(errorText: error, errorMaxLines: 2),
        items: [
          DropdownMenuItem(value: '', child: Text(emptyLabel)),
          for (final option in options)
            DropdownMenuItem(value: option.code, child: Text(option.name)),
        ],
        onChanged: !enabled || options.isEmpty
            ? null
            : (code) => onChanged(code ?? ''),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => FutureBuilder<List<JobCategory>>(
    key: ObjectKey(future),
    future: future,
    builder: (context, snapshot) {
      final categories = snapshot.data ?? const <JobCategory>[];
      final subcategories =
          categories
              .where((category) => category.code == categoryCode)
              .firstOrNull
              ?.children ??
          const <JobCategory>[];
      final loading = snapshot.connectionState != ConnectionState.done;
      // A preset code (e.g. the saved goal) is shown once the list has it; the dropdowns are
      // rebuilt when loading ends so they pick it up.
      final category = categories.any((c) => c.code == categoryCode)
          ? categoryCode
          : '';
      final subcategory = subcategories.any((c) => c.code == subcategoryCode)
          ? subcategoryCode
          : '';
      return KeyedSubtree(
        key: ValueKey(loading),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _field(
              label: '직종',
              key: ValueKey('$keyPrefix-category'),
              value: category,
              emptyLabel: loading ? '직종 목록 불러오는 중…' : '선택 안 함',
              options: categories,
              error: subcategoryCode.isEmpty ? error : null,
              onChanged: (value) => onChanged(value, ''),
            ),
            if (subcategories.isNotEmpty) ...[
              const SizedBox(height: 16),
              _field(
                label: '세부 직종 (선택)',
                key: ValueKey('$keyPrefix-subcategory-$categoryCode'),
                value: subcategory,
                emptyLabel: '선택한 직종 전체',
                options: subcategories,
                error: subcategoryCode.isEmpty ? null : error,
                onChanged: (value) => onChanged(categoryCode, value),
              ),
            ],
            if (!loading && categories.isEmpty && onRetry != null)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton(
                  onPressed: enabled ? onRetry : null,
                  child: const Text('직종 목록을 불러오지 못했습니다. 다시 시도'),
                ),
              ),
            const SizedBox(height: 16),
          ],
        ),
      );
    },
  );
}
