import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:university_path_frontend/features/records/portfolio/portfolio_workspace_repository.dart';
import 'package:university_path_frontend/features/records/personal_record_repository.dart';

Future<void> seedRecords() async {
  final works = PersonalRecordRepository(PersonalRecordKind.portfolio);
  await works.load();
  for (final id in ['work-1', 'work-2']) {
    await works.save(
      PersonalRecord(
        id: id,
        values: {
          'title': '합성 성과 $id',
          'type': '프로젝트',
          'role': '합성 설계',
          'result': '합성 결과',
        },
      ),
    );
  }
  final experiences = PersonalRecordRepository(PersonalRecordKind.experience);
  await experiences.load();
  await experiences.save(
    PersonalRecord(
      id: 'experience-1',
      values: {'title': '합성 경험', 'role': '합성 역할', 'result': '합성 경험 결과'},
    ),
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('compositions and documents persist independently without mutating source records', () async {
    await seedRecords();
    final repo = PortfolioWorkspaceRepository();
    await repo.load();
    await repo.saveComposition(
      PortfolioComposition(
        id: 'composition',
        title: '합성 구성',
        audience: PortfolioAudience.publicReview,
        reviewed: true,
        sources: ['portfolio/work-2', 'portfolio/work-1'],
      ),
    );
    await repo.saveDocument(
      ApplicationDocument(
        id: 'document',
        title: '합성 문서',
        target: '합성 기업',
        role: '합성 직무',
        type: '자기소개서',
        body: '사용자 원문',
        sources: ['experience/experience-1', 'portfolio/work-1'],
      ),
    );
    final loaded = PortfolioWorkspaceRepository();
    await loaded.load();
    expect(loaded.compositions.single.sources, [
      'portfolio/work-2',
      'portfolio/work-1',
    ]);
    expect(loaded.compositions.single.audience, PortfolioAudience.publicReview);
    expect(loaded.documents.single.body, '사용자 원문');
    await loaded.deleteComposition('composition');
    expect(loaded.documents.single.id, 'document');
    await loaded.deleteDocument('document');
    final works = PersonalRecordRepository(PersonalRecordKind.portfolio);
    await works.load();
    expect(works.records.length, 2);
    expect(works.records.first.value('result'), '합성 결과');
  });

  test(
    'deleted sources remain explicit and unknown audiences fail the read',
    () async {
      await seedRecords();
      final repo = PortfolioWorkspaceRepository();
      await repo.load();
      await repo.saveComposition(
        PortfolioComposition(
          id: 'composition',
          title: '합성 구성',
          sources: ['portfolio/work-1'],
        ),
      );
      await repo.saveDocument(
        ApplicationDocument(
          id: 'document',
          title: '보존할 문서',
          target: '합성 기관',
          role: '합성 직무',
          type: '이력서',
          body: '직접 작성하여 보존할 본문',
          sources: ['portfolio/work-1'],
        ),
      );
      final works = PersonalRecordRepository(PersonalRecordKind.portfolio);
      await works.load();
      await works.delete('work-1');
      final loaded = PortfolioWorkspaceRepository();
      await loaded.load();
      expect(loaded.compositions.single.sources, ['portfolio/work-1']);
      expect(loaded.documents.single.sources, ['portfolio/work-1']);
      expect(loaded.documents.single.body, '직접 작성하여 보존할 본문');
      expect(
        loaded.compositionText(loaded.compositions.single),
        contains('원본 기록 삭제됨'),
      );
      await loaded.saveComposition(
        PortfolioComposition(
          id: 'composition',
          title: '수정',
          sources: ['portfolio/work-1'],
        ),
      );
      final prefs = await SharedPreferences.getInstance();
      final root = jsonDecode(
        prefs.getString(PortfolioWorkspaceRepository.storageKey)!,
      ) as Map;
      root['compositions'][0]['audience'] = 'future_unknown';
      await prefs.setString(
        PortfolioWorkspaceRepository.storageKey,
        jsonEncode(root),
      );
      final safe = PortfolioWorkspaceRepository();
      await expectLater(safe.load(), throwsFormatException);
      expect(
        (jsonDecode(prefs.getString(PortfolioWorkspaceRepository.storageKey)!)
            as Map)['compositions'][0]['audience'],
        'future_unknown',
      );
    },
  );

  test(
    'invalid references and unreviewed public drafts are not saved',
    () async {
      await seedRecords();
      final repo = PortfolioWorkspaceRepository();
      await repo.load();
      await expectLater(
        repo.saveComposition(
          PortfolioComposition(
            id: 'x',
            title: '합성',
            audience: PortfolioAudience.publicReview,
            sources: ['portfolio/work-1'],
          ),
        ),
        throwsArgumentError,
      );
      await expectLater(
        repo.saveComposition(
          PortfolioComposition(
            id: 'x',
            title: '합성',
            sources: ['experience/experience-1'],
          ),
        ),
        throwsArgumentError,
      );
      await expectLater(
        repo.saveComposition(
          PortfolioComposition(
            id: 'x',
            title: '합성',
            sources: ['portfolio/missing'],
          ),
        ),
        throwsArgumentError,
      );
      expect(repo.compositions, isEmpty);
    },
  );

  test('load and write failures retain original workspace bytes and in-memory data', () async {
    await seedRecords();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      PortfolioWorkspaceRepository.storageKey,
      'invalid synthetic json',
    );
    final corrupt = PortfolioWorkspaceRepository();
    await expectLater(corrupt.load(), throwsFormatException);
    await expectLater(
      corrupt.saveComposition(
        PortfolioComposition(id: 'new', title: '새 구성', sources: []),
      ),
      throwsStateError,
    );
    expect(
      prefs.getString(PortfolioWorkspaceRepository.storageKey),
      'invalid synthetic json',
    );
    await prefs.remove(PortfolioWorkspaceRepository.storageKey);
    final repo = PortfolioWorkspaceRepository(writer: (_, _) async => false);
    await repo.load();
    await expectLater(
      repo.saveDocument(
        ApplicationDocument(
          id: 'new',
          title: '문서',
          target: '기관',
          role: '직무',
          type: '이력서',
          sources: [],
        ),
      ),
      throwsStateError,
    );
    expect(repo.documents, isEmpty);
    expect(prefs.getString(PortfolioWorkspaceRepository.storageKey), isNull);
  });
}
