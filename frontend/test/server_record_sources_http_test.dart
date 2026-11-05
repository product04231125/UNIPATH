import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:university_path_frontend/features/api/official_records_api.dart';
import 'package:university_path_frontend/features/api/record_source_api.dart';
import 'package:university_path_frontend/features/auth/auth_api.dart';

void main() {
  final configured = Platform.environment['UNIPATH_RECORD_SOURCE_API_URL'];
  test(
    'real Flutter PDF submission, scoped review, replay and withdrawal preserve exact evidence',
    () async {
      final base = Uri.parse(configured!);
      expect({'localhost', '127.0.0.1'}, contains(base.host));
      final root = AuthApi(baseUrl: base, cookieMode: false);
      final student = AuthApi(baseUrl: base, cookieMode: false);
      final peer = AuthApi(baseUrl: base, cookieMode: false);
      addTearDown(root.close);
      addTearDown(student.close);
      addTearDown(peer.close);
      final actor = await root.authenticate(
        email: 'source-review-qa@example.invalid',
        password: 'synthetic source review password 2026',
      );
      final rootApi = root.forOwner(actor.id);
      final suffix = DateTime.now().microsecondsSinceEpoch.toString();
      final institution = (await rootApi.request('POST', 'admin/institutions', {
        'name': '합성 원본 검토 $suffix',
      }))!;
      final owner = await student.authenticate(
        email: 'source-owner-$suffix@example.invalid',
        password: 'synthetic source student password 2026',
        displayName: '합성 자료 제출자',
      );
      final api = RecordSourceApi.forOwner(student, owner.id);
      final bytes = Uint8List.fromList(
        utf8.encode('%PDF-1.7\n% SYNTHETIC EVIDENCE ONLY\n%%EOF\n'),
      );
      final metadata = RecordSourceUpload(
        clientId: '00000000-0000-4000-8000-000000000001',
        institutionId: institution['id'] as String,
        documentKind: RecordSourceKind.transcript,
        issuedOn: '2026-01-01',
        filename: '합성 성적 원본.pdf',
        reviewConsentConfirmed: true,
      );
      final source = await api.upload(metadata, bytes);
      expect(source.ownerId, owner.id);
      expect(source.status, RecordSourceStatus.submitted);
      expect((await api.upload(metadata, bytes)).id, source.id);
      expect(await api.download(source.id), bytes);
      final reviewer = RecordSourceApi.forOwner(root, actor.id, admin: true);
      expect(await reviewer.download(source.id), bytes);
      final verified = await reviewer.verify(
        source.id,
        expectedVersion: source.version,
        expectedSha256: source.sha256,
        schoolIssuedConfirmed: true,
        subjectIdentityConfirmed: true,
      );
      expect(verified.status, RecordSourceStatus.verified);
      expect(verified.graduationEligible, isFalse);
      final department = (await rootApi.request('POST', 'admin/departments', {
        'name': '합성 검토 학과',
        'code': 'REVIEW',
        'institution_id': institution['id'],
      }))!;
      final course = (await rootApi.request('POST', 'admin/courses', {
        'name': '합성 검토 과목',
        'code': 'SOURCE1',
        'credits': '3.5',
        'institution_id': institution['id'],
      }))!;
      final records = OfficialRecordsApi.forOwner(root, actor.id, admin: true);
      final ownRecords = OfficialRecordsApi.forOwner(student, owner.id);
      final draftRequest = SchoolRecordBatchCreate(
        sourceId: verified.id,
        expectedSourceVersion: verified.version,
        clientId: '00000000-0000-4000-8000-000000000002',
        data: SchoolRecordAcademicData(
          kind: 'academics',
          pageCount: 1,
          recordsAsOf: '2026-01-01',
          coverage: 'complete',
          context: SchoolRecordContext(
            departmentId: department['id'] as String,
            admissionYear: 2026,
            track: 'single_major',
          ),
          records: [
            SchoolRecordAcademicRecord(
              clientId: '00000000-0000-4000-8000-000000000003',
              sourcePage: 1,
              courseId: course['id'] as String,
              expectedCourseVersion: course['version'] as int,
              completionStatus: 'completed',
              earnedCredits: '3.5',
              originalGrade: 'A+',
            ),
          ],
        ),
      );
      final draft = await records.create(draftRequest);
      expect((await records.create(draftRequest)).id, draft.id);
      expect((await ownRecords.list()).items, isEmpty);
      final approved = await records.approve(
        draft.id,
        SchoolRecordBatchApprove(
          expectedVersion: draft.version,
          expectedSourceSha256: verified.sha256,
          recordsReviewed: true,
          contextReviewed: true,
          coverageReviewed: true,
        ),
      );
      expect(approved.usableForAudit, true);
      final viewed = await ownRecords.get(approved.id);
      final academic = viewed.data as SchoolRecordAcademicData;
      expect(academic.records.single.earnedCredits, '3.5');
      expect(academic.records.single.originalGrade, 'A+');
      expect(academic.records.single.gradePoints, isNull);
      expect(viewed.graduationEligible, false);
      final other = await peer.authenticate(
        email: 'source-peer-$suffix@example.invalid',
        password: 'synthetic source peer password 2026',
        displayName: '합성 다른 사용자',
      );
      await expectLater(
        RecordSourceApi.forOwner(peer, other.id).get(source.id),
        throwsA(isA<AuthFailure>().having((e) => e.status, 'status', 404)),
      );
      await expectLater(
        OfficialRecordsApi.forOwner(peer, other.id).get(approved.id),
        throwsA(isA<AuthFailure>().having((e) => e.status, 'status', 404)),
      );
      final withdrawn = await api.withdraw(
        source.id,
        expectedVersion: verified.version,
      );
      expect(withdrawn.status, RecordSourceStatus.withdrawn);
      final ended = await ownRecords.get(approved.id);
      expect(ended.status, 'revoked');
      expect(ended.usableForAudit, false);
      expect(
        (await ownRecords.events(approved.id)).items.last.action,
        'source_withdrawn',
      );
      await expectLater(
        records.get(approved.id),
        throwsA(isA<AuthFailure>().having((e) => e.status, 'status', 404)),
      );
      await expectLater(
        reviewer.download(source.id),
        throwsA(isA<AuthFailure>().having((e) => e.status, 'status', 404)),
      );
      expect(await api.download(source.id), bytes);
      expect((await api.events(source.id)).map((event) => event.action), [
        RecordSourceStatus.submitted,
        RecordSourceStatus.verified,
        RecordSourceStatus.withdrawn,
      ]);
      expect(
        (await api.upload(metadata, bytes)).status,
        RecordSourceStatus.withdrawn,
      );
    },
    skip: configured == null
        ? 'Requires an owned isolated record-source review API'
        : false,
  );
}
