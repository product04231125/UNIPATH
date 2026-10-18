import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../shared/app_typography.dart';
import 'assistant_api.dart';
import 'assistant_context_dialog.dart';
import 'assistant_conversation.dart';

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
  bool get _canSend =>
      conversation.ready &&
      conversation.connectionError == null &&
      !conversation.sending &&
      !_savingContext;
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

                    if (_editingContext) ...[
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
                    if (conversation.turns.isEmpty)
                      Text('학교 규정에 관해 질문해 보세요. 승인된 근거가 없으면 근거 부족을 안내합니다.'),
                    for (final turn in conversation.turns) ...[
                      _bubble(
                        Text(
                          '나: ${turn.question}',
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
                          if (_canSend) conversation.send();
                        },
                        decoration: const InputDecoration(
                          labelText: '학교 규정 질문',
                          hintText: '예: 사회봉사 조건은?',
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
                        onPressed: _canSend ? conversation.send : null,
                        icon: Icon(Icons.send),
                      )
                    else
                      FilledButton(
                        onPressed: _canSend ? conversation.send : null,
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
            onPressed: !_canSend ? null : () => _editContext(context),
            child: Text('질의 정보 보완'),
          ),
        if (canRetry)
          TextButton(
            onPressed: !_canSend ? null : () => conversation.retry(turn),
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
  'institution' => '학교',
  'department' => '학과',
  'admission_year' => '입학연도',
  'track' => '이수경로',
  'question' => '질문',
  'graduation_audit' => '졸업감사',
  _ => '질의 입력',
};
