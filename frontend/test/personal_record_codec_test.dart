import 'package:flutter_test/flutter_test.dart';
import 'package:university_path_frontend/features/api/student_api.dart';
import 'package:university_path_frontend/features/records/personal_record_codec.dart';
import 'package:university_path_frontend/features/records/personal_record_repository.dart';

import 'support/auth_fixture.dart';
import 'support/personal_workspace_fixture.dart';

void main() {
  for (final kind in PersonalRecordKind.values) {
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
