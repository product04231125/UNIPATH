import 'package:university_path_frontend/features/auth/local_data_owner.dart';
import 'package:university_path_frontend/features/records/personal_record_repository.dart';
import 'package:university_path_frontend/features/records/portfolio/portfolio_workspace_repository.dart';

String fixtureId(PersonalRecordKind kind) =>
    '10000000-0000-4000-8000-00000000000${kind.index + 1}';
const compositionId = '20000000-0000-4000-8000-000000000001';
const documentId = '20000000-0000-4000-8000-000000000002';
Map<String, String> fixtureValues(PersonalRecordKind kind) => {
  'title': '합성 ${kind.name}',
  'detail': '합성 메모',
  ...switch (kind) {
    PersonalRecordKind.course => {
      'term': '2026-2',
      'category': '전공',
      'credits': '3',
      'section': 'A',
      'courseCode': 'CS101',
      'grade': 'A',
      'completion': '이수 기록',
    },
    PersonalRecordKind.activity => {
      'organization': '합성 행사',
      'role': '운영',
      'startedOn': '2026-10-01',
      'endedOn': '2026-10-02',
      'reportedHours': '4.5',
      'approvedHours': '3.25',
      'approval': 'approved',
      'observedOn': '2026-10-03',
    },
    PersonalRecordKind.experience => {
      'type': '현장실습',
      'organization': '합성 기관',
      'role': '개발',
      'result': '합성 결과',
      'status': '완료',
      'startedOn': '2026-10-01',
      'endedOn': '2026-10-02',
    },
    PersonalRecordKind.credential => {
      'provider': '합성 기관',
      'level': '1급',
      'earnedOn': '2026-01-01',
      'expiresOn': '2028-01-01',
      'status': '보유',
      'evidenceUrl': 'https://example.test/evidence',
    },
    PersonalRecordKind.portfolio => {
      'type': '캡스톤',
      'thesisType': '졸업작품',
      'thesisStatus': '확인 중',
      'thesisGrade': 'A',
      'thesisApprovedOn': '2026-10-01',
      'role': '개발',
      'result': '합성 성과',
      'startedOn': '2026-10-01',
      'endedOn': '2026-10-02',
      'evidenceUrl': 'https://example.test/evidence',
    },
    PersonalRecordKind.personalCurriculum => {
      'school': '합성 대학교',
      'department': '합성 학과',
      'admissionYear': '2024',
      'curriculumYear': '2024',
      'evidenceUrl': 'https://example.test/rules',
    },
    PersonalRecordKind.personalCurriculumCourse => {
      'curriculumId': fixtureId(PersonalRecordKind.personalCurriculum),
      'courseRecordId': fixtureId(PersonalRecordKind.course),
      'courseCode': 'CS101',
      'category': '전공',
      'credits': '3',
      'requiredCourse': '필수',
    },
    PersonalRecordKind.personalGraduationRule => {
      'curriculumId': fixtureId(PersonalRecordKind.personalCurriculum),
      'curriculumCourseId': fixtureId(
        PersonalRecordKind.personalCurriculumCourse,
      ),
      'ruleCode': 'CORE',
      'ruleType': '학점',
      'scope': '교육과정',
      'requiredValue': '3',
      'currentValue': '3',
      'unit': '학점',
      'condition': '명시 조건은 별도 계산에서 확인',
      'effectiveFrom': '2024-03-01',
      'effectiveTo': '2029-02-28',
      'evidenceUrl': 'https://example.test/rules',
      'relatedRecord': 'portfolio/${fixtureId(PersonalRecordKind.portfolio)}',
    },
  },
};
Future<void> seedLocalWorkspace(String ownerId) async {
  for (final kind in PersonalRecordKind.values.where((kind) => kind.hasServerContract)) {
    final repo = PersonalRecordRepository(kind, owner: LocalDataOwner(ownerId));
    await repo.load();
    await repo.save(
      PersonalRecord(id: fixtureId(kind), values: fixtureValues(kind)),
    );
  }
  final portfolio = PortfolioWorkspaceRepository(
    owner: LocalDataOwner(ownerId),
  );
  await portfolio.load();
  await portfolio.saveComposition(
    PortfolioComposition(
      id: compositionId,
      title: '합성 구성',
      description: '구성 메모',
      sources: ['portfolio/${fixtureId(PersonalRecordKind.portfolio)}'],
    ),
  );
  await portfolio.saveDocument(
    ApplicationDocument(
      id: documentId,
      title: '합성 문서',
      target: '합성 지원처',
      role: '개발',
      type: '이력서',
      body: '합성 본문',
      sources: [
        'experience/${fixtureId(PersonalRecordKind.experience)}',
        'portfolio/${fixtureId(PersonalRecordKind.portfolio)}',
      ],
    ),
  );
}
