import 'dart:async';

import 'package:flutter/material.dart';

import '../../shared/app_tones.dart';
import '../../shared/widgets/external_link_button.dart';
import '../../shared/widgets/feature_page.dart';
import '../../shared/widgets/surface_card.dart';
import '../../shared/widgets/tone_chip.dart';
import '../../shared/widgets/work_layout.dart';
import '../api/student_api.dart';
import '../auth/auth_api.dart';
import '../auth/guest_preview_scope.dart';
import 'certificate_schedule.dart';
import 'certificates.dart';

/// 시험 일정: search any certificate and see its official schedule, fee and exam method.
class CertificateLookupView extends StatefulWidget {
  const CertificateLookupView({
    super.key,
    required this.api,
    required this.selection,
    this.onAddEvents,
    this.now,
  });
  final StudentApi? api;
  final CertificateSelection selection;
  final AddCertificateEvents? onAddEvents;
  final DateTime Function()? now;

  @override
  State<CertificateLookupView> createState() => _CertificateLookupViewState();
}

class _CertificateLookupViewState extends State<CertificateLookupView> {
  final _query = TextEditingController();
  Timer? _debounce;
  List<CertificateSummary> _results = const [];
  bool _searching = false;
  String? _searchError;
  CertificateDetail? _detail;
  bool _loading = false;
  String? _detailError;
  var _revision = 0;

  bool get _connected =>
      widget.api != null && !GuestPreviewScope.isActive(context);

  @override
  void initState() {
    super.initState();
    widget.selection.addListener(_selected);
    WidgetsBinding.instance.addPostFrameCallback((_) => _selected());
  }

