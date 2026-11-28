import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../../shared/app_style.dart';
import '../../../shared/app_tones.dart';
import '../../../shared/drafts/form_draft_picker.dart';
import '../../../shared/drafts/form_draft_store.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/external_link_button.dart';
import '../../../shared/widgets/feature_line.dart';
import '../../../shared/widgets/feature_page.dart';
import '../../../shared/widgets/guide_card.dart';
import '../../../shared/widgets/page_actions.dart';
import '../../../shared/widgets/record_tile.dart';
import '../../../shared/widgets/responsive_grid.dart';
import '../../../shared/widgets/surface_card.dart';
import '../../../shared/widgets/tone_chip.dart';
import '../../../shared/widgets/work_layout.dart';
import '../../auth/auth_api.dart';
import '../../auth/guest_preview_scope.dart';
import '../personal_record_fields.dart';
import '../personal_record_form.dart';
import '../personal_record_repository.dart';
import '../personal_repository_scope.dart';
import '../record_display.dart';
import 'material_form_dialog.dart';
import 'material_preview.dart';
import 'material_repository.dart';

/// The kinds the 내 자료 chips filter by.
enum MaterialFilter {
  all('전체'),
  activity('활동'),
  credential('자격증'),
  file('자료');

  const MaterialFilter(this.label);
  final String label;
}

/// What `+` adds; the activity keys stay `activity-add-*`.
enum _AddChoice {
  volunteer('봉사', '이름·시간·메모를 적습니다.', MaterialFilter.activity),
  project('프로젝트', '참여 기간·역할과 결과를 기록합니다.', MaterialFilter.activity),
  intern('인턴', '참여 기간·역할과 결과를 기록합니다.', MaterialFilter.activity),
  club('동아리', '참여 기간·역할과 결과를 기록합니다.', MaterialFilter.activity),
  other('그 밖의 활동', '이름·시간·메모를 적습니다.', MaterialFilter.activity),
  credential('자격증', '자격증·어학·교육 이수 내역을 기록합니다.', MaterialFilter.credential),
  file('자료', '포트폴리오·이력서 PDF나 담긴 내용 설명을 보관합니다.', MaterialFilter.file);

  const _AddChoice(this.label, this.help, this.filter);
  final String label, help;
  final MaterialFilter filter;

  Key get key => switch (this) {
    credential || file => ValueKey('material-add-$name'),
    _ => ValueKey('activity-add-$name'),
  };
}

/// 내 자료: 활동·경험, 자격증 records and 자료 (PDF or a described file) in one
/// list, filtered by kind. `+` asks what to record and opens that input dialog.
class MaterialsPage extends StatefulWidget {
  const MaterialsPage({
    super.key,
    this.repository,
    this.pickPdf,
    this.exportPdf,
    this.onChanged,
    this.changes,
  });
  final MaterialRepository? repository;
  final Future<XFile?> Function()? pickPdf;
  final Future<void> Function(PersonalMaterial, Uint8List)? exportPdf;

  /// A 자료 (file) was saved or deleted.
  final VoidCallback? onChanged;

  /// Fires when records were added elsewhere (e.g. from 활동 추천) so the list reloads.
  final Listenable? changes;
  @override
  State<MaterialsPage> createState() => MaterialsPageState();
}

class MaterialsPageState extends State<MaterialsPage> {
  static const _recordKinds = [
    PersonalRecordKind.activity,
    PersonalRecordKind.experience,
    PersonalRecordKind.credential,
  ];

  late final MaterialRepository _materialRepo =
      widget.repository ?? DeviceMaterialRepository();
  late final PersonalRecordRepository _activityRepo, _experienceRepo;
  late final PersonalRecordRepository _credentialRepo;
  Listenable? _importChanges;
  final Map<PersonalRecordKind, List<PersonalRecordField>> _fields = {
    for (final kind in _recordKinds) kind: personalRecordFields(kind),
  };
  List<PersonalMaterial> _materials = [];
  MaterialFilter _filter = MaterialFilter.all;
  bool _loading = true, _recordsFailed = false, _materialsFailed = false;
  bool _busy = false, _formOpen = false;
  int _loadRevision = 0;

