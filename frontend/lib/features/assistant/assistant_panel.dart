import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../shared/app_typography.dart';
import '../../shared/widgets/external_link_button.dart';
import 'assistant_api.dart';
import 'assistant_context_dialog.dart';
import 'assistant_conversation.dart';
import '../settings/ai_consent_section.dart';
import 'academic_guidance_view.dart';

class AssistantPanel extends StatefulWidget {
  const AssistantPanel({
    super.key,
    required this.conversation,
    required this.onClose,
    required this.width,
    this.onDetach,
    this.suggestContext,
    this.saveContext,
    this.fullScreen = false,
    this.active = true,
  });
  final AssistantConversation conversation;
  final VoidCallback onClose;
  final VoidCallback? onDetach;
  final double width;
  final SchoolQueryContext Function()? suggestContext;
  final Future<void> Function(SchoolQueryContext)? saveContext;
  final bool fullScreen;
  final bool active;

  @override
  AssistantPanelState createState() => AssistantPanelState();
}

class AssistantPanelState extends State<AssistantPanel> {
  AssistantConversation get conversation => widget.conversation;
  double get width => widget.width;
  VoidCallback get onClose => widget.onClose;
  VoidCallback? get onDetach => widget.onDetach;
  SchoolQueryContext Function()? get suggestContext => widget.suggestContext;
  final _scroll = ScrollController();
  final _contextForm = GlobalKey<SchoolQueryContextFormState>();
  final _focusScope = FocusScopeNode();
  int _turnCount = 0;
  bool _editingContext = false;
  bool _savingContext = false;
  bool _authorizing = false;
  bool get _canSend =>
      conversation.ready &&
      conversation.connectionError == null &&
      !conversation.sending &&
      !_authorizing &&
      !_savingContext;

  Future<void> _submit([AssistantTurn? turn]) async {
    if (!_canSend) return;
    if (turn == null && conversation.input.text.trim().isEmpty) return;
    final mode = turn?.mode ?? conversation.mode;
    if (conversation.registeredOnly &&
        (!(turn?.requestContext ?? conversation.context).hasRegisteredSchool ||
            (mode == AssistantMode.personalized &&
                (turn?.records.isEmpty ??
                    conversation.selectedRecords.isEmpty)))) {
      if (turn == null) {
        await conversation.send();
      } else {
        await conversation.retry(turn);
      }
      return;
    }
    if (conversation.requiresConsent && !conversation.allowsMode(mode)) {
      if (conversation.permissionLoading) return;
      setState(() => _authorizing = true);
      try {
        final remember = await chooseAiConsent(context, mode.feature);
        if (!mounted || remember == null) return;
        if (!await conversation.permit(mode, remember: remember)) return;
      } finally {
        if (mounted) setState(() => _authorizing = false);
      }
    }
    if (!mounted) return;
    if (turn == null) {
      await conversation.send();
    } else {
      await conversation.retry(turn);
    }
  }

  @override
  void initState() {
    super.initState();
    _updateTraversal();
    if (widget.active && widget.fullScreen) _restoreFocus();
    conversation.addListener(_followMessages);
  }

  @override
  void didUpdateWidget(covariant AssistantPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updateTraversal();
    if (widget.active &&
        (!oldWidget.active || (!oldWidget.fullScreen && widget.fullScreen))) {
      _restoreFocus();
    }
    if (oldWidget.conversation != conversation) {
      oldWidget.conversation.removeListener(_followMessages);
      conversation.addListener(_followMessages);
    }
  }

