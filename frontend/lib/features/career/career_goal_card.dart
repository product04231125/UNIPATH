import 'package:flutter/material.dart';

import '../../shared/widgets/field_label.dart';
import '../../shared/widgets/surface_card.dart';
import '../auth/auth_api.dart';
import 'career_goal.dart';
import 'job_category_fields.dart';

/// 홈 card: the target job every career feature starts from.
class CareerGoalCard extends StatelessWidget {
  const CareerGoalCard({super.key, required this.controller, this.onFindJobs});

  final CareerGoalController controller;
  final VoidCallback? onFindJobs;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final theme = Theme.of(context);
      final goal = controller.goal;
      final Widget body;
      if (!controller.loaded && controller.loading) {
        body = const Text('목표 직무를 불러오는 중…');
      } else if (!controller.loaded && controller.error != null) {
        body = Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          children: [
            Text(controller.error!),
            TextButton(
              onPressed: controller.load,
              child: const Text('다시 불러오기'),
            ),
          ],
        );
      } else if (!goal.isSet) {
        body = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '목표 직무를 정하면 그 직무 공고가 요구하는 조건과 내 기록을 비교해 준비할 일을 알려 드립니다.',
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              key: const ValueKey('career-goal-set'),
              onPressed: () => showCareerGoalDialog(context, controller),
              icon: const Icon(Icons.flag_outlined),
              label: const Text('목표 직무 정하기'),
            ),
          ],
        );
      } else {
        body = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              goal.summary,
              key: const ValueKey('career-goal-summary'),
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (onFindJobs != null)
                  FilledButton.icon(
                    onPressed: onFindJobs,
                    icon: const Icon(Icons.search),
                    label: const Text('맞는 공고 찾기'),
                  ),
                OutlinedButton(
                  key: const ValueKey('career-goal-change'),
                  onPressed: () => showCareerGoalDialog(context, controller),
                  child: const Text('목표 직무 바꾸기'),
                ),
              ],
            ),
          ],
        );
      }
      return SurfaceCard(
        key: const ValueKey('home-card-목표 직무'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('목표 직무', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            body,
          ],
        ),
      );
    },
  );
}

Future<void> showCareerGoalDialog(
  BuildContext context,
  CareerGoalController controller,
) => showDialog<void>(
  context: context,
  builder: (_) => _CareerGoalDialog(controller: controller),
);

class _CareerGoalDialog extends StatefulWidget {
  const _CareerGoalDialog({required this.controller});
  final CareerGoalController controller;

  @override
  State<_CareerGoalDialog> createState() => _CareerGoalDialogState();
}

class _CareerGoalDialogState extends State<_CareerGoalDialog> {
  late final _goal = widget.controller.goal;
  late var _category = _goal.topCode, _subcategory = _goal.subCode;
  late final _keyword = TextEditingController(text: _goal.keyword);
  late var _categories = widget.controller.categories;
  var _saving = false;
  String? _error;

  @override
  void dispose() {
    _keyword.dispose();
    super.dispose();
  }

  String? _check() {
    final keyword = _keyword.text.trim();
    if (_category.isEmpty && keyword.isEmpty) {
      return '직종을 고르거나 세부 검색어를 입력하세요.';
    }
    if (keyword.runes.length > 80) return '세부 검색어는 80자 이내로 입력하세요.';
    final terms = keyword
        .split(RegExp(r'[,，\n]+'))
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toSet();
    if (terms.length > 5) return '세부 검색어는 쉼표로 구분해 5개까지 입력하세요.';
    return null;
  }

  Future<void> _save() async {
    final problem = _check();
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final code = _subcategory.isEmpty ? _category : _subcategory;
    try {
      await widget.controller.save(
        code.isEmpty ? const [] : [code],
        _keyword.text,
      );
      if (mounted) Navigator.of(context).pop();
    } on AuthFailure catch (e) {
      if (e.status == 409) await widget.controller.load();
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = switch (e.status) {
          409 => '다른 기기에서 목표 직무가 바뀌어 다시 불러왔습니다. 확인 후 다시 저장하세요.',
          422 => '직종과 세부 검색어를 확인하세요.',
          _ => e.message,
        };
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = '목표 직무를 저장하지 못했습니다. 다시 시도하세요.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('목표 직무'),
    content: SizedBox(
      width: 520,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('준비하는 직무를 고용24 직종으로 고르고, 필요하면 세부 검색어를 더하세요.'),
            const SizedBox(height: 16),
            JobCategoryFields(
              keyPrefix: 'goal',
              future: _categories,
              categoryCode: _category,
              subcategoryCode: _subcategory,
              enabled: !_saving,
              onChanged: (category, subcategory) => setState(() {
                _category = category;
                _subcategory = subcategory;
              }),
              onRetry: () =>
                  setState(() => _categories = widget.controller.categories),
            ),
            FieldLabel(
              label: '세부 검색어 (선택)',
              child: TextField(
                key: const ValueKey('goal-keyword'),
                controller: _keyword,
                enabled: !_saving,
                decoration: const InputDecoration(
                  hintText: '예: 프론트엔드, 웹 개발',
                  helperText: '쉼표로 구분해 5개까지 입력할 수 있습니다.',
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Semantics(
                liveRegion: true,
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ],
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => Navigator.of(context).pop(),
        child: const Text('취소'),
      ),
      FilledButton(
        key: const ValueKey('goal-save'),
        onPressed: _saving ? null : _save,
        child: Text(_saving ? '저장 중…' : '저장'),
      ),
    ],
  );
}
