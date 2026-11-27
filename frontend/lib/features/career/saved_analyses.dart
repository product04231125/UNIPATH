import 'package:flutter/material.dart';

import '../../shared/app_tones.dart';
import '../../shared/widgets/surface_card.dart';
import '../../shared/widgets/tone_chip.dart';
import '../auth/auth_api.dart';
import '../planning/planning_dates.dart';

/// The analyses whose finished results are kept: the three 채용공고 분석
/// purposes, 활동 추천 and 자격증 추천.
enum AnalysisKind {
  posting('posting'),
  gap('gap'),
  search('search'),
  activity('activity'),
  certificate('certificate');

  const AnalysisKind(this.value);
  final String value;
}

class SavedAnalysisSummary {
  SavedAnalysisSummary.fromJson(Map<String, dynamic> json)
    : id = json['id'] as String,
      kind = json['kind'] as String,
      title = json['title'] as String,
      summary = Map<String, dynamic>.from(json['summary'] as Map? ?? const {}),
      favorite = json['favorite'] == true,
      createdAt = DateTime.tryParse(json['created_at'] as String? ?? '');
  SavedAnalysisSummary._copy(SavedAnalysisSummary other, {bool? favorite})
    : id = other.id,
      kind = other.kind,
      title = other.title,
      summary = other.summary,
      favorite = favorite ?? other.favorite,
      createdAt = other.createdAt;
  final String id, kind, title;
  final Map<String, dynamic> summary;
  final bool favorite;
  final DateTime? createdAt;

  /// `준비 6 / 7` when the result counted requirements, `공고 3건`, or `추천 4개`.
  String? get fact => switch ((summary['ready'], summary['total'])) {
    (final int ready, final int total) => '준비 $ready / $total',
    _ => switch ((summary['postings'], summary['recommendations'])) {
      (final int count, _) => '공고 $count건',
      (_, final int count) => '추천 $count개',
      _ => null,
    },
  };
}

/// A saved result with what was asked, to show it again.
class SavedAnalysis extends SavedAnalysisSummary {
  SavedAnalysis.fromJson(super.json)
    : input = Map<String, dynamic>.from(json['input'] as Map? ?? const {}),
      result = Map<String, dynamic>.from(json['result'] as Map),
      super.fromJson();
  final Map<String, dynamic> input, result;
}

class AnalysisResultsApi {
  const AnalysisResultsApi(this.api);
  final ApiGateway api;
  static const _path = 'me/analysis-results';

  Future<List<SavedAnalysisSummary>> list(AnalysisKind kind) async => [
    for (final raw
        in (await api.request('GET', '$_path?kind=${kind.value}'))?['items']
                as List? ??
            const [])
      SavedAnalysisSummary.fromJson(Map<String, dynamic>.from(raw as Map)),
  ];

  Future<SavedAnalysis> get(String id) async =>
      SavedAnalysis.fromJson((await api.request('GET', '$_path/$id'))!);

  Future<SavedAnalysisSummary> save({
    required AnalysisKind kind,
    required String title,
    required Map<String, Object?> summary,
    required Map<String, Object?> input,
    required Map<String, dynamic> result,
  }) async => SavedAnalysisSummary.fromJson(
    (await api.request('POST', _path, {
      'kind': kind.value,
      'title': title,
      'summary': summary,
      'input': input,
      'result': result,
    }))!,
  );

  Future<SavedAnalysisSummary> favorite(String id, bool value) async =>
      SavedAnalysisSummary.fromJson(
        (await api.request('PATCH', '$_path/$id', {'favorite': value}))!,
      );

  Future<void> delete(String id) => api.request('DELETE', '$_path/$id');
}

/// A short title from free text: its first non-empty line, at most 60 characters.
String analysisTitle(String text, {String fallback = '분석 결과'}) {
  final line = text
      .split('\n')
      .map((l) => l.trim())
      .firstWhere((l) => l.isNotEmpty, orElse: () => fallback);
  final runes = line.runes.toList();
  return runes.length <= 60 ? line : '${String.fromCharCodes(runes.take(59))}…';
}

/// The saved results of one purpose: the list beside the form, the star on the
/// shown result, and saving each finished result automatically.
class SavedAnalysesController extends ChangeNotifier {
  SavedAnalysesController(this.api, this.kind) {
    refresh();
  }
  final AnalysisResultsApi api;
  final AnalysisKind kind;
  List<SavedAnalysisSummary> items = const [];
  bool loading = true;
  String? error;

  /// The result on screen, when it is saved.
  String? currentId;
  bool _disposed = false;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  SavedAnalysisSummary? get current =>
      items.where((i) => i.id == currentId).firstOrNull;

  Future<void> refresh() async {
    loading = true;
    error = null;
    _notify();
    try {
      items = await api.list(kind);
    } catch (_) {
      error = '저장된 결과를 읽지 못했습니다.';
    }
    loading = false;
    _notify();
  }

  /// Saves a finished result; a failure only shows a note, the result stays on screen.
  Future<void> save({
    required String title,
    required Map<String, Object?> summary,
    required Map<String, Object?> input,
    required Map<String, dynamic> result,
  }) async {
    currentId = null;
    error = null;
    _notify();
    try {
      final saved = await api.save(
        kind: kind,
        title: title,
        summary: summary,
        input: input,
        result: result,
      );
      currentId = saved.id;
      // Starred first, then newest, as the server lists them.
      final starred = items.where((i) => i.favorite).toList();
      final rest = items.where((i) => !i.favorite).toList();
      items = [...starred, saved, ...rest];
    } on AuthFailure catch (e) {
      error = '결과를 저장하지 못했습니다. ${e.message}';
    } catch (_) {
      error = '결과를 저장하지 못했습니다.';
    }
    _notify();
  }