  void _followMessages() {
    final added = conversation.turns.length > _turnCount;
    _turnCount = conversation.turns.length;
    final atBottom = !_scroll.hasClients || _scroll.position.extentAfter < 80;
    if (added || atBottom) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scroll.hasClients) {
          _scroll.jumpTo(_scroll.position.maxScrollExtent);
        }
      });
    }
  }

  void _updateTraversal() {
    _focusScope.traversalEdgeBehavior = widget.fullScreen
        ? TraversalEdgeBehavior.closedLoop
        : TraversalEdgeBehavior.parentScope;
  }

  void _restoreFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !widget.active) return;
      final previous = _focusScope.focusedChild;
      final target = previous != null && previous.canRequestFocus
          ? previous
          : _focusScope.traversalDescendants.firstOrNull;
      target?.requestFocus();
    });
  }

  @override
  void dispose() {
    conversation.removeListener(_followMessages);
    _scroll.dispose();
    _focusScope.dispose();
    super.dispose();
  }

  void _editContext(BuildContext context) {
    setState(() => _editingContext = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scroll.hasClients) _scroll.jumpTo(0);
    });
  }

  Future<bool> prepareToLeave() async {
    if (_savingContext) return false;
    if (_editingContext &&
        await _contextForm.currentState?.confirmLeave() == false) {
      return false;
    }
    if (!mounted) return false;
    setState(() => _editingContext = false);
    return true;
  }

  Future<void> _detach() async {
    if (await prepareToLeave()) onDetach?.call();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: conversation,
    builder: (context, _) => FocusScope(
      node: _focusScope,
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): () {
            if (!_savingContext) onClose();
          },
        },
        child: Container(
          width: width,
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
                child: Row(
                  children: [
                    if (widget.fullScreen)
                      IconButton(
                        autofocus: true,
                        tooltip: '작업 화면으로 돌아가기',
                        onPressed: _savingContext ? null : onClose,
                        icon: const Icon(Icons.arrow_back),
                      ),
                    const Expanded(
                      child: Text(
                        'AI 도우미',
                        style: TextStyle(
                          fontSize: AppTypography.section,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    if (onDetach != null)
                      IconButton(
                        tooltip: '새 창으로 분리',
                        onPressed: _savingContext ? null : _detach,
                        icon: Icon(Icons.open_in_new),
                      ),
                    IconButton(
                      tooltip: 'AI 도우미 닫기',
                      onPressed: _savingContext ? null : onClose,
                      icon: Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView(
                  controller: _scroll,
                  padding: const EdgeInsets.all(14),
                  children: [
                    if (conversation.registeredOnly) ...[
                      OutlinedButton.icon(
                        onPressed: conversation.guidanceLoading
                            ? null
                            : conversation.showGuidance,
                        icon: const Icon(Icons.menu_book_outlined),
                        label: const Text('학사 안내'),
                      ),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final mode in AssistantMode.values)
                            ChoiceChip(
                              label: Text(mode.label),
                              selected: conversation.mode == mode,
                              onSelected: !_canSend
                                  ? null
                                  : (_) {
                                      conversation.setMode(mode);
                                      if (mode == AssistantMode.personalized) {
                                        conversation.refreshRecords();
                                      }
                                    },
                            ),
                        ],
                      ),
                      Text(
                        conversation.context.institution == null
                            ? '설정에서 학업 프로필을 확인해 주세요.'
                            : '${conversation.context.institution} · ${conversation.context.department ?? "학과 미선택"}',
                      ),
                      TextButton(
                        onPressed: _canSend ? conversation.openSettings : null,
                        child: const Text('학교 정보는 설정에서 변경'),
                      ),
                      if (!conversation.context.hasRegisteredSchool)
                        const Text(
                          '학교 질문과 맞춤 안내에는 등록된 학교·학과가 필요합니다. 개인 기준·PDF 질문은 아직 지원하지 않습니다.',
                        ),
                      Text(
                        conversation.allowsMode(conversation.mode)
                            ? 'Google 외부 AI 전송 허용 중 · 설정에서 변경'
                            : 'Google 외부 AI 전송 · 전송 전 동의 확인',
                      ),
                      if (conversation.permissionError != null) ...[
                        Text(conversation.permissionError!),
                        TextButton(
                          onPressed: conversation.refreshPermission,
                          child: const Text('전송 설정 다시 읽기'),
                        ),
                      ],
                      if (conversation.mode == AssistantMode.personalized) ...[
                        Text(
                          '질문에 사용할 내 기록 (${conversation.selectedRecords.length}/20)',
                        ),
                        TextButton(
                          onPressed:
                              conversation.recordsLoading ||
                                  conversation.sending
                              ? null
                              : conversation.refreshRecords,
                          child: const Text('개인 기록 다시 읽기'),
                        ),
                        if (conversation.recordsLoading)
                          const LinearProgressIndicator(),
                        if (conversation.recordsError != null)
                          Text(conversation.recordsError!),
                        if (!conversation.recordsLoading &&
                            conversation.recordOptions.isEmpty)
                          const Text('선택할 서버 개인 기록이 없습니다.'),
                        for (final record in conversation.recordOptions)
                          Material(
                            type: MaterialType.transparency,
                            child: CheckboxListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(record.title),
                              subtitle: Text(
                                '${record.kindLabel} · 버전 ${record.version}',
                              ),
                              value: conversation.selectedRecords.any(
                                (r) => r.key == record.key,
                              ),
                              onChanged: conversation.sending
                                  ? null
                                  : (v) => conversation.selectRecord(
                                      record.key,
                                      v == true,
                                    ),
                            ),
                          ),
                      ],
                      if (conversation.submissionError != null)
                        Text(
                          conversation.submissionError!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      const Divider(),
                    ],
                    if (!conversation.registeredOnly)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              '학교 규정 질의 · 대화는 앱 실행 중 유지됩니다.',
                              style: TextStyle(
                                fontSize: AppTypography.caption,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                            ),
                            OutlinedButton.icon(
                              onPressed: !_canSend
                                  ? null
                                  : () => _editContext(context),
                              icon: Icon(Icons.tune, size: 18),
                              label: Text(
                                conversation.context.institution == null
                                    ? '학교 정보 설정'
                                    : '${conversation.context.institution} · ${conversation.context.department ?? "학과 미입력"}',
                              ),
                            ),
                          ],
                        ),
                      ),

                    if (_editingContext && !conversation.registeredOnly) ...[
                      SchoolQueryContextForm(
                        key: _contextForm,
                        initial: conversation.context.institution == null
                            ? suggestContext?.call() ?? conversation.context
                            : conversation.context,
                        enabled: !conversation.sending,
                        onCancel: () => setState(() => _editingContext = false),
                        onSave: (value) async {
                          setState(() => _savingContext = true);
                          try {
                            await widget.saveContext?.call(value);
                            if (mounted) {
                              // A shared repository publishes the committed profile;
                              // do not replace it with an older form snapshot.
                              if (widget.saveContext == null) {
                                conversation.setContext(value);
                              }
                              setState(() => _editingContext = false);
                            }
                          } finally {
                            if (mounted) setState(() => _savingContext = false);
                          }
                        },
                      ),
                      const Divider(),
                    ],
                    if (conversation.guidanceOpen)
                      AcademicGuidanceView(conversation: conversation),
                    if (conversation.turns.isEmpty &&
                        !conversation.guidanceOpen)
                      Text('학교 규정에 관해 질문해 보세요. 승인된 근거가 없으면 근거 부족을 안내합니다.'),
                    for (final turn in conversation.turns) ...[
                      _bubble(
                        Text(
                          '${conversation.registeredOnly ? '${turn.mode.label} · ' : ''}나: ${turn.question}',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onPrimary,
                            height: 1.5,
                          ),
                        ),
                        user: true,
                      ),
                      const SizedBox(height: 8),
                      _bubble(_response(context, turn)),
                      const SizedBox(height: 16),
                    ],
                  ],
                ),
              ),
              if (conversation.sending)
                Semantics(
                  liveRegion: true,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Text('공식 문서 근거 확인 중…'),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        enabled: conversation.ready,
                        controller: conversation.input,
                        maxLength: 4000,
                        onSubmitted: (_) {
                          if (_canSend) _submit();
                        },
                        decoration: InputDecoration(
                          labelText: conversation.registeredOnly
                              ? conversation.mode.label
                              : '학교 규정 질문',
                          hintText:
                              conversation.mode == AssistantMode.personalized
                              ? '예: 내 봉사 기록과 학교 안내를 설명해 줘'
                              : '예: 사회봉사 조건은?',
                          counterText: '',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (width < 300)
                      IconButton.filled(
                        tooltip: '보내기',
                        onPressed: _canSend ? _submit : null,
                        icon: Icon(Icons.send),
                      )
                    else
                      FilledButton(
                        onPressed: _canSend ? _submit : null,
                        child: Text('보내기'),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _bubble(Widget child, {bool user = false}) => Align(
    alignment: user ? Alignment.centerRight : Alignment.centerLeft,
    child: Container(
      constraints: const BoxConstraints(maxWidth: 440),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: user
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
      ),
      child: child,
    ),
  );

  Widget _response(BuildContext context, AssistantTurn turn) {
    if (turn.loading) {
      return Semantics(liveRegion: true, child: Text('답변 기다리는 중…'));
    }
    if (turn.personalized != null) {
      final result = turn.personalized!;
      final statusText = switch (result.reason) {
        'generator_not_configured' => '외부 AI 연결 설정 필요',
        'school_evidence_unavailable' => '학교 자료 확인 필요',
        'generation_failed' => '외부 AI 답변 생성 실패',
        _ => switch (result.status) {
          'grounded' => '학교 자료와 내 기록을 바탕으로 한 안내',
          'evidence_only' => '답변 생성 준비 중 · 조회한 자료',
          'needs_user_input' => '추가 입력 필요',
          'insufficient_evidence' => '답변 근거 부족',
          _ => '맞춤 안내 처리 실패',
        },
      };
      final reasonText = switch (result.reason) {
        'external_processing_consent_required' => '외부 전송 동의를 확인해 주세요.',
        'personal_records_required' => '내 기록을 선택해 주세요.',
        'school_evidence_unavailable' => switch (result.school.reason) {
          'rule_engine_required' => '졸업 가능 여부는 졸업 요건 화면의 감사 결과로 확인해 주세요.',
          'academic_scope_required' => '설정에서 입학연도와 이수경로를 확인해 주세요.',
          'conflicting_admission_year' =>
            '질문 속 입학연도와 설정의 입학연도가 다릅니다. 입력을 확인해 주세요.',
          _ => schoolQueryDiagnostic(result.school.reason) ?? '학교 자료 조회를 완료하지 못했습니다. 관리자에서 학교·학과 연결과 문서 검색 상태를 확인해야 합니다. 현재 응답만으로 UUID 오류인지 자료 부재인지는 구분할 수 없습니다.',
        },
        'generator_not_configured' => '학교 자료와 내 기록은 조회됐지만 외부 AI 답변 생성기가 설정되지 않았습니다. 백엔드의 Vertex AI 연결 설정이 필요합니다.',
        'generation_failed' => '외부 AI 답변 생성 또는 응답 검증에 실패했습니다. 다시 시도하고 문제가 계속되면 백엔드의 AI 연결·응답 처리를 확인해야 합니다.',
        'generator_reported_insufficient_evidence' =>
          '외부 AI가 조회된 학교 자료와 개인 기록만으로는 답변할 수 없다고 응답했습니다. 질문과 선택한 자료를 확인해 주세요.',
        _ => '받은 자료만 표시합니다. 입력을 유지하고 다시 시도할 수 있습니다.',
      };
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(statusText, style: const TextStyle(fontWeight: FontWeight.w700)),
          SelectableText(result.answer ?? reasonText),
          const Divider(),
          const Text('학교 문서'),
          for (final source in result.school.sources) ...[
            Text('${source.title} · ${source.page}페이지'),
            SelectableText(source.excerpt),
            ExternalLinkButton(url: source.sourceUrl, label: '학교 원문 열기'),
          ],
          const Divider(),
          const Text('내 기록'),
          for (final record in result.personal.records) ...[
            Text('${record.title} · 버전 ${record.version}'),
            SelectableText(record.text),
            if (record.truncated) const Text('일부 내용만 포함되었습니다.'),
          ],
          for (final citation in result.personalCitations)
            SelectableText('내 기록 인용: ${citation.excerpt}'),
          TextButton(
            onPressed: _canSend ? () => _submit(turn) : null,
            child: const Text('다시 질문'),
          ),
        ],
      );
    }
    final result = turn.result;
    final error = turn.error;
    final canRetry =
        error != null ||
        result?.status == AssistantStatus.failed ||
        (result?.status == AssistantStatus.needsUserInput &&
            result?.reason != 'rule_engine_required');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          liveRegion: true,
          child: Text(
            result?.label ?? '연결 또는 요청 실패',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(height: 6),
        SelectableText(result?.message ?? error!.message),
        if (result != null &&
            result.missingFields.isNotEmpty &&
            result.reason != 'rule_engine_required')
          Text(
            '필요한 정보: ${result.missingFields.map(assistantFieldLabel).join(", ")}',
          ),
        if (error != null && error.fields.isNotEmpty)
          Text('확인할 입력: ${error.fields.map(assistantFieldLabel).join(", ")}'),
        if (error?.requestId != null)
          SelectableText(
            '문의 식별자: ${error!.requestId}',
            style: TextStyle(fontSize: AppTypography.caption),
          ),
        if (result?.status == AssistantStatus.needsUserInput &&
            result?.reason != 'rule_engine_required')
          TextButton(
            onPressed: !_canSend
                ? null
                : () => conversation.registeredOnly
                      ? conversation.openSettings()
                      : _editContext(context),
            child: Text('질의 정보 보완'),
          ),
        if (canRetry)
          TextButton(
            onPressed: !_canSend ? null : () => _submit(turn),
            child: Text('다시 질문'),
          ),
        for (final citation in result?.citations ?? <AssistantCitation>[]) ...[
          const Divider(),
          Text(
            '${citation.title} · ${citation.page}페이지',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          SelectableText(citation.excerpt),
          TextButton.icon(
            onPressed: () async {
              var opened = false;
              try {
                opened = await launchUrl(
                  citation.source,
                  mode: LaunchMode.externalApplication,
                  webOnlyWindowName: '_blank',
                );
              } catch (_) {
                /* Show the same recoverable error below. */
              }
              if (!opened && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('공식 문서를 열지 못했습니다. 잠시 후 다시 시도해 주세요.'),
                  ),
                );
              }
            },
            icon: Icon(Icons.open_in_new, size: 18),
            label: Text('공식 문서 열기 · 새 창'),
          ),
        ],
      ],
    );
  }
}

String assistantFieldLabel(String field) => switch (field.split('.').last) {
  'institution' || 'institution_id' => '학교',
  'department' || 'department_id' => '학과',
  'curriculum_id' => '교육과정',
  'records' => '개인 기록',
  'external_processing_consent' => '외부 전송 동의',
  'admission_year' => '입학연도',
  'track' => '이수경로',
  'question' => '질문',
  'graduation_audit' => '졸업감사',
  _ => '질의 입력',
};
