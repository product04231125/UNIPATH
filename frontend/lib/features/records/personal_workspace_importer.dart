import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/personal_import_api.dart';
import '../api/personal_import_models.dart';
import '../api/student_api.dart';
import '../auth/local_data_owner.dart';
import '../planning/remote_planning_repository.dart';
import 'personal_record_codec.dart';
import 'personal_record_repository.dart';
import 'portfolio/portfolio_workspace_repository.dart';

/// Preserves a complete, reviewed graph of the other ten personal collections.
/// Profile/events have their own existing migration and are not sent again.
class PersonalWorkspaceImporter extends ChangeNotifier {
  PersonalWorkspaceImporter(this.api, {required this.ensureOpen, this.writer});
  final StudentApi api;
  final void Function() ensureOpen;
  final Future<bool> Function(String key, String value)? writer;
  final importedRevision = ValueNotifier(0);
  SharedPreferences? _preferences;
  PersonalImportRequest? _request;
  bool loading = true, failed = false, completed = false, _closed = false;
  String? issue;
  Future<void> _pending = Future.value();
  String get _key =>
      LocalDataOwner(api.ownerId)
          .key('university_path.personal_workspace_import.v1');
  String? get snapshotId => _request?.importId;
  static const labels = {
    'course_records': '수강',
    'activity_records': '활동',
    'experience_records': '경험',
    'credential_records': '자격',
    'achievement_records': '성과',
    'personal_curricula': '개인 교육과정',
    'personal_curriculum_courses': '교육과정 과목',
    'personal_graduation_rules': '개인 규칙',
    'portfolio_compositions': '포트폴리오 구성',
    'application_documents': '지원 문서',
  };
  List<String> get preview => [
    if (_request != null)
      for (final entry in _request!.toJson().entries)
        if (labels.containsKey(entry.key))
          for (final row in entry.value as List)
            '${labels[entry.key]} · ${(row as Map)['title']}',
  ];
  int get count => preview.length;
  bool get canImport =>
      !loading && !failed && !completed && issue == null && count > 0;
  void _notify() {
    if (!_closed) notifyListeners();
  }

