import '../../shared/app_style.dart';
import '../../shared/app_tones.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/tone_chip.dart';

import 'package:flutter/material.dart';

import '../../app_shell/phone_shell.dart';
import '../../shared/drafts/form_draft_picker.dart';
import '../../shared/drafts/form_draft_store.dart';
import '../../shared/widgets/equal_height_row.dart';
import '../../shared/widgets/feature_line.dart';
import '../../shared/widgets/feature_page.dart';
import '../../shared/widgets/input_dialog.dart';
import '../../shared/widgets/surface_card.dart';
import '../../shared/pending_ui_action.dart';
import '../planning/planning_repository.dart';
import '../planning/planning_storage_state.dart';
import '../../shared/widgets/anchored_select_field.dart';
import '../planning/planning_dates.dart';
import '../planning/event_category_tone.dart';
import '../planning/remote_planning_repository.dart';
import '../auth/auth_api.dart';
import '../auth/guest_preview_scope.dart';

const _scheduleDraftScreenId = 'schedule.event';

class SchedulePage extends StatefulWidget {
  const SchedulePage({
    super.key,
    required this.repository,
    this.initialDay,
    this.addRequest,
  });

  final PlanningRepository repository;
  final DateTime? initialDay;
  final PendingUiAction? addRequest;

  @override
  State<SchedulePage> createState() => _SchedulePageState();
}

class _SchedulePageState extends State<SchedulePage> {
  late DateTime _month;
  late DateTime _selectedDay;
  bool _autoAddScheduled = false;

