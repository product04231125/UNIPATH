import '../api/official_record_models.dart';

String recordIssueLabel(String reason) =>
    const {
      'source_unavailable': '원본을 확인할 수 없습니다.',
      'source_changed': '원본이 변경됐습니다.',
      'reference_changed': '등록 과목·자격 기준이 변경됐습니다.',
      'context_incomplete': '학적 문맥 확인이 부족합니다.',
      'partial_records': '일부 기록만 검토됐습니다.',
      'not_approved': '학교 기록 승인이 필요합니다.',
      'snapshot_date_mismatch': '기록 기준일이 일치하지 않습니다.',
    }[reason] ??
    '학교 담당자의 확인이 필요합니다.';

String recordLabel(String value) =>
    const {
      'academics': '성적',
      'volunteers': '봉사',
      'certificates': '자격',
      'theses': '논문',
      'draft': '검토 초안',
      'approved': '승인됨',
      'revoked': '승인 회수',
      'superseded': '새 기록으로 교체됨',
      'discarded': '초안 폐기',
      'complete': '전체 기록 확인',
      'partial': '일부 기록만 확인',
      'completed': '이수',
      'failed': '미이수',
      'in_progress': '진행 중',
      'needs_review': '확인 필요',
      'pending': '대기',
      'rejected': '반려',
      'created': '초안 생성',
      'replaced': '초안 수정',
      'source_revoked': '원본 확인 회수',
      'source_withdrawn': '원본 검토 허용 철회',
    }[value] ??
    '확인 필요';

List<SchoolRecordPayload> recordRows(SchoolRecordData data) => switch (data) {
  SchoolRecordAcademicData d => d.records,
  SchoolRecordVolunteerData d => d.records,
  SchoolRecordCertificateData d => d.records,
  SchoolRecordThesisData d => d.records,
};

String recordSummary(
  SchoolRecordPayload row,
  List<SchoolRecordReferenceSnapshot> refs,
) {
  String name(String id) =>
      refs.where((r) => r.id == id).firstOrNull?.name ?? '등록 항목 (이름 확인 필요)';
  return switch (row) {
    SchoolRecordAcademicRecord r =>
      '${name(r.courseId)} · 원본 ${r.sourcePage}쪽\n${recordLabel(r.completionStatus)} · 취득 ${r.earnedCredits ?? '미확인'}학점 · 분류 ${r.category ?? '미확인'}\n원문 성적 ${r.originalGrade ?? '미확인'} · 숫자 평점 ${r.gradePoints ?? '미확인'} / ${r.gradeScale ?? '미확인'}',
    SchoolRecordVolunteerRecord r =>
      '원본 ${r.sourcePage}쪽 · ${recordLabel(r.approvalStatus)} · ${r.approvedHours ?? '미확인'}시간',
    SchoolRecordCertificateRecord r =>
      '${name(r.certificateId)} · 원본 ${r.sourcePage}쪽 · ${recordLabel(r.approvalStatus)}\n유효기간 ${r.validityKnown ? r.expiresOn ?? '기간 제한 없음' : '미확인'}',
    SchoolRecordThesisRecord r =>
      '${r.thesisType} · 원본 ${r.sourcePage}쪽 · ${recordLabel(r.approvalStatus)}\n완료 ${r.isCompleted == null
          ? '미확인'
          : r.isCompleted!
          ? '확인됨'
          : '미완료'} · 성적 ${r.grade ?? '미확인'}',
    _ => '확인할 수 없는 기록',
  };
}
