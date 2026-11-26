import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../shared/widgets/anchored_select_field.dart';
import '../../shared/widgets/field_label.dart';
import '../../shared/widgets/responsive_panels.dart';
import '../records/personal_record_repository.dart';

class _Clause {
  _Clause(Map<String, dynamic> value)
    : department = value['department_id'] as String? ?? '',
      allTracks = value['track_mode'] != 'selected',
      tracks = List<String>.from(value['track_ids'] as List? ?? []),
      from = TextEditingController(text: '${value['admission_from'] ?? ''}'),
      to = TextEditingController(text: '${value['admission_to'] ?? ''}');
  final id = PersonalRecord.newId();
  String department;
  bool allTracks;
  final List<String> tracks;
  final TextEditingController from, to;
  void dispose() {
    from.dispose();
    to.dispose();
  }

  String? get error {
    if (from.text.isEmpty && to.text.isEmpty) return null;
    final a = int.tryParse(from.text), b = int.tryParse(to.text);
    return a == null || b == null || a < 1000 || b > 9999 || a > b
        ? '입학연도 시작·종료를 네 자리로 입력하고 순서를 확인하세요.'
        : null;
  }

  Map<String, Object?> toJson() => {
    'department_id': department.isEmpty ? null : department,
    'admission_from': int.tryParse(from.text),
    'admission_to': int.tryParse(to.text),
    'track_mode': allTracks ? 'all' : 'selected',
    'track_ids': allTracks ? <String>[] : tracks,
  };
}

/// The same scope meaning is used by curriculum and graduation administration.
class AcademicScopeForm extends StatefulWidget {
  const AcademicScopeForm({
    super.key,
    required this.initial,
    required this.resetKey,
    required this.departments,
    required this.tracks,
    required this.enabled,
    required this.onChanged,
  });
  final Map<String, dynamic> initial;
  final String resetKey;
  final List<SelectOption<String>> departments;
  final List<Map<String, dynamic>> tracks;
  final bool enabled;
  final VoidCallback onChanged;
  @override
  State<AcademicScopeForm> createState() => AcademicScopeFormState();
}

class AcademicScopeFormState extends State<AcademicScopeForm> {
  final List<_Clause> _clauses = [];
  late String _initial;
  String get _fingerprint => jsonEncode([
    for (final clause in _clauses)
      {
        ...clause.toJson(),
        'from_text': clause.from.text,
        'to_text': clause.to.text,
      },
  ]);
  bool get dirty => _fingerprint != _initial;
  Map<String, Object?> get value {
    for (final clause in _clauses) {
      if (clause.error != null) throw FormatException(clause.error!);
      if (!clause.allTracks && clause.tracks.isEmpty) {
        throw const FormatException('적용할 이수 경로를 하나 이상 선택하세요.');
      }
    }
    return {
      'clauses': [for (final clause in _clauses) clause.toJson()],
    };
  }

  @override
  void initState() {
    super.initState();
    _reset();
  }

  void _changed() {
    setState(() {});
    widget.onChanged();
  }

  void _reset() {
    for (final clause in _clauses) {
      clause.dispose();
    }
    _clauses.clear();
    for (final raw in widget.initial['clauses'] as List? ?? []) {
      _add(Map<String, dynamic>.from(raw as Map));
    }
    _initial = _fingerprint;
  }

  void _add(Map<String, dynamic> input) {
    final clause = _Clause(input);
    clause.from.addListener(_changed);
    clause.to.addListener(_changed);
    _clauses.add(clause);
  }

  @override
  void didUpdateWidget(covariant AcademicScopeForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.resetKey != widget.resetKey) _reset();
  }

  @override
  void dispose() {
    for (final clause in _clauses) {
      clause.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text('적용 대상', style: Theme.of(context).textTheme.titleSmall),
      const Text('한 대상 안의 조건은 함께 적용합니다. 대상을 여러 개 추가하면 그중 하나에 해당하는 경우 적용합니다.'),
      if (_clauses.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Text('적용 대상이 없습니다. 학교 전체 또는 해당 학과·입학연도·경로를 추가하세요.'),
        ),
      for (final clause in _clauses)
        Padding(
          key: ValueKey(clause.id),
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AnchoredSelectField<String>(
                externalLabel: true,
                label: '적용 학과',
                value: clause.department,
                options: [
                  const SelectOption('', '학교 전체'),
                  ...widget.departments,
                  if (clause.department.isNotEmpty &&
                      !widget.departments.any(
                        (d) => d.value == clause.department,
                      ))
                    SelectOption(clause.department, '이전에 선택한 학과 · 다시 확인'),
                ],
                onChanged: (id) {
                  if (widget.enabled) {
                    clause.department = id;
                    _changed();
                  }
                },
              ),
              const SizedBox(height: 8),
              ResponsivePanels(
                children: [
                  FieldLabel(
                    label: '입학연도 시작 · 비우면 제한 없음',
                    child: TextField(
                      controller: clause.from,
                      enabled: widget.enabled,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(4),
                      ],
                      decoration: InputDecoration(errorText: clause.error),
                    ),
                  ),
                  FieldLabel(
                    label: '입학연도 종료',
                    child: TextField(
                      controller: clause.to,
                      enabled: widget.enabled,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(4),
                      ],
                    ),
                  ),
                ],
              ),
              CheckboxListTile(
                value: clause.allTracks,
                contentPadding: EdgeInsets.zero,
                title: const Text('모든 이수 경로에 적용'),
                onChanged: !widget.enabled
                    ? null
                    : (value) {
                        clause.allTracks = value ?? true;
                        _changed();
                      },
              ),
              if (!clause.allTracks)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final track in widget.tracks)
                      FilterChip(
                        label: Text(
                          '${track['name']}${track['inactive_at'] == null ? '' : ' · 사용 중지'}',
                        ),
                        selected: clause.tracks.contains(track['id']),
                        onSelected:
                            !widget.enabled ||
                                track['inactive_at'] != null &&
                                    !clause.tracks.contains(track['id'])
                            ? null
                            : (selected) {
                                if (selected) {
                                  clause.tracks.add(track['id'] as String);
                                } else {
                                  clause.tracks.remove(track['id']);
                                }
                                _changed();
                              },
                      ),
                    if (widget.tracks.isEmpty)
                      const Text('학교·학과 메뉴에서 이수 경로를 먼저 등록하세요.'),
                  ],
                ),
              if (widget.enabled)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: () {
                      setState(() {
                        _clauses.remove(clause);
                        clause.dispose();
                      });
                      widget.onChanged();
                    },
                    child: const Text('적용 대상 제거'),
                  ),
                ),
            ],
          ),
        ),
      if (widget.enabled)
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton(
            onPressed: () {
              setState(() => _add({}));
              widget.onChanged();
            },
            child: const Text('적용 대상 추가'),
          ),
        ),
    ],
  );
}
