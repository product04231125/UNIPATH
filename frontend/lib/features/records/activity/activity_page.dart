import '../../../shared/app_tones.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/guide_card.dart';
import '../../../shared/widgets/record_tile.dart';
import '../../../shared/widgets/responsive_grid.dart';
import '../../../shared/widgets/tone_chip.dart';
import '../record_display.dart';

import 'package:flutter/material.dart';

import '../../../shared/app_style.dart';
import '../../../shared/drafts/form_draft_picker.dart';
import '../../../shared/drafts/form_draft_store.dart';
import '../../../shared/widgets/external_link_button.dart';
import '../../../shared/widgets/feature_line.dart';
import '../../../shared/widgets/feature_page.dart';
import '../../../shared/widgets/surface_card.dart';
import '../../auth/auth_api.dart';
import '../../auth/guest_preview_scope.dart';
import '../personal_record_fields.dart';
import '../personal_record_form.dart';
import '../personal_record_repository.dart';
import '../personal_repository_scope.dart';

enum _ActivityAddChoice { volunteer, project, intern, club, other }

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
              subtitle: Text('이름·시간·메모를 적습니다.'),
            ),
          ),
          for (final entry in const {
            _ActivityAddChoice.project: '프로젝트',
            _ActivityAddChoice.intern: '인턴',
            _ActivityAddChoice.club: '동아리',
          }.entries)
            SimpleDialogOption(
              key: ValueKey('activity-add-${entry.key.name}'),
              onPressed: () => Navigator.pop(context, entry.key),
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(entry.value),
                subtitle: const Text('참여 기간·역할과 결과를 기록합니다.'),
              ),
            ),
          SimpleDialogOption(
            key: const ValueKey('activity-add-other'),
            onPressed: () => Navigator.pop(context, _ActivityAddChoice.other),
            child: const ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('그 밖의 활동'),
              subtitle: Text('이름·시간·메모를 적습니다.'),
            ),
          ),
        ],
      ),
    );
    if (!mounted || choice == null) return;
    final experienceType = switch (choice) {
      _ActivityAddChoice.project => '프로젝트',
      _ActivityAddChoice.intern => '인턴',
      _ActivityAddChoice.club => '동아리',
      _ => null,
    };
    await _edit(
      experienceType == null
          ? PersonalRecordKind.activity
          : PersonalRecordKind.experience,
      draftValues: experienceType == null ? null : {'type': experienceType},
    );
  }

  Future<void> _edit(
    PersonalRecordKind kind, {
    PersonalRecord? record,
    Map<String, String>? draftValues,
    String? appliedDraftId,
  }) async {
    if (_formOpen || _guestBlocked()) return;
    _formOpen = true;
    try {
      await showPersonalRecordForm(
        context: context,
        kind: kind,
        repository: _repoFor(kind),
        addLabel: kind == PersonalRecordKind.experience ? '경험 추가' : '활동 추가',
        record: record,
        draftValues: draftValues,
        appliedDraftId: appliedDraftId,
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

  Future<void> _loadDraft() async {
    if (_formOpen || _guestBlocked()) return;
    final kind = await showDialog<PersonalRecordKind>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('불러올 임시저장 종류'),
        children: [
          SimpleDialogOption(
            onPressed: () =>
                Navigator.pop(context, PersonalRecordKind.activity),
            child: const Text('활동·봉사'),
          ),
          SimpleDialogOption(
            onPressed: () =>
                Navigator.pop(context, PersonalRecordKind.experience),
            child: const Text('프로젝트·인턴·동아리'),
          ),
        ],
      ),
    );
    if (!mounted || kind == null) return;
    final entry = await showFormDraftPicker(
      context: context,
      collectionKey: formDraftCollectionKey(personalRecordDraftScreenId(kind)),
    );
    if (!mounted || entry == null) return;
    final values = {
      for (final item in entry.payload.entries) item.key: '${item.value ?? ''}',
    };
    await _edit(kind, draftValues: values, appliedDraftId: entry.id);
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

  String _fieldDisplay(PersonalRecordField field, String value) {
    if (field.optionLabels[value] != null) return field.optionLabels[value]!;
    if (field.options.isNotEmpty && !field.options.contains(value)) {
      return '연결 대상 없음 · 수정에서 다시 선택하세요';
    }
    return value;
  }

  Widget _personalEntry(PersonalRecordKind kind, PersonalRecord record) {
    final fields = _fields[kind] ?? personalRecordFields(kind);
    String value(String key) {
      final raw = record.value(key);
      if (raw.isEmpty) return raw;
      final field = fields.where((f) => f.key == key).firstOrNull;
      return field == null ? raw : _fieldDisplay(field, raw);
    }

    final experience = kind == PersonalRecordKind.experience;
    final type = value('type');
    final (icon, tone) = experience
        ? experienceVisual(type)
        : (Icons.volunteer_activism_outlined, AppTone.success);
    final period = recordPeriodLabel(
      record.value('startedOn'),
      record.value('endedOn'),
    );
    final hours = record.value('reportedHours');
    return RecordTile(
      key: ValueKey('record-${kind.name}-${record.id}'),
      icon: icon,
      tone: tone,
      title: record.value('title'),
      chips: [
        ToneChip(
          label: experience ? (type.isEmpty ? '경험' : type) : '활동',
          tone: tone,
        ),
        if (period != null)
          ToneChip(label: period, icon: Icons.calendar_today_outlined),
        if (hours.isNotEmpty)
          ToneChip(label: '${recordNumber(hours)}시간', icon: Icons.schedule),
        if (value('organization') case final org when org.isNotEmpty)
          ToneChip(label: org, icon: Icons.apartment_outlined),
        if (value('role') case final role when role.isNotEmpty)
          ToneChip(label: role, icon: Icons.person_outline),
        if (value('status') case final status when status.isNotEmpty)
          ToneChip(label: status),
      ],
      lines: [
        if (value('result') case final result when result.isNotEmpty) result,
        if (value('detail') case final detail when detail.isNotEmpty) detail,
      ],
      onTap: () => _edit(kind, record: record),
      trailing: [
        for (final field in fields.where(
          (f) =>
              f.type == PersonalFieldType.url && record.value(f.key).isNotEmpty,
        ))
          ExternalLinkButton(url: record.value(field.key), label: field.label),
      ],
      actions: [
        RecordAction(
          '수정',
          Icons.edit_outlined,
          () => _edit(kind, record: record),
        ),
        RecordAction(
          '삭제',
          Icons.delete_outline,
          () => _delete(kind, record),
          destructive: true,
        ),
      ],
    );
  }

  /// Same header in every state so the title never shifts.
  List<Widget> _headerActions(bool serverBacked) {
    final ready = !_loading && !_loadFailed;
    return [
      PopupMenuButton<void>(
        key: const Key('activity-more'),
        tooltip: '더보기',
        enabled: ready,
        icon: const Icon(Icons.more_horiz),
        itemBuilder: (context) => [
          PopupMenuItem<void>(
            key: const Key('activity-load-draft'),
            onTap: _loadDraft,
            child: const ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.inventory_2_outlined),
              title: Text('임시저장 불러오기'),
            ),
          ),
          if (serverBacked)
            PopupMenuItem<void>(
              onTap: _load,
              child: const ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.refresh),
                title: Text('다시 읽기'),
              ),
            ),
        ],
      ),
      IconButton(
        tooltip: '활동 추가',
        onPressed: ready ? _add : null,
        icon: const Icon(Icons.add),
      ),
    ];
  }

  Widget _statePage({required Widget child}) =>
      FeaturePage(title: '활동', trailing: _headerActions(false), body: [child]);

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
    final recordedHours = _activityRepo.records.fold<double>(
      0,
      (sum, r) => sum + (double.tryParse(r.value('reportedHours')) ?? 0),
    );
    final serverBacked =
        _activityRepo.isServerBacked || _experienceRepo.isServerBacked;

    return FeaturePage(
      title: '활동',
      trailing: _headerActions(serverBacked),
      body: [
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              StatStrip(
                items: [
                  ('활동', '${_activityRepo.records.length}'),
                  ('경험', '${_experienceRepo.records.length}'),
                  ('기록 시간', '${recordNumber('$recordedHours')}시간'),
                ],
              ),
              const SizedBox(height: 16),
              if (personal.isEmpty)
                EmptyState(
                  icon: Icons.volunteer_activism_outlined,
                  title: '아직 기록한 활동이 없습니다',
                  message: '봉사·대외활동·프로젝트·인턴·동아리를 기록해 두면 자기소개서와 직무 분석에 쓰입니다.',
                  action: OutlinedButton.icon(
                    onPressed: _add,
                    icon: const Icon(Icons.add),
                    label: const Text('첫 활동 추가'),
                  ),
                )
              else
                ResponsiveGrid(
                  children: [
                    for (final item in personal)
                      _personalEntry(item.$1, item.$2),
                  ],
                ),
            ],
          ),
        ),
      ],
      below: const [
        GuideCard(
          title: '활동 준비',
          lines: ['봉사 시간·증빙 자료 점검', '프로젝트·인턴·동아리는 역할과 결과를 분리해 기록'],
          links: [
            ExternalLinkButton(
              url: 'https://www.1365.go.kr/',
              label: '1365 봉사 찾기',
              description:
                  '1365에서 활동을 찾아 직접 신청할 수 있습니다. 링크 열기로 봉사 시간을 자동 변경하지 않습니다.',
            ),
          ],
        ),
      ],
    );
  }
}