  @override
  void initState() {
    super.initState();
    _selectedDay = _dateOnly(widget.initialDay ?? DateTime.now());
    _month = DateTime(_selectedDay.year, _selectedDay.month);
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.repository,
    builder: (context, _) {
      if (widget.repository.isLoading || widget.repository.loadFailed) {
        return FeaturePage(
          title: '일정',
          body: [PlanningStorageState(repository: widget.repository)],
        );
      }
      final selectedEvents = _eventsForDay(_selectedDay);
      final request = widget.addRequest;
      if (!_autoAddScheduled && request?.isPending == true) {
        _autoAddScheduled = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _autoAddScheduled = false;
          if (!mounted ||
              !identical(widget.addRequest, request) ||
              widget.repository.isLoading ||
              widget.repository.loadFailed) {
            return;
          }
          if (request!.consume()) _editEvent();
        });
      }
      return LayoutBuilder(
        builder: (context, constraints) => FeaturePage(
          padding: EdgeInsets.only(
            bottom: PhoneChromeScope.of(context)
                ? phoneListGap
                : (constraints.maxHeight < 620 ? 28 : 8),
          ),
          title: '일정',
          trailing: [
            PopupMenuButton<void>(
              key: const Key('schedule-more'),
              tooltip: '더보기',
              icon: const Icon(Icons.more_horiz),
              itemBuilder: (context) => [
                PopupMenuItem<void>(
                  key: const Key('schedule-load-draft'),
                  onTap: _loadDraft,
                  child: const ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.inventory_2_outlined),
                    title: Text('임시저장 불러오기'),
                  ),
                ),
              ],
            ),
            FilledButton.icon(
              onPressed: () => _editEvent(),
              icon: const Icon(Icons.add),
              label: const Text('일정 추가'),
            ),
          ],
          body: [
            Align(
              alignment: Alignment.topLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1400),
                child: constraints.maxWidth >= 1000
                    ? EqualHeightRow(
                        children: [
                          Expanded(flex: 3, child: _calendar()),
                          const SizedBox(width: 16),
                          Expanded(flex: 2, child: _dayList(selectedEvents)),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _calendar(),
                          SizedBox(height: FeatureLine.slotGap(context)),
                          _dayList(selectedEvents),
                        ],
                      ),
              ),
            ),
          ],
        ),
      );
    },
  );

  Widget _calendar() {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final showingToday =
        _month.year == now.year &&
        _month.month == now.month &&
        _sameDay(_selectedDay, now);
    return SurfaceCard(
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    '${_month.year}년 ${_month.month}월',
                    style: theme.textTheme.titleLarge,
                  ),
                ),
              ),
              if (!showingToday) ...[
                TextButton(
                  onPressed: () => setState(() {
                    _selectedDay = _dateOnly(now);
                    _month = DateTime(now.year, now.month);
                  }),
                  child: const Text('오늘'),
                ),
                const SizedBox(width: 4),
              ],
              IconButton(
                tooltip: '이전 달',
                onPressed: () => setState(
                  () => _month = DateTime(_month.year, _month.month - 1),
                ),
                icon: const Icon(Icons.chevron_left),
              ),
              IconButton(
                tooltip: '다음 달',
                onPressed: () => setState(
                  () => _month = DateTime(_month.year, _month.month + 1),
                ),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              for (final day in planningWeek(
                DateTime.now(),
                widget.repository.profile.weekStartsOn,
              ))
                Expanded(
                  child: Center(
                    child: Text(
                      weekdayLabel(day.weekday),
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: _weekdayColor(day.weekday),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: 42,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisExtent:
                  MediaQuery.textScalerOf(context).scale(14) * 3 + 20,
            ),
            itemBuilder: (context, index) {
              final first = DateTime(_month.year, _month.month);
              final day = first.add(
                Duration(
                  days:
                      index -
                      (first.weekday -
                              widget.repository.profile.weekStartsOn.weekday +
                              7) %
                          7,
                ),
              );
              return _dayCell(day);
            },
          ),
        ],
      ),
    );
  }

  Color _weekdayColor(int weekday) => switch (weekday) {
    DateTime.sunday => AppTone.danger.color(context),
    DateTime.saturday => AppTone.info.color(context),
    _ => Theme.of(context).colorScheme.onSurfaceVariant,
  };

  Widget _dayCell(DateTime day) {
    final colors = Theme.of(context).colorScheme;
    final events = _eventsForDay(day);
    final selected = _sameDay(day, _selectedDay);
    final today = _sameDay(day, DateTime.now());
    final inMonth = day.month == _month.month;
    final number = Container(
      width: 30,
      height: 30,
      alignment: Alignment.center,
      decoration: today
          ? BoxDecoration(color: colors.primary, shape: BoxShape.circle)
          : null,
      child: Text(
        '${day.day}',
        style: TextStyle(
          fontWeight: selected || today ? FontWeight.w800 : FontWeight.w500,
          color: today
              ? colors.onPrimary
              : inMonth
              ? colors.onSurface
              : colors.onSurfaceVariant.withValues(alpha: .45),
        ),
      ),
    );
    return Semantics(
      button: true,
      selected: selected,
      label:
          '${day.month}월 ${day.day}일${today ? ', 오늘' : ''}, 일정 ${events.length}개',
      child: InkWell(
        onTap: () => setState(() {
          _selectedDay = _dateOnly(day);
          if (!inMonth) _month = DateTime(day.year, day.month);
        }),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          margin: const EdgeInsets.all(2),
          padding: const EdgeInsets.only(top: 4),
          decoration: BoxDecoration(
            color: selected ? colors.primaryContainer : null,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            children: [
              number,
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final event in events.take(3))
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 1.5),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: event.category.tone.color(context),
                          shape: BoxShape.circle,
                        ),
                        child: const SizedBox(width: 6, height: 6),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dayList(List<PlanningEvent> events) {
    final theme = Theme.of(context);
    final day = _selectedDay;
    final today = _sameDay(day, DateTime.now());
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    '${day.month}월 ${day.day}일 ${weekdayLabel(day.weekday)}요일',
                    style: theme.textTheme.titleLarge,
                  ),
                ),
              ),
              if (today) const ToneChip(label: '오늘', tone: AppTone.accent),
              if (events.isNotEmpty) ...[
                const SizedBox(width: 6),
                ToneChip(label: '${events.length}개'),
              ],
            ],
          ),
          const SizedBox(height: 12),
          if (events.isEmpty)
            EmptyState(
              icon: Icons.event_available_outlined,
              title: '일정이 없습니다',
              action: OutlinedButton.icon(
                onPressed: () => _editEvent(),
                icon: const Icon(Icons.add),
                label: const Text('이 날에 추가'),
              ),
            )
          else
            for (final event in events) ...[
              _eventTile(event, day),
              const SizedBox(height: 8),
            ],
        ],
      ),
    );
  }

  Widget _eventTile(PlanningEvent event, DateTime day) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final tone = event.category.tone;
    final continued = !_sameDay(event.start, day);
    return Material(
      color: colors.surfaceContainerLow,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _editEvent(existing: event),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 4, color: tone.color(context)),
              const SizedBox(width: 12),
              SizedBox(
                width: 52,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        continued ? '계속' : _time(event.start),
                        style: theme.textTheme.titleSmall,
                      ),
                      Text(
                        _sameDay(event.end, day) ? _time(event.end) : '다음 날',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        event.title,
                        style: theme.textTheme.titleSmall,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (event.memo.isNotEmpty)
                        Text(
                          event.memo,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      const SizedBox(height: 6),
                      ToneChip(
                        label: event.category.label,
                        tone: tone,
                        dot: true,
                      ),
                    ],
                  ),
                ),
              ),
              IconButton(
                tooltip: '${event.title} 수정',
                icon: const Icon(Icons.edit_outlined, size: 20),
                onPressed: () => _editEvent(existing: event),
              ),
              const SizedBox(width: 4),
            ],
          ),
        ),
      ),
    );
  }

  List<PlanningEvent> _eventsForDay(DateTime day) =>
      eventsOnDay(widget.repository.events, day);

  Future<void> _editEvent({
    PlanningEvent? existing,
    Map<String, Object?>? draftValues,
    String? appliedDraftId,
  }) async {
    if (!_allowWrite()) return;
    await showInputDialog<void>(
      context: context,
      builder: (context) => _EventEditor(
        event: existing,
        initialDay: _selectedDay,
        repository: widget.repository,
        allowWrite: _allowWrite,
        draftValues: draftValues,
        appliedDraftId: appliedDraftId,
      ),
    );
  }

  Future<void> _loadDraft() async {
    if (!_allowWrite()) return;
    final entry = await showFormDraftPicker(
      context: context,
      collectionKey: formDraftCollectionKey(_scheduleDraftScreenId),
    );
    if (!mounted || entry == null) return;
    await _editEvent(draftValues: entry.payload, appliedDraftId: entry.id);
  }

  bool _allowWrite() {
    if (!mounted) return false;
    if (GuestPreviewScope.isActive(context)) {
      GuestPreviewScope.showBlockedMessage(context);
      return false;
    }
    if (widget.repository.writesBlocked) {
      try {
        widget.repository.ensureWritable();
      } on StateError catch (error) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(error.message)));
      }
      return false;
    }
    return true;
  }
}

