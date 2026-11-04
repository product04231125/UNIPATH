import 'package:flutter/material.dart';

import '../../../shared/app_style.dart';
import '../../../shared/widgets/external_link_button.dart';
import '../../../shared/widgets/feature_line.dart';
import '../../../shared/widgets/feature_page.dart';
import '../../../shared/widgets/status_badge.dart';
import '../../../shared/widgets/surface_card.dart';
import '../../auth/auth_api.dart';
import '../../auth/guest_preview_scope.dart';
import '../personal_record_fields.dart';
import '../personal_record_form.dart';
import '../personal_record_repository.dart';
import '../personal_repository_scope.dart';

enum _ActivityAddChoice { volunteer, project, other }

/// Unified student menu for activity and experience personal records.
class ActivityPage extends StatefulWidget {
  const ActivityPage({super.key});

  @override
  State<ActivityPage> createState() => _ActivityPageState();
}

class _ActivityPageState extends State<ActivityPage> {
  late final PersonalRecordRepository _activityRepo;
  late final PersonalRecordRepository _experienceRepo;
  var _loading = true;
  var _loadFailed = false;
  var _loadRevision = 0;
  var _formOpen = false;
  Listenable? _importChanges;
  final Map<PersonalRecordKind, List<PersonalRecordField>> _fields = {
    PersonalRecordKind.activity: personalRecordFields(
      PersonalRecordKind.activity,
    ),
    PersonalRecordKind.experience: personalRecordFields(
      PersonalRecordKind.experience,
    ),
  };

  @override
  void initState() {
    super.initState();
    final scope = PersonalRepositoryScope.read(context);
    _activityRepo =
        scope?.records(PersonalRecordKind.activity) ??
        PersonalRecordRepository(PersonalRecordKind.activity);
    _experienceRepo =
        scope?.records(PersonalRecordKind.experience) ??
        PersonalRecordRepository(PersonalRecordKind.experience);
    _importChanges = scope?.importer?.importedRevision;
    _importChanges?.addListener(_reloadAfterImport);
    _load();
  }

  void _reloadAfterImport() => _load();

  @override
  void dispose() {
    _importChanges?.removeListener(_reloadAfterImport);
    _loadRevision++;
    super.dispose();
  }

  Future<void> _load() async {
    final revision = ++_loadRevision;
    if (mounted) {
      setState(() {
        _loading = true;
        _loadFailed = false;
      });
    }
    try {
      await Future.wait([_activityRepo.load(), _experienceRepo.load()]);
      if (mounted && revision == _loadRevision) {
        _fields[PersonalRecordKind.activity] = personalRecordFields(
          PersonalRecordKind.activity,
        );
        _fields[PersonalRecordKind.experience] = personalRecordFields(
          PersonalRecordKind.experience,
        );
      }
    } catch (_) {
      if (mounted && revision == _loadRevision) {
        setState(() => _loadFailed = true);
      }
    } finally {
      if (mounted && revision == _loadRevision) {
        setState(() => _loading = false);
      }
    }
  }

  PersonalRecordRepository _repoFor(PersonalRecordKind kind) =>
      kind == PersonalRecordKind.experience ? _experienceRepo : _activityRepo;

  String _kindLabel(PersonalRecordKind kind) =>
      kind == PersonalRecordKind.experience ? '경험' : '활동';

  bool _guestBlocked() {
    if (!GuestPreviewScope.isActive(context)) return false;
    GuestPreviewScope.showBlockedMessage(context);
    return true;
  }