  Future<void> _enqueue(Future<void> Function() action) {
    final result = _pending.then((_) {
      if (_closed) throw StateError('Import controller closed');
      ensureOpen();
      return action();
    });
    _pending = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  @override
  void dispose() {
    _closed = true;
    importedRevision.dispose();
    super.dispose();
  }

  Future<void> load() => _enqueue(() async {
    loading = true;
    failed = false;
    issue = null;
    _notify();
    try {
      _preferences ??= await SharedPreferences.getInstance();
      final raw = _preferences!.getString(_key);
      if (raw != null) {
        final journal = jsonDecode(raw) as Map;
        if (journal['completed'] is! bool) {
          throw const FormatException('Invalid journal');
        }
        final request = PersonalImportRequest.fromJson(
          Map<String, dynamic>.from(journal['request'] as Map),
        );
        if (request.sourceOwnerId != api.ownerId ||
            !request.consentConfirmed ||
            request.profile != null ||
            request.events.isNotEmpty) {
          throw const FormatException('Invalid import owner or scope');
        }
        _request = request;
        completed = journal['completed'] as bool;
      } else {
        final records = <PersonalRecordKind, List<PersonalRecord>>{};
        for (final kind in PersonalRecordKind.values) {
          final repository = PersonalRecordRepository(
            kind,
            owner: LocalDataOwner(api.ownerId),
          );
          await repository.load();
          records[kind] = repository.records;
        }
        final portfolio = PortfolioWorkspaceRepository(
          owner: LocalDataOwner(api.ownerId),
        );
        await portfolio.load();
        _request = _prepare(records, portfolio);
        completed = false;
      }
      ensureOpen();
    } on _ImportIssue catch (error) {
      _request = null;
      issue = error.message;
    } catch (_) {
      failed = true;
      _request = null;
    } finally {
      loading = false;
      _notify();
    }
  });

  PersonalImportRequest? _prepare(
    Map<PersonalRecordKind, List<PersonalRecord>> records,
    PortfolioWorkspaceRepository portfolio,
  ) {
    String clientId(String original) =>
        RegExp(
          r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
        ).hasMatch(original)
        ? original.toLowerCase()
        : planningClientId();
    final identities = <PersonalRecordKind, Map<String, String>>{
      for (final entry in records.entries)
        entry.key: {for (final row in entry.value) row.id: clientId(row.id)},
    };
    String resolve(PersonalRecordKind kind, String id, String title) {
      final mapped = identities[kind]?[id];
      if (mapped == null) {
        throw _ImportIssue(
          '$title에 연결된 기기 원본이 없습니다. 연결을 확인한 뒤 다시 시도해 주세요. 기기 자료는 유지됩니다.',
        );
      }
      return mapped;
    }

    Map<String, Object?> reference(String ref, String title) {
      final parsed = PersonalRecordCodec.reference(ref);
      final kind = PersonalRecordKind.values.byName(ref.split('/').first);
      return {
        'kind': parsed['kind'],
        'client_id': resolve(kind, parsed['record_id'] as String, title),
      };
    }

    final body = <String, dynamic>{
      'import_id': planningClientId(),
      'source_owner_id': api.ownerId,
      'consent_confirmed': true,
    };
    for (final entry in records.entries) {
      final codec = PersonalRecordCodec(entry.key);
      body[codec.resource.path.replaceAll('-', '_')] = [
        for (final row in entry.value)
          (() {
            final data = codec
                .encode(row.values, clientId: identities[entry.key]![row.id])
                .toJson();
            if (entry.key == PersonalRecordKind.personalCurriculumCourse ||
                entry.key == PersonalRecordKind.personalGraduationRule) {
              data['curriculum_client_id'] = resolve(
                PersonalRecordKind.personalCurriculum,
                data.remove('curriculum_id') as String,
                row.value('title'),
              );
            }
            if (entry.key == PersonalRecordKind.personalCurriculumCourse) {
              final id = data.remove('course_record_id') as String?;
              data['course_record_client_id'] = id == null
                  ? null
                  : resolve(PersonalRecordKind.course, id, row.value('title'));
            }
            if (entry.key == PersonalRecordKind.personalGraduationRule) {
              final id = data.remove('curriculum_course_id') as String?;
              data['curriculum_course_client_id'] = id == null
                  ? null
                  : resolve(
                      PersonalRecordKind.personalCurriculumCourse,
                      id,
                      row.value('title'),
                    );
              if (row.value('relatedRecord').isNotEmpty) {
                data['related_record'] = reference(
                  row.value('relatedRecord'),
                  row.value('title'),
                );
              }
            }
            return data;
          })(),
      ];
    }
    body['portfolio_compositions'] = [
      for (final c in portfolio.compositions)
        {
          'client_id': clientId(c.id),
          'title': c.title,
          'detail': c.description,
          'audience': switch (c.audience) {
            PortfolioAudience.private => 'private',
            PortfolioAudience.application => 'application',
            PortfolioAudience.publicReview => 'public_review',
          },
          'reviewed': c.reviewed,
          'sources': [for (final ref in c.sources) reference(ref, c.title)],
        },
    ];
    body['application_documents'] = [
      for (final d in portfolio.documents)
        {
          'client_id': clientId(d.id),
          'title': d.title,
          'target': d.target,
          'role': d.role,
          'document_type': d.type,
          'body': d.body,
          'sources': [for (final ref in d.sources) reference(ref, d.title)],
        },
    ];
    var total = 0;
    for (final value in body.values.whereType<List>()) {
      if (value.length > 100) {
        throw const _ImportIssue('종류별 100개까지 한 번에 이전할 수 있습니다. 기기 원본은 유지됩니다.');
      }
      total += value.length;
    }
    if (total == 0) return null;
    if (total > 500) {
      throw const _ImportIssue('한 번에 500개까지 이전할 수 있습니다. 기기 원본은 유지됩니다.');
    }
    final request = PersonalImportRequest.fromJson(body);
    if (utf8.encode(jsonEncode(request.toJson())).length > 2 * 1024 * 1024) {
      throw const _ImportIssue('자료가 한 번에 이전할 수 있는 크기를 초과했습니다. 기기 원본은 유지됩니다.');
    }
    return request;
  }

  Future<void> importRecords({
    required bool confirmed,
    required String snapshotId,
  }) => _enqueue(() async {
    if (!confirmed || !canImport || _request?.importId != snapshotId) {
      throw StateError('Review current import snapshot first');
    }
    final request = _request!;
    if (!await _saveJournal(request, false)) {
      throw StateError('Preserve retry journal before sending');
    }
    await PersonalImportApi(api.api, ownerId: api.ownerId).create(request);
    ensureOpen();
    importedRevision.value++;
    if (!await _saveJournal(request, true)) {
      throw StateError('Import committed; recheck same request');
    }
    completed = true;
    _notify();
  });
  Future<bool> _saveJournal(PersonalImportRequest request, bool completed) {
    final raw = jsonEncode({
      'request': request.toJson(),
      'completed': completed,
    });
    return writer?.call(_key, raw) ?? _preferences!.setString(_key, raw);
  }
}

class _ImportIssue implements Exception {
  const _ImportIssue(this.message);
  final String message;
}