class _EventEditor extends StatefulWidget {
  const _EventEditor({
    this.event,
    required this.initialDay,
    required this.repository,
    required this.allowWrite,
    this.draftValues,
    this.appliedDraftId,
  });
  final PlanningEvent? event;
  final DateTime initialDay;
  final PlanningRepository repository;
  final bool Function() allowWrite;
  final Map<String, Object?>? draftValues;
  final String? appliedDraftId;

  @override
  State<_EventEditor> createState() => _EventEditorState();
}

class _EventEditorState extends State<_EventEditor> {
  late final TextEditingController _title;
  late final TextEditingController _memo;
  late DateTime _start;
  late DateTime _end;
  late PlanningEventCategory _category;
  late DateTime _defaultStart, _defaultEnd;
  final _formKey = GlobalKey<FormState>();
  final _drafts = FormDraftStore.instance;
  bool _saving = false;
  String? _error;
  late String? _loadedDraftId = widget.appliedDraftId;
  late final String _id = widget.event?.id ?? planningClientId();
  String get _collectionKey => formDraftCollectionKey(_scheduleDraftScreenId);

  @override
  void initState() {
    super.initState();
    final event = widget.event;
    final draft = widget.draftValues;
    _title = TextEditingController(
      text: draft?['title']?.toString() ?? event?.title,
    );
    _memo = TextEditingController(
      text: draft?['memo']?.toString() ?? event?.memo,
    );
    _start =
        DateTime.tryParse(draft?['start']?.toString() ?? '') ??
        event?.start ??
        DateTime(
          widget.initialDay.year,
          widget.initialDay.month,
          widget.initialDay.day,
          9,
        );
    _end =
        DateTime.tryParse(draft?['end']?.toString() ?? '') ??
        event?.end ??
        _start.add(const Duration(hours: 1));
    final categoryName = draft?['category']?.toString();
    _category =
        PlanningEventCategory.values
            .where((c) => c.name == categoryName)
            .firstOrNull ??
        event?.category ??
        PlanningEventCategory.academic;
    _defaultStart = _start;
    _defaultEnd = _end;
  }

