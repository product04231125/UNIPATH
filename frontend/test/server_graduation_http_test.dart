import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:university_path_frontend/features/api/graduation_api.dart';
import 'package:university_path_frontend/features/auth/auth_api.dart';

void main() {
  final configured = Platform.environment['UNIPATH_GRADUATION_API_URL'];
  test(
    'real Flutter catalogue attestation, owner-only audit, replay and revocation retain dated evidence',
    () async {
      final base = Uri.parse(configured!);
      expect({'localhost', '127.0.0.1'}, contains(base.host));
      final fixture = jsonDecode(
        File(Platform.environment['UNIPATH_GRADUATION_FIXTURE']!)
            .readAsStringSync(),
      ) as Map;
      final context = GraduationContext.fromJson(
        Map<String, dynamic>.from(fixture['context'] as Map),
      );
      final on = fixture['as_of'] as String;
      final root = AuthApi(baseUrl: base, cookieMode: false);
      final student = AuthApi(baseUrl: base, cookieMode: false);
      final peer = AuthApi(baseUrl: base, cookieMode: false);
      addTearDown(root.close);
      addTearDown(student.close);
      addTearDown(peer.close);
      final admin = await root.authenticate(
        email: 'operator@example.test',
        password: 'synthetic strong password 2026',
      );
      final owner = await student.authenticate(
        email: 'student@example.test',
        password: 'synthetic strong password 2026',
      );
      final reviewer = GraduationCatalogApi.forOwner(root, admin.id);
      final preview = await reviewer.preview(context, on);
      expect(preview.reviewable, true);
      final reviewRequest = CatalogReviewCreate(
        context: context,
        asOf: on,
        clientId: '00000000-0000-4000-8000-000000000001',
        expectedCatalogDigest: preview.snapshotDigest,
        allRequirementsReviewed: true,
        allLevelsReviewed: true,
        sourcesReviewed: true,
        reviewNote: '합성 Flutter 전체 요건 검토',
      );
      final reviewed = await reviewer.create(reviewRequest);
      expect(reviewed.usable, true);
      expect((await reviewer.create(reviewRequest)).id, reviewed.id);
      final api = GraduationApi.forOwner(student, owner.id);
      final request = GraduationAuditCreate(
        context: context,
        asOf: on,
        clientId: '00000000-0000-4000-8000-000000000002',
      );
      final audit = await api.create(request);
      expect(audit.status, 'satisfied');
      expect(audit.eligibleAsOf, true);
      expect(audit.currentUsable, true);
      expect(audit.results.single.current, '3.5');
      expect(
        audit.recordEvidence.single.recordId,
        audit.results.single.evidenceRecordIds.single,
      );
      expect(audit.recordEvidence.single.sourcePage, 1);
      expect((await api.create(request)).id, audit.id);
      expect((await api.list()).items.single.id, audit.id);
      final other = await peer.authenticate(
        email: 'graduation-peer@example.invalid',
        password: 'synthetic strong password 2026',
        displayName: '합성 감사 다른 학생',
      );
      await expectLater(
        GraduationApi.forOwner(peer, other.id).get(audit.id),
        throwsA(isA<AuthFailure>().having((e) => e.status, 'status', 404)),
      );
      await expectLater(
        GraduationApi.forOwner(root, admin.id).get(audit.id),
        throwsA(isA<AuthFailure>().having((e) => e.status, 'status', 404)),
      );
      await reviewer.revoke(
        reviewed.id,
        CatalogReviewRevoke(
          expectedVersion: reviewed.version,
          reason: '합성 검토 회수',
        ),
      );
      final historical = await api.get(audit.id);
      expect(historical.status, 'satisfied');
      expect(historical.eligibleAsOf, true);
      expect(historical.currentUsable, false);
      expect(historical.results.single.current, '3.5');
      expect((await reviewer.events(reviewed.id)).items.last.action, 'revoked');
      final fresh = await api.create(
        GraduationAuditCreate(
          context: context,
          asOf: on,
          clientId: '00000000-0000-4000-8000-000000000003',
        ),
      );
      expect(fresh.catalogComplete, false);
      expect(fresh.status, 'needs_review');
      expect(fresh.eligibleAsOf, false);
    },
    skip: configured == null
        ? 'Requires an owned isolated graduation audit API'
        : false,
  );
}