  @override
  void didUpdateWidget(covariant CertificateLookupView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.selection, widget.selection)) {
      oldWidget.selection.removeListener(_selected);
      widget.selection.addListener(_selected);
    }
    if (oldWidget.api?.ownerId != widget.api?.ownerId) {
      _revision++;
      _results = const [];
      _detail = null;
      _query.clear();
    }
  }

  @override
  void dispose() {
    widget.selection.removeListener(_selected);
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  void _selected() {
    final item = widget.selection.selected;
    if (!mounted || item == null || _detail?.summary.id == item.id) return;
    _open(item);
  }

  void _changed(String text) {
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 300),
      () => _search(text.trim()),
    );
  }

  Future<void> _search(String text) async {
    final api = widget.api;
    if (api == null || !_connected) return;
    final revision = ++_revision;
    if (text.isEmpty) {
      setState(() => _results = const []);
      return;
    }
    setState(() {
      _searching = true;
      _searchError = null;
    });
    try {
      final found = await CertificateApi(api).search(text);
      if (mounted && revision == _revision) setState(() => _results = found);
    } catch (e) {
      if (mounted && revision == _revision) {
        setState(
          () => _searchError = e is AuthFailure ? e.message : '검색하지 못했습니다.',
        );
      }
    } finally {
      if (mounted && revision == _revision) setState(() => _searching = false);
    }
  }

  Future<void> _open(CertificateSummary item) async {
    final api = widget.api;
    if (api == null || !_connected) return;
    final revision = ++_revision;
    setState(() {
      _loading = true;
      _detailError = null;
    });
    try {
      final detail = await CertificateApi(api).detail(item.id);
      if (mounted && revision == _revision) setState(() => _detail = detail);
    } catch (e) {
      if (mounted && revision == _revision) {
        setState(
          () => _detailError = e is AuthFailure
              ? e.message
              : '${item.name} 정보를 불러오지 못했습니다.',
        );
      }
    } finally {
      if (mounted && revision == _revision) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final detail = _detail;
    return FeaturePage(
      title: '시험 일정',
      body: [
        WorkLayout(
          input: SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  key: const ValueKey('certificate-search'),
                  controller: _query,
                  enabled: _connected,
                  decoration: InputDecoration(
                    labelText: '자격증 이름',
                    hintText: '예: 정보처리기사, SQLD, 컴퓨터활용능력',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searching
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox.square(
                              dimension: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : null,
                  ),
                  onChanged: _changed,
                  onSubmitted: (text) => _search(text.trim()),
                ),
                const SizedBox(height: 8),
                if (!_connected)
                  const NoteLine(
                    icon: Icons.lock_outline,
                    text: '시험 일정을 찾으려면 로그인해 주세요.',
                  )
                else
                  Text(
                    '국가자격 613종목은 Q-Net 공식 일정을, 그 밖의 자주 찾는 자격은 시행 기관 공지를 보여 줍니다.',
                    style: muted,
                  ),
                if (_searchError != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _searchError!,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ],
                if (_query.text.trim().isNotEmpty &&
                    !_searching &&
                    _results.isEmpty &&
                    _searchError == null) ...[
                  const SizedBox(height: 12),
                  Text('찾는 자격증이 없습니다. 이름을 다르게 입력해 보세요.', style: muted),
                ],
                const SizedBox(height: 8),
                for (final item in _results)
                  ListTile(
                    key: ValueKey('certificate-result-${item.id}'),
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                    selected: detail?.summary.id == item.id,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    title: Text(item.name),
                    subtitle: Text(
                      [
                        item.kindLabel,
                        ?item.grade,
                        if (item.field.isNotEmpty) item.field,
                      ].join(' · '),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => widget.selection.select(item),
                  ),
              ],
            ),
          ),
          result: _loading
              ? const SurfaceCard(child: LinearProgressIndicator())
              : _detailError != null
              ? SurfaceCard(child: Text(_detailError!))
              : detail == null
              ? null
              : _detailView(context, detail),
          placeholder: const ResultPlaceholder(
            icon: Icons.event_note_outlined,
            title: '자격증을 고르면 접수·시험·발표 일정과 시험 방법을 보여 드립니다',
          ),
        ),
      ],
    );
  }

  Widget _detailView(BuildContext context, CertificateDetail d) {
    final theme = Theme.of(context);
    final today = (widget.now ?? DateTime.now)();
    final s = d.summary;
    return Column(
      key: ValueKey('certificate-detail-${s.id}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                s.name,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  ToneChip(label: s.kindLabel, tone: AppTone.accent),
                  if (s.grade case final grade?) ToneChip(label: grade),
                  if (s.issuer.isNotEmpty)
                    ToneChip(label: s.issuer, icon: Icons.apartment_outlined),
                  if (s.field.isNotEmpty) ToneChip(label: s.field),
                ],
              ),
              if (d.fee case final fee?) ...[
                const SizedBox(height: 10),
                NoteLine(icon: Icons.payments_outlined, text: '응시료 · $fee'),
              ],
              if (d.eligibilityNote case final note?) ...[
                const SizedBox(height: 6),
                NoteLine(
                  icon: Icons.verified_user_outlined,
                  text: note,
                  color: AppTone.warning.color(context),
                ),
              ],
              if (d.officialUrl case final url?)
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: ExternalLinkButton(
                    url: url,
                    label: '${s.issuer.isEmpty ? '공식 사이트' : s.issuer} 자격 안내',
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('시험 일정', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              CertificateScheduleView(
                name: s.name,
                schedule: d.schedule,
                today: today,
                onAdd: widget.onAddEvents,
              ),
            ],
          ),
        ),
        if (d.method != null ||
            d.subjects.isNotEmpty ||
            d.passCriteria != null ||
            d.trend != null) ...[
          const SizedBox(height: 16),
          SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('시험 과목·방법', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                if (d.method case final method?) SelectableText(method),
                if (d.subjects.isNotEmpty) ...[
                  for (final subject in d.subjects) Text('· $subject'),
                ],
                if (d.passCriteria case final pass?) ...[
                  const SizedBox(height: 8),
                  Text('합격 기준 · $pass'),
                ],
                if (d.trend case final trend?)
                  ExpansionTile(
                    key: const ValueKey('certificate-trend'),
                    tilePadding: EdgeInsets.zero,
                    title: const Text('출제 경향 (Q-Net)'),
                    children: [
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: SelectableText(trend),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ] else if (d.infoFailureReason != null) ...[
          const SizedBox(height: 16),
          const SurfaceCard(
            child: Text('시험 과목·응시료를 불러오지 못했습니다. 공식 사이트에서 확인하세요.'),
          ),
        ],
      ],
    );
  }
}