  Future<void> _add() async {
    if (_formOpen || _guestBlocked()) return;
    final choice = await showDialog<_ActivityAddChoice>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('어떤 활동을 기록할까요?'),
        children: [
          SimpleDialogOption(
            key: const ValueKey('activity-add-volunteer'),
            onPressed: () =>
                Navigator.pop(context, _ActivityAddChoice.volunteer),
            child: const ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('봉사'),
              subtitle: Text('시간·승인 필드를 사용합니다.'),
            ),
          ),
          SimpleDialogOption(
            key: const ValueKey('activity-add-project'),
            onPressed: () => Navigator.pop(context, _ActivityAddChoice.project),
            child: const ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('프로젝트·인턴·동아리'),
              subtitle: Text('역할·결과 필드를 사용합니다.'),
            ),
          ),
          SimpleDialogOption(
            key: const ValueKey('activity-add-other'),
            onPressed: () => Navigator.pop(context, _ActivityAddChoice.other),
            child: const ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('그 밖의 활동'),
              subtitle: Text('교내외 활동 기록의 기존 필드를 사용합니다.'),
            ),
          ),
        ],
      ),
    );
    if (!mounted || choice == null) return;
    final kind = choice == _ActivityAddChoice.project
        ? PersonalRecordKind.experience
        : PersonalRecordKind.activity;
    await _edit(kind);
  }

  Future<void> _edit(PersonalRecordKind kind, [PersonalRecord? record]) async {
    if (_formOpen || _guestBlocked()) return;
    _formOpen = true;
    try {
      await showPersonalRecordForm(
        context: context,
        kind: kind,
        repository: _repoFor(kind),
        addLabel: kind == PersonalRecordKind.experience
            ? '경험 직접 기록'
            : '활동 직접 기록',
        record: record,
        onFieldsReady: (fields) {
          if (mounted) setState(() => _fields[kind] = fields);
        },
        onSaved: () {
          if (mounted) setState(() {});
        },
      );
    } finally {
      _formOpen = false;
    }
  }

  Future<void> _delete(PersonalRecordKind kind, PersonalRecord record) async {
    if (_guestBlocked()) return;
    final repository = _repoFor(kind);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('개인 기록 삭제'),
        content: Text(
          '${record.value('title')} 기록을 ${repository.isServerBacked ? '계정 서버' : '이 기기'}에서 삭제할까요?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            style: destructiveButtonStyle(context),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    if (_guestBlocked()) return;
    try {
      await repository.delete(record.id, expectedVersion: record.version);
      if (mounted) setState(() {});
    } catch (failure) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              failure is AuthFailure && failure.status == 409
                  ? '연결된 자료가 있거나 기록이 변경되었습니다. 연결을 정리하거나 서버 기록을 다시 불러와 주세요.'
                  : '삭제하지 못했습니다. 기록은 유지됩니다.',
            ),
          ),
        );
      }
    }
  }

  String _fieldDisplay(PersonalRecordKind kind, PersonalRecordField field, String value) {
    if (field.optionLabels[value] != null) return field.optionLabels[value]!;
    if (field.options.isNotEmpty && !field.options.contains(value)) {
      return kind == PersonalRecordKind.activity && field.key == 'approval'
          ? '알 수 없는 승인 상태 · 수정에서 다시 선택하세요'
          : '연결 대상 없음 · 수정에서 다시 선택하세요';
    }
    return value;
  }

  Widget _personalEntry(PersonalRecordKind kind, PersonalRecord record) {
    final fields = _fields[kind] ?? personalRecordFields(kind);
    return FeatureLine.two(
      primary: '${_kindLabel(kind)} · ${record.value('title')}',
      secondary: fields
          .where((f) => f.key != 'title' && record.value(f.key).isNotEmpty)
          .map(
            (f) =>
                '${f.label}: ${_fieldDisplay(kind, f, record.value(f.key))}',
          )
          .join(' · '),
      leading: Icon(
        Icons.description_outlined,
        size: 19,
        color: Theme.of(context).colorScheme.onSurface,
      ),
      trailing: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const StatusBadge(status: '개인 기록'),
          for (final field in fields.where(
            (f) =>
                f.type == PersonalFieldType.url &&
                record.value(f.key).isNotEmpty,
          ))
            ExternalLinkButton(
              url: record.value(field.key),
              label: field.label,
            ),
          TextButton(
            onPressed: () => _edit(kind, record),
            child: const Text('수정'),
          ),
          TextButton(
            style: destructiveButtonStyle(context),
            onPressed: () => _delete(kind, record),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
  }

  Widget _statePage({required Widget child}) => FeaturePage(
    title: '활동',
    description: '봉사·교내외 활동과 프로젝트·인턴·동아리 경험을 한곳에서 기록합니다.',
    body: [child],
  );

  @override
  Widget build(BuildContext context) {
    if (_loading) return _statePage(child: const CircularProgressIndicator());
    if (_loadFailed) {
      return _statePage(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const FeatureLine.one(
              text: '개인 기록을 읽지 못했습니다. 기존 저장 내용은 덮어쓰지 않습니다.',
            ),
            FeatureLine.reload(onPressed: _load, label: '다시 시도'),
          ],
        ),
      );
    }

    final personal = [
      for (final record in _activityRepo.records)
        (PersonalRecordKind.activity, record),
      for (final record in _experienceRepo.records)
        (PersonalRecordKind.experience, record),
    ];
    final approvedHours = _activityRepo.records
        .where((r) => r.value('approval') == 'approved')
        .fold<double>(
          0,
          (sum, r) => sum + (double.tryParse(r.value('approvedHours')) ?? 0),
        );
    final serverBacked =
        _activityRepo.isServerBacked || _experienceRepo.isServerBacked;

    return FeaturePage(
      title: '활동',
      description: '봉사·교내외 활동과 프로젝트·인턴·동아리 경험을 한곳에서 기록합니다.',
      body: [
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FeatureLine.section(
                text: '등록한 활동',
                padTop: false,
                padBottom: false,
                trailing: serverBacked
                    ? FeatureLine.reload(onPressed: _loading ? null : _load)
                    : null,
              ),
              FeatureLine.one(
                text: '사용자가 승인됨으로 기록한 봉사 시간 합계 $approvedHours시간',
              ),
              if (personal.isEmpty)
                const FeatureLine.one(text: '개인 기록이 없습니다. 직접 입력해 주세요.'),
              for (final item in personal) _personalEntry(item.$1, item.$2),
            ],
          ),
        ),
      ],
      actions: [
        FilledButton.icon(
          onPressed: _add,
          icon: const Icon(Icons.add),
          label: const Text('활동 직접 기록'),
        ),
      ],
      below: [
        const ExpansionTile(
          title: Text('활동 준비'),
          childrenPadding: EdgeInsets.symmetric(horizontal: 16),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text('• 봉사 시간·증빙 자료 점검'),
            ),
            Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text('• 교내 활동 인정 절차 확인'),
            ),
            Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text('• 프로젝트·인턴·동아리는 역할과 결과를 분리해 기록'),
            ),
            Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text('• 필요할 때 외부 봉사 사이트 안내'),
            ),
          ],
        ),
        const ExternalLinkButton(
          url: 'https://www.1365.go.kr/',
          label: '1365 봉사 찾기',
          description:
              '1365에서 활동을 찾아 직접 신청하고, 학교 인정이 필요한 활동은 학교에 등록·승인받으세요. 링크 열기로 봉사 시간이나 승인 상태를 자동 변경하지 않습니다.',
        ),
      ],
    );
  }
}
