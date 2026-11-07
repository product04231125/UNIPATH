import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:university_path_frontend/features/api/student_api.dart';
import 'package:university_path_frontend/features/auth/auth_api.dart';
import 'package:university_path_frontend/features/auth/guest_preview_scope.dart';
import 'package:university_path_frontend/features/records/credential/credential_page.dart';
import 'package:university_path_frontend/features/records/official_sources_dialog.dart';
import 'package:university_path_frontend/features/records/personal_record_codec.dart';
import 'package:university_path_frontend/features/records/personal_record_repository.dart';

import 'support/auth_fixture.dart';
import 'support/personal_workspace_fixture.dart';

void main() {
  test('credential fields retain their wire values and optional dates', () {
    const codec = PersonalRecordCodec(PersonalRecordKind.credential);
    final values = {
      'title': '합성 자격',
      'detail': '직접 입력한 메모',
      'provider': '합성 발급 기관',
      'level': '900점 / A등급',
      'earnedOn': '2026-01-02',
      'expiresOn': '',
      'status': '사용자가 입력한 보유 상태',
      'evidenceUrl': 'https://example.org/credential',
    };
    final payload = codec.encode(values, clientId: userId);
    expect(payload.toJson(), containsPair('provider', values['provider']));
    expect(payload.toJson(), containsPair('level', values['level']));
    expect(payload.toJson(), containsPair('earned_on', '2026-01-02'));
    expect(payload.toJson(), containsPair('expires_on', null));
    expect(payload.toJson(), containsPair('status_label', values['status']));
    expect(
      payload.toJson(),
      containsPair('evidence_url', values['evidenceUrl']),
    );
    final record = StudentRecord.fromJson({
      ...payload.toJson(),
      'id': userId,
      'owner_id': userId,
      'version': 3,
      'created_at': '2026-10-19T00:00:00Z',
      'updated_at': '2026-10-19T00:00:00Z',
      'origin': 'personal',
      'official': false,
    }, codec.resource);
    expect(codec.decode(record).values, values);
    expect(codec.encode({'title': '합성 자격'}).toJson()['earned_on'], isNull);
  });

  testWidgets('credential page loads with no personal repository scope', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: CredentialPage())),
    );
    await tester.pumpAndSettle();
    expect(find.text('자격'), findsOneWidget);
    expect(find.text('개인 기록이 없습니다. 직접 입력해 주세요.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('credential registration is blocked in guest preview', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      const MaterialApp(
        home: GuestPreviewScope(
          active: true,
          child: Scaffold(body: CredentialPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final add = find.text('자격 직접 등록');
    await tester.ensureVisible(add);
    await tester.tap(add);
    await tester.pump();
    expect(find.text(GuestPreviewScope.blockedMessage), findsOneWidget);
    expect(find.text('내 기록에 저장'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'official source read failure does not display an empty success',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OfficialSourcesDialog(
              auth: _FailingAuthApi(),
              ownerId: userId,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(sourceError(const FormatException())), findsOneWidget);
      expect(find.text('확인할 제출 자료가 없습니다.'), findsNothing);
      expect(find.text('제출 목록 다시 읽기'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final kind in PersonalRecordKind.values.where(
    (kind) => kind.hasServerContract,
  )) {
    test(
      'personal ${kind.name} maps all UI fields and preserves personal metadata',
      () {
        final codec = PersonalRecordCodec(kind);
        final values = fixtureValues(kind);
        final payload = codec.encode(values, clientId: fixtureId(kind));
        final record = StudentRecord.fromJson({
          ...payload.toJson(),
          'id': fixtureId(kind),
          'owner_id': userId,
          'version': 7,
          'created_at': '2026-10-19T00:00:00Z',
          'updated_at': '2026-10-19T00:00:00Z',
          'origin': 'personal',
          'official': false,
        }, codec.resource);
        final decoded = codec.decode(record);
        expect(decoded.values, values);
        expect(decoded.version, 7);
        expect(
          () => codec.encode({...values, 'unknownField': 'must not disappear'}),
          throwsFormatException,
        );
      },
    );
  }
  test(
    'missing observed values remain null and do not become zero or approved',
    () {
      final codec = PersonalRecordCodec(PersonalRecordKind.activity);
      final data = codec.encode({'title': '합성 활동'}).toJson();
      expect(data['reported_hours'], isNull);
      expect(data['approved_hours'], isNull);
      expect(data['approval'], isNull);
      expect(data['observed_on'], isNull);
    },
  );
  test(
    'unknown completion, required flag and relation kinds are not guessed',
    () {
      expect(
        () => PersonalRecordCodec(PersonalRecordKind.course).encode({
          ...fixtureValues(PersonalRecordKind.course),
          'completion': 'official',
        }),
        throwsFormatException,
      );
      expect(
        () => PersonalRecordCodec(PersonalRecordKind.personalCurriculumCourse)
            .encode({
              ...fixtureValues(PersonalRecordKind.personalCurriculumCourse),
              'requiredCourse': 'unknown',
            }),
        throwsFormatException,
      );
      expect(
        () => PersonalRecordCodec.reference('institution/school-id'),
        throwsFormatException,
      );
    },
  );
}

class _FailingAuthApi implements AuthApi {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw const FormatException();
}