  /// Input lives in the 추가·수정 dialogs, which ask before discarding it.
  Future<bool> allowLeave() async => !_busy;

  @override
  void initState() {
    super.initState();
    final scope = PersonalRepositoryScope.read(context);
    PersonalRecordRepository repo(PersonalRecordKind kind) =>
        scope?.records(kind) ?? PersonalRecordRepository(kind);
    _activityRepo = repo(PersonalRecordKind.activity);
    _experienceRepo = repo(PersonalRecordKind.experience);
    _credentialRepo = repo(PersonalRecordKind.credential);
    _importChanges = scope?.importer?.importedRevision;
    _importChanges?.addListener(_reload);
    widget.changes?.addListener(_reload);
    _load();
  }

  @override
  void didUpdateWidget(covariant MaterialsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.changes, widget.changes)) {
      oldWidget.changes?.removeListener(_reload);
      widget.changes?.addListener(_reload);
    }
  }

  @override
  void dispose() {
    _importChanges?.removeListener(_reload);
    widget.changes?.removeListener(_reload);
    _loadRevision++;
    super.dispose();
  }

  void _reload() => _load();

  PersonalRecordRepository _repoFor(PersonalRecordKind kind) => switch (kind) {
    PersonalRecordKind.experience => _experienceRepo,
    PersonalRecordKind.credential => _credentialRepo,
    _ => _activityRepo,
  };

  /// Records and files load apart: a file store that cannot be read still
  /// leaves the records listed, and the other way round.
  Future<void> _load() async {
    final revision = ++_loadRevision;
    setState(() {
      _loading = true;
      _recordsFailed = false;
      _materialsFailed = false;
    });
    Future<void> records() async {
      try {
        await Future.wait([
          for (final kind in _recordKinds) _repoFor(kind).load(),
        ]);
      } catch (_) {
        if (mounted && revision == _loadRevision) _recordsFailed = true;
      }
    }

    Future<void> materials() async {
      try {
        final rows = await _materialRepo.load();
        if (mounted && revision == _loadRevision) _materials = rows;
      } catch (_) {
        if (mounted && revision == _loadRevision) _materialsFailed = true;
      }
    }

    await Future.wait([records(), materials()]);
    if (mounted && revision == _loadRevision) setState(() => _loading = false);
  }

  bool _blocked() {
    if (!GuestPreviewScope.isActive(context)) return false;
    GuestPreviewScope.showBlockedMessage(context);
    return true;
  }

  void _notify(String message) =>
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: Text(message)));

  // ---- adding and editing ----

  Future<void> _add() async {
    if (_busy || _formOpen || _blocked()) return;
    final choices = [
      for (final choice in _AddChoice.values)
        if (_filter == MaterialFilter.all || choice.filter == _filter) choice,
    ];
    final choice = choices.length == 1
        ? choices.single
        : await showDialog<_AddChoice>(
            context: context,
            builder: (context) => SimpleDialog(
              title: const Text('무엇을 기록할까요?'),
              children: [
                for (final choice in choices)
                  SimpleDialogOption(
                    key: choice.key,
                    onPressed: () => Navigator.pop(context, choice),
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(choice.label),
                      subtitle: Text(choice.help),
                    ),
                  ),
              ],
            ),
          );
    if (!mounted || choice == null) return;
    switch (choice) {
      case _AddChoice.file:
        await _editMaterial();
      case _AddChoice.credential:
        await _editRecord(PersonalRecordKind.credential);
      case _AddChoice.project || _AddChoice.intern || _AddChoice.club:
        await _editRecord(
          PersonalRecordKind.experience,
          draftValues: {'type': choice.label},
        );
      case _AddChoice.volunteer || _AddChoice.other:
        await _editRecord(PersonalRecordKind.activity);
    }
  }

  Future<void> _editRecord(
    PersonalRecordKind kind, {
    PersonalRecord? record,
    Map<String, String>? draftValues,
    String? appliedDraftId,
  }) async {
    if (_busy || _formOpen || _blocked()) return;
    _formOpen = true;
    try {
      await showPersonalRecordForm(
        context: context,
        kind: kind,
        repository: _repoFor(kind),
        addLabel: switch (kind) {
          PersonalRecordKind.experience => '경험 추가',
          PersonalRecordKind.credential => '자격증 추가',
          _ => '활동 추가',
        },
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

  Future<void> _editMaterial([PersonalMaterial? material]) async {
    if (_busy || _formOpen || _blocked()) return;
    _formOpen = true;
    final bool saved;
    try {
      saved = await showMaterialForm(
        context: context,
        repository: _materialRepo,
        material: material,
        pickPdf: widget.pickPdf,
        blocked: _blocked,
        onViewSaved: _materialRepo.canPreview ? _view : null,
      );
    } finally {
      _formOpen = false;
    }
    if (saved && mounted) await _refreshMaterials();
  }

  Future<void> _loadDraft() async {
    if (_formOpen || _blocked()) return;
    final kind = await showDialog<PersonalRecordKind>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('불러올 임시저장 종류'),
        children: [
          for (final (kind, label) in const [
            (PersonalRecordKind.activity, '활동·봉사'),
            (PersonalRecordKind.experience, '프로젝트·인턴·동아리'),
            (PersonalRecordKind.credential, '자격증'),
          ])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, kind),
              child: Text(label),
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
    await _editRecord(kind, draftValues: values, appliedDraftId: entry.id);
  }

  // ---- deleting and files ----

  Future<bool> _confirmDelete(String title, String message) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(message),
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
      ) ==
      true;

  Future<void> _deleteRecord(
    PersonalRecordKind kind,
    PersonalRecord record,
  ) async {
    if (_busy || _blocked()) return;
    final repository = _repoFor(kind);
    final confirmed = await _confirmDelete(
      '개인 기록 삭제',
      '${record.value('title')} 기록을 '
          '${repository.isServerBacked ? '계정 서버' : '이 기기'}에서 삭제할까요?',
    );
    if (!confirmed || !mounted || _blocked()) return;
    try {
      await repository.delete(record.id, expectedVersion: record.version);
      if (mounted) setState(() {});
    } catch (failure) {
      if (mounted) {
        _notify(
          failure is AuthFailure && failure.status == 409
              ? '연결된 자료가 있거나 기록이 변경되었습니다. 연결을 정리하거나 서버 기록을 다시 불러와 주세요.'
              : '삭제하지 못했습니다. 기록은 유지됩니다.',
        );
      }
    }
  }

  /// Reads the files again after a change; a failed read must not pretend
  /// that the change itself failed.
  Future<void> _refreshMaterials() async {
    widget.onChanged?.call();
    try {
      _materials = await _materialRepo.load();
      _materialsFailed = false;
    } catch (_) {
      _materialsFailed = true;
    }
    if (mounted) setState(() {});
  }

  Future<void> _deleteMaterial(PersonalMaterial material) async {
    if (_busy || _blocked()) return;
    final confirmed = await _confirmDelete(
      '${material.title} 삭제',
      '${_materialRepo.inAccount ? '계정에' : '이 기기에'} 보관한 설명과 PDF를 삭제합니다. '
          '원래 선택한 파일과 기록·자기소개서·포트폴리오는 삭제하지 않습니다.',
    );
    if (!confirmed || !mounted) return;
    setState(() => _busy = true);
    try {
      await _materialRepo.delete(material);
      if (mounted) await _refreshMaterials();
    } catch (_) {
      if (mounted) _notify('삭제하지 못했습니다. 자료를 유지했습니다. 다시 시도하세요.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _export(PersonalMaterial material) async {
    setState(() => _busy = true);
    try {
      final bytes = await _materialRepo.pdf(material);
      if (bytes == null) return;
      await (widget.exportPdf ?? exportMaterialPdf)(material, bytes);
    } catch (e) {
      if (mounted) {
        _notify(
          e is AuthFailure ? e.message : 'PDF를 내보내지 못했습니다. 보관 자료는 유지했습니다.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  bool _canView(PersonalMaterial material) =>
      material.hasPdf && _materialRepo.canPreview;

  Future<void> _view(PersonalMaterial material) => showMaterialPreview(
    context,
    repository: _materialRepo,
    material: material,
    onExport: () {
      if (!_busy) _export(material);
    },
  );

  // ---- tiles ----

  String _value(PersonalRecordKind kind, PersonalRecord record, String key) {
    final raw = record.value(key);
    if (raw.isEmpty) return raw;
    final fields = _fields[kind] ?? personalRecordFields(kind);
    final field = fields.where((f) => f.key == key).firstOrNull;
    if (field == null) return raw;
    if (field.optionLabels[raw] case final label?) return label;
    if (field.options.isNotEmpty && !field.options.contains(raw)) {
      return '연결 대상 없음 · 수정에서 다시 선택하세요';
    }
    return raw;
  }

  static String _date(String iso) {
    final d = DateTime.tryParse(iso);
    return d == null
        ? iso
        : '${d.year}.${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')}';
  }

  Widget _recordTile(PersonalRecordKind kind, PersonalRecord record) {
    String value(String key) => _value(kind, record, key);
    final IconData icon;
    final AppTone tone;
    final List<Widget> badges;
    final List<RecordFact> facts;
    final lines = <String>[];
    if (kind == PersonalRecordKind.credential) {
      final status = value('status');
      final earned = record.value('earnedOn');
      tone = status.contains('준비') || status.contains('응시')
          ? AppTone.warning
          : earned.isNotEmpty || status.contains('취득') || status.contains('합격')
          ? AppTone.success
          : AppTone.accent;
      icon = Icons.workspace_premium_outlined;
      badges = [
        ToneChip(label: '자격증', tone: tone),
        if (status.isNotEmpty) ToneChip(label: status),
        if (value('level') case final level when level.isNotEmpty)
          ToneChip(label: level, tone: AppTone.info),
      ];
      facts = [
        if (value('provider') case final provider when provider.isNotEmpty)
          RecordFact(Icons.apartment_outlined, provider),
        if (earned.isNotEmpty)
          RecordFact(Icons.calendar_today_outlined, '취득 ${_date(earned)}'),
        if (record.value('expiresOn') case final expires
            when expires.isNotEmpty)
          RecordFact(Icons.event_busy, '만료 ${_date(expires)}'),
      ];
    } else {
      final experience = kind == PersonalRecordKind.experience;
      final type = value('type');
      (icon, tone) = experience
          ? experienceVisual(type)
          : (Icons.volunteer_activism_outlined, AppTone.success);
      final period = recordPeriodLabel(
        record.value('startedOn'),
        record.value('endedOn'),
      );
      final hours = record.value('reportedHours');
      badges = [
        ToneChip(
          label: experience ? (type.isEmpty ? '경험' : type) : '활동',
          tone: tone,
        ),
        if (value('status') case final status when status.isNotEmpty)
          ToneChip(label: status),
      ];
      facts = [
        if (period != null) RecordFact(Icons.calendar_today_outlined, period),
        if (hours.isNotEmpty)
          RecordFact(Icons.schedule, '${recordNumber(hours)}시간'),
        if (value('organization') case final org when org.isNotEmpty)
          RecordFact(Icons.apartment_outlined, org),
        if (value('role') case final role when role.isNotEmpty)
          RecordFact(Icons.person_outline, role),
      ];
      if (value('result') case final result when result.isNotEmpty) {
        lines.add(result);
      }
    }
    if (value('detail') case final detail when detail.isNotEmpty) {
      lines.add(detail);
    }
    final fields = _fields[kind] ?? personalRecordFields(kind);
    return RecordTile(
      key: ValueKey('record-${kind.name}-${record.id}'),
      icon: icon,
      tone: tone,
      title: record.value('title'),
      badges: badges,
      facts: facts,
      lines: lines,
      onTap: () => _editRecord(kind, record: record),
      footer: [
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
          () => _editRecord(kind, record: record),
        ),
        RecordAction(
          '삭제',
          Icons.delete_outline,
          () => _deleteRecord(kind, record),
          destructive: true,
        ),
      ],
    );
  }

  Widget _materialTile(PersonalMaterial r) {
    final pdf = r.hasPdf;
    final tone = pdf ? AppTone.danger : AppTone.accent;
    return RecordTile(
      key: ValueKey('material-row-${r.id}'),
      icon: pdf ? Icons.picture_as_pdf_outlined : Icons.sticky_note_2_outlined,
      tone: tone,
      title: r.title,
      badges: [if (r.type.isNotEmpty) ToneChip(label: r.type, tone: tone)],
      facts: [
        if (pdf)
          RecordFact(
            Icons.attach_file,
            '${r.fileName} · ${(r.byteCount / 1024).ceil()}KB',
          )
        else
          const RecordFact(Icons.edit_note, '내용 설명 기록'),
        if (!_materialRepo.inAccount)
          const RecordFact(Icons.smartphone_outlined, '이 기기에 보관'),
      ],
      lines: [if (r.description.isNotEmpty) r.description],
      onTap: _busy ? null : () => _editMaterial(r),
      footer: [
        if (_canView(r))
          TextButton.icon(
            key: ValueKey('material-view-${r.id}'),
            onPressed: () => _view(r),
            icon: const Icon(Icons.visibility_outlined, size: 18),
            label: const Text('PDF 보기'),
          ),
      ],
      actions: [
        if (_canView(r))
          RecordAction('PDF 보기', Icons.visibility_outlined, () => _view(r)),
        RecordAction('수정', Icons.edit_outlined, () => _editMaterial(r)),
        if (pdf)
          RecordAction('PDF 내보내기', Icons.download_outlined, () {
            if (!_busy) _export(r);
          }),
        RecordAction(
          '삭제',
          Icons.delete_outline,
          () => _deleteMaterial(r),
          destructive: true,
        ),
      ],
    );
  }

  // ---- page ----

  bool _shows(MaterialFilter kind) =>
      _filter == MaterialFilter.all || _filter == kind;

  int _count(MaterialFilter kind) => switch (kind) {
    MaterialFilter.all =>
      _count(MaterialFilter.activity) +
          _count(MaterialFilter.credential) +
          _count(MaterialFilter.file),
    MaterialFilter.activity =>
      _activityRepo.records.length + _experienceRepo.records.length,
    MaterialFilter.credential => _credentialRepo.records.length,
    MaterialFilter.file => _materials.length,
  };

  Widget _list(BuildContext context) {
    final recordedHours = _activityRepo.records.fold<double>(
      0,
      (sum, r) => sum + (double.tryParse(r.value('reportedHours')) ?? 0),
    );
    final tiles = [
      if (_shows(MaterialFilter.activity)) ...[
        for (final record in _activityRepo.records)
          _recordTile(PersonalRecordKind.activity, record),
        for (final record in _experienceRepo.records)
          _recordTile(PersonalRecordKind.experience, record),
      ],
      if (_shows(MaterialFilter.credential))
        for (final record in _credentialRepo.records)
          _recordTile(PersonalRecordKind.credential, record),
      if (_shows(MaterialFilter.file))
        for (final material in _materials) _materialTile(material),
    ];
    final recordsFailed = _recordsFailed && _filter != MaterialFilter.file;
    final filesFailed = _materialsFailed && _shows(MaterialFilter.file);
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          StatStrip(
            items: [
              ('활동', '${_activityRepo.records.length}'),
              ('경험', '${_experienceRepo.records.length}'),
              ('자격증', '${_credentialRepo.records.length}'),
              ('자료', '${_materials.length}'),
              ('기록 시간', '${recordNumber('$recordedHours')}시간'),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            key: const ValueKey('material-filters'),
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final kind in MaterialFilter.values)
                ChoiceChip(
                  key: ValueKey('material-filter-${kind.name}'),
                  label: Text('${kind.label} ${_count(kind)}'),
                  selected: _filter == kind,
                  onSelected: (_) => setState(() => _filter = kind),
                ),
            ],
          ),
          if (recordsFailed) ...[
            const SizedBox(height: 8),
            const FeatureLine.one(
              text: '활동·자격증 기록을 읽지 못했습니다. 기존 저장 내용은 덮어쓰지 않습니다.',
            ),
          ],
          if (filesFailed) ...[
            const SizedBox(height: 8),
            const FeatureLine.one(text: '자료 목록을 읽지 못했습니다. 저장된 자료를 덮어쓰지 않습니다.'),
          ],
          if (recordsFailed || filesFailed)
            FeatureLine.reload(onPressed: _busy ? null : _load, label: '다시 읽기'),
          if (_materialRepo case AccountMaterialRepository(:final unmovedCount)
              when unmovedCount > 0 && _shows(MaterialFilter.file)) ...[
            const SizedBox(height: 8),
            NoteLine(
              key: const ValueKey('materials-unmoved'),
              icon: Icons.warning_amber_outlined,
              text: '이 기기에 남은 자료 $unmovedCount개를 계정으로 옮기지 못했습니다.',
              detail:
                  '8MB를 넘는 PDF이거나 계정 보관 한도(50MB)를 넘었을 수 있습니다. '
                  '다음에 로그인하면 다시 옮깁니다.',
            ),
          ],
          const SizedBox(height: 16),
          if (tiles.isEmpty)
            EmptyState(
              icon: switch (_filter) {
                MaterialFilter.credential => Icons.workspace_premium_outlined,
                MaterialFilter.file => Icons.folder_open_outlined,
                _ => Icons.volunteer_activism_outlined,
              },
              title: switch (_filter) {
                MaterialFilter.activity => '아직 기록한 활동이 없습니다',
                MaterialFilter.credential => '아직 기록한 자격증이 없습니다',
                _ => '아직 기록한 자료가 없습니다',
              },
              message: '활동·자격증·포트폴리오를 기록해 두면 채용공고 분석과 자기소개서에 쓰입니다.',
              action: OutlinedButton.icon(
                onPressed: _busy ? null : _add,
                icon: const Icon(Icons.add),
                label: Text(
                  _filter == MaterialFilter.all
                      ? '첫 자료 추가'
                      : '${_filter.label} 추가',
                ),
              ),
            )
          else
            ResponsiveGrid(
              key: const ValueKey('material-catalog'),
              children: tiles,
            ),
        ],
      ),
    );
  }

  /// Same header in every state so the title never shifts; the actions wait
  /// for the list.
  List<Widget> _headerActions() {
    final ready = !_loading && !_busy;
    final serverBacked =
        _materialRepo.inAccount ||
        _recordKinds.any((kind) => _repoFor(kind).isServerBacked);
    return [
      PageMoreMenu(
        key: const Key('materials-more'),
        enabled: ready,
        itemBuilder: (context) => [
          PopupMenuItem<void>(
            key: const Key('materials-load-draft'),
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
      PageAddButton(label: '자료 추가', onPressed: ready ? _add : null),
    ];
  }

  @override
  Widget build(BuildContext context) => FeaturePage(
    title: '내 자료',
    trailing: _headerActions(),
    body: [if (_loading) const LinearProgressIndicator() else _list(context)],
    below: [
      if (!_loading)
        const GuideCard(
          title: '자료 준비',
          lines: [
            '봉사 시간·증빙 자료 점검',
            '프로젝트·인턴·동아리는 역할과 결과를 분리해 기록',
            '자격증 시험 일정·응시자격은 Q-Net에서 직접 확인',
            '파일 없이 담긴 내용 설명만 기록해도 됩니다 · PDF는 한 개 8MB, 전체 50MB까지',
          ],
          links: [
            ExternalLinkButton(
              url: 'https://www.1365.go.kr/',
              label: '1365 봉사 찾기',
              description:
                  '1365에서 활동을 찾아 직접 신청할 수 있습니다. 링크 열기로 봉사 시간을 자동 변경하지 않습니다.',
            ),
            ExternalLinkButton(
              url: 'https://www.q-net.or.kr/',
              label: 'Q-Net에서 확인',
              description: '시험 일정·응시자격·원서접수는 Q-Net에서 직접 확인하세요. 자동 조회나 자격 취득·보유 내역 변경은 하지 않습니다.',
            ),
          ],
        ),
    ],
  );
}