  Future<SavedAnalysis?> open(String id) async {
    try {
      final saved = await api.get(id);
      currentId = id;
      error = null;
      _notify();
      return saved;
    } catch (_) {
      error = '저장된 결과를 열지 못했습니다. 목록을 새로 읽어 주세요.';
      _notify();
      return null;
    }
  }

  Future<void> setFavorite(String id, bool value) async {
    final index = items.indexWhere((i) => i.id == id);
    if (index < 0) return;
    final before = items;
    // Show the star at once; undo if the server refuses.
    items = [...items]
      ..[index] = SavedAnalysisSummary._copy(items[index], favorite: value);
    _notify();
    try {
      await api.favorite(id, value);
      error = null;
      await refresh();
    } on AuthFailure catch (e) {
      items = before;
      error = e.message;
      _notify();
    } catch (_) {
      items = before;
      error = '즐겨찾기를 바꾸지 못했습니다.';
      _notify();
    }
  }

  Future<void> delete(String id) async {
    try {
      await api.delete(id);
      items = items.where((i) => i.id != id).toList();
      if (currentId == id) currentId = null;
      error = null;
    } catch (_) {
      error = '결과를 삭제하지 못했습니다.';
    }
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

String savedAnalysisTime(DateTime? at) {
  if (at == null) return '';
  final local = at.toLocal();
  return '${local.month}월 ${local.day}일 ${planningTime(local)}';
}

/// Star on a shown result: keeps it in the saved list until unstarred.
class SavedAnalysisStar extends StatelessWidget {
  const SavedAnalysisStar({super.key, required this.controller});
  final SavedAnalysesController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final current = controller.current;
      if (current == null) return const SizedBox.shrink();
      return IconButton(
        key: const ValueKey('saved-analysis-current-star'),
        tooltip: current.favorite ? '즐겨찾기 해제' : '즐겨찾기',
        onPressed: () => controller.setFavorite(current.id, !current.favorite),
        icon: Icon(
          current.favorite ? Icons.star : Icons.star_border,
          color: current.favorite
              ? AppTone.warning.color(context)
              : Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      );
    },
  );
}

/// The saved results of one purpose, starred first; tap one to show it again.
class SavedAnalysesPanel extends StatefulWidget {
  const SavedAnalysesPanel({
    super.key,
    required this.controller,
    required this.onOpen,
    this.enabled = true,
  });
  final SavedAnalysesController controller;
  final ValueChanged<SavedAnalysisSummary> onOpen;
  final bool enabled;

  @override
  State<SavedAnalysesPanel> createState() => _SavedAnalysesPanelState();
}

class _SavedAnalysesPanelState extends State<SavedAnalysesPanel> {
  static const _shown = 6;
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = widget.controller;
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final items = c.items;
        final visible = _all ? items : items.take(_shown).toList();
        return SurfaceCard(
          key: ValueKey('saved-analyses-${c.kind.value}'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text('저장된 결과', style: theme.textTheme.titleSmall),
                  const SizedBox(width: 8),
                  if (items.isNotEmpty) ToneChip(label: '${items.length}'),
                  const Spacer(),
                  IconButton(
                    key: ValueKey('saved-analyses-${c.kind.value}-refresh'),
                    tooltip: '저장된 결과 다시 읽기',
                    visualDensity: VisualDensity.compact,
                    onPressed: c.loading ? null : c.refresh,
                    icon: const Icon(Icons.refresh, size: 20),
                  ),
                ],
              ),
              if (c.loading) const LinearProgressIndicator(),
              if (c.error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    c.error!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ),
              if (!c.loading && items.isEmpty && c.error == null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '분석을 마치면 결과가 자동으로 저장됩니다. 별표를 누르면 계속 보관합니다.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              for (final item in visible) _row(context, item),
              if (items.length > _shown)
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton(
                    onPressed: () => setState(() => _all = !_all),
                    child: Text(_all ? '접기' : '${items.length - _shown}개 더 보기'),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _row(BuildContext context, SavedAnalysisSummary item) {
    final theme = Theme.of(context);
    final c = widget.controller;
    final selected = item.id == c.currentId;
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Material(
      key: ValueKey('saved-analysis-${item.id}'),
      color: selected ? AppTone.accent.container(context) : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: widget.enabled ? () => widget.onOpen(item) : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            children: [
              IconButton(
                key: ValueKey('saved-analysis-star-${item.id}'),
                tooltip: item.favorite ? '즐겨찾기 해제' : '즐겨찾기',
                visualDensity: VisualDensity.compact,
                onPressed: () => c.setFavorite(item.id, !item.favorite),
                icon: Icon(
                  item.favorite ? Icons.star : Icons.star_border,
                  size: 20,
                  color: item.favorite
                      ? AppTone.warning.color(context)
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 2),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: selected ? FontWeight.w700 : null,
                      ),
                    ),
                    Text(
                      [
                        savedAnalysisTime(item.createdAt),
                        ?item.fact,
                      ].where((s) => s.isNotEmpty).join(' · '),
                      style: muted,
                    ),
                  ],
                ),
              ),
              IconButton(
                key: ValueKey('saved-analysis-delete-${item.id}'),
                tooltip: '삭제',
                visualDensity: VisualDensity.compact,
                onPressed: () async {
                  final yes = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('저장된 결과 삭제'),
                      content: Text('${item.title} 결과를 삭제합니다.'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('취소'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('삭제'),
                        ),
                      ],
                    ),
                  );
                  if (yes == true) await c.delete(item.id);
                },
                icon: Icon(
                  Icons.delete_outline,
                  size: 20,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
