import 'dart:io';

import 'package:university_path_frontend/features/assistant/assistant_api.dart';

/// Run against the current development backend; no questions or responses logged.
Future<void> main() async {
  final api = AssistantApi();
  try {
    final missing = await api.query('사회봉사 조건은?', const SchoolQueryContext());
    final evidence = await api.query(
      '사회봉사 조건은?',
      const SchoolQueryContext(institution: '경동대학교', department: '컴퓨터공학과'),
    );
    final audit = await api.query('저 졸업 가능한가요?', const SchoolQueryContext());
    if (missing.status != AssistantStatus.needsUserInput ||
        evidence.status != AssistantStatus.insufficientEvidence ||
        audit.reason != 'rule_engine_required' ||
        [
          missing,
          evidence,
          audit,
        ].any((r) => r.answer != null || r.citations.isNotEmpty)) {
      throw StateError('Unexpected local backend behavior');
    }
    stdout.writeln('Frontend HTTP client smoke check passed.');
  } catch (_) {
    stderr.writeln(
      'Frontend API smoke check failed. Check the local backend and API_BASE_URL.',
    );
    exitCode = 1;
  } finally {
    api.close();
  }
}