  @override
  void dispose() {
    _title.dispose();
    _memo.dispose();
    super.dispose();
  }

  Future<bool> _saveDraft() async {
    if (!widget.allowWrite()) return false;
    try {
      final payload = <String, Object?>{
        'title': _title.text.trim(),
        'memo': _memo.text.trim(),
        'start': _start.toIso8601String(),
        'end': _end.toIso8601String(),
        'category': _category.name,
      };
      final entry = await _drafts.add(
        _collectionKey,
        summary: formDraftSummaryFromValues({
          'title': _title.text.trim(),
          'memo': _memo.text.trim(),
        }),
        payload: payload,
      );
      _loadedDraftId = entry.id;
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('임시저장했습니다.')));
      }
      return true;
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('임시저장하지 못했습니다. 입력은 유지됩니다.')),
        );
      }
      return false;
    }
  }

  @override
  Widget build(BuildContext context) => InputDialog(
    changes: Listenable.merge([_title, _memo]),
    editing: widget.event != null,
    saving: _saving,
    onTempSave: _saveDraft,
    hasUnsavedChanges: () => widget.event == null
        ? _title.text.trim().isNotEmpty ||
              _memo.text.trim().isNotEmpty ||
              _category != PlanningEventCategory.academic ||
              _start != _defaultStart ||
              _end != _defaultEnd ||
              widget.draftValues != null
        : _title.text != widget.event!.title ||
              _memo.text != widget.event!.memo ||
              _category != widget.event!.category ||
              _start != _defaultStart ||
              _end != _defaultEnd,
    hasContent: () =>
        _title.text.trim().isNotEmpty ||
        _memo.text.trim().isNotEmpty ||
        _category != PlanningEventCategory.academic ||
        _start != _defaultStart ||
        _end != _defaultEnd,
    title: Text(widget.event == null ? '일정 추가' : '일정 수정'),
    content: Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextFormField(
            enabled: !_saving,
            controller: _title,
            maxLength: 128,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: '제목',
              hintText: '예: 자료구조 과제 제출',
            ),
            validator: (value) =>
                value == null || value.trim().isEmpty ? '제목을 입력해 주세요.' : null,
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final start = _dateTimeField(
                const Key('event-start'),
                '시작 일시',
                _start,
                (value) => setState(() {
                  _start = value;
                  if (_end.isBefore(_start)) {
                    _end = _start.add(const Duration(hours: 1));
                  }
                }),
              );
              final end = _dateTimeField(
                const Key('event-end'),
                '종료 일시',
                _end,
                (value) => setState(() => _end = value),
              );
              // Side by side when both values fit on one line each.
              final sideBySide =
                  constraints.maxWidth >=
                  MediaQuery.textScalerOf(context).scale(440);
              return sideBySide
                  ? Row(
                      children: [
                        Expanded(child: start),
                        const SizedBox(width: 12),
                        Expanded(child: end),
                      ],
                    )
                  : Column(children: [start, const SizedBox(height: 12), end]);
            },
          ),
          const SizedBox(height: 16),
          AnchoredSelectField<PlanningEventCategory>(
            value: _category,
            label: '분류',
            options: [
              for (final category in PlanningEventCategory.values)
                SelectOption(category, category.label),
            ],
            onChanged: (value) => setState(() => _category = value),
          ),
          const SizedBox(height: 12),
          TextFormField(
            enabled: !_saving,
            controller: _memo,
            maxLength: 8000,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(labelText: '메모 (선택)'),
          ),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
    ),
    actions: [
      if (widget.event != null)
        TextButton.icon(
          style: destructiveButtonStyle(context),
          onPressed: _saving ? null : _delete,
          icon: Icon(Icons.delete_outline),
          label: Text('삭제'),
        ),
      TextButton(
        onPressed: _saving ? null : () => InputDialog.cancel<void>(context),
        child: Text('취소'),
      ),
      TextButton(
        key: const Key('schedule-temp-save'),
        onPressed: _saving ? null : () => _saveDraft(),
        child: const Text('임시저장'),
      ),
      FilledButton(
        onPressed: _saving ? null : _save,
        child: Text(_saving ? '저장 중…' : '저장'),
      ),
    ],
  );

  Widget _dateTimeField(
    Key key,
    String label,
    DateTime value,
    ValueChanged<DateTime> onChanged,
  ) {
    final text =
        '${value.year}.${value.month}.${value.day} (${weekdayLabel(value.weekday)}) ${_time(value)}';
    return Semantics(
      button: true,
      label: '$label $text',
      excludeSemantics: true,
      child: InkWell(
        key: key,
        borderRadius: BorderRadius.circular(appCornerRadius),
        onTap: _saving
            ? null
            : () async {
                final date = await showDatePicker(
                  context: context,
                  initialDate: value,
                  firstDate: DateTime(2000),
                  lastDate: DateTime(2100),
                );
                if (date == null || !mounted) return;
                final time = await showTimePicker(
                  context: context,
                  initialTime: TimeOfDay.fromDateTime(value),
                );
                if (time == null || !mounted) return;
                onChanged(
                  DateTime(
                    date.year,
                    date.month,
                    date.day,
                    time.hour,
                    time.minute,
                  ),
                );
              },
        child: InputDecorator(
          isEmpty: false,
          decoration: InputDecoration(
            labelText: label,
            enabled: !_saving,
            suffixIcon: const Icon(Icons.event_outlined),
          ),
          child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ),
    );
  }

  Future<void> _delete() async {
    if (!widget.allowWrite()) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('개인 일정 삭제'),
        content: Text(
          '${widget.event!.title} 일정을 ${widget.repository.isServerBacked ? '계정 서버' : '이 기기'}에서 삭제할까요?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('취소'),
          ),
          FilledButton(
            style: destructiveButtonStyle(context),
            onPressed: () => Navigator.pop(context, true),
            child: Text('삭제'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _persist(
        () => widget.repository.deleteEvent(
          widget.event!.id,
          expectedVersion: widget.event!.version,
        ),
      );
    }
  }

  Future<void> _persist(Future<void> Function() write) async {
    if (!widget.allowWrite()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await write();
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is AuthFailure
              ? '${error.message} 입력은 유지됩니다.'
              : '${widget.repository.isServerBacked ? '서버' : '기기'}에 저장하지 못했습니다. 입력과 기존 일정을 유지했으니 다시 시도하세요.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _save() async {
    if (!widget.allowWrite()) return;
    if (!_formKey.currentState!.validate()) return;
    if (!_end.isAfter(_start)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('종료 일시는 시작 일시보다 뒤여야 합니다.')));
      return;
    }
    final event = PlanningEvent(
      id: _id,
      version: widget.event?.version,
      title: _title.text.trim(),
      start: _start,
      end: _end,
      category: _category,
      memo: _memo.text.trim(),
    );
    await _persist(() async {
      await widget.repository.saveEvent(event);
      final draftId = _loadedDraftId;
      if (draftId != null) {
        await _drafts.delete(_collectionKey, draftId);
        _loadedDraftId = null;
      }
    });
  }
}

DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);
bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;
String _time(DateTime value) =>
    '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
