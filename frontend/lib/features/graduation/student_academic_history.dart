import 'package:flutter/material.dart';

import '../admin/academic_credit_preview.dart';
import '../admin/academic_requirement_content.dart';
import '../api/student_academic_api.dart';

Future<void> showStudentAcademicHistory(
  BuildContext context,
  StudentAcademicApi api,
) => showDialog<void>(
  context: context,
  builder: (context) => Dialog(
    child: SizedBox(
      width: 900,
      height: 700,
      child: StudentAcademicHistory(api: api),
    ),
  ),
);

class StudentAcademicHistory extends StatefulWidget {
  const StudentAcademicHistory({super.key, required this.api});
  final StudentAcademicApi api;
  @override
  State<StudentAcademicHistory> createState() => _StudentAcademicHistoryState();
}

class _StudentAcademicHistoryState extends State<StudentAcademicHistory> {
  late Future<List<AcademicStudentHistoryItem>> _history;
  final Map<String, Future<AcademicStudentRequirements>> _snapshots = {};
  @override
  void initState() {
    super.initState();
    _history = widget.api.history();
  }

  Widget _response(AcademicStudentDocument doc, AcademicStudentItem item) {
    final response = doc.response(item.id);
    return ListTile(
      title: Text(item.text),
      subtitle: Text(
        [
          response?.value == null
              ? '미확인'
              : response!.value!
              ? 'O'
              : 'X',
          ...?response?.records.map((r) => r.title),
        ].join(' · '),
      ),
    );
  }

  Iterable<Widget> _groups(
    AcademicStudentDocument doc,
    List<AcademicStudentGroup> groups,
  ) sync* {
    for (final group in groups) {
      yield Padding(
        padding: const EdgeInsets.all(8),
        child: Text('${group.label} · ${group.choiceLabel}'),
      );
      yield* group.items.map((i) => _response(doc, i));
      yield* _groups(doc, group.groups);
    }
  }

  @override
  Widget build(BuildContext context) => Material(
    type: MaterialType.transparency,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          title: const Text('적용 기준·내 확인 이력'),
          trailing: IconButton(
            tooltip: '닫기',
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        Expanded(
          child: FutureBuilder<List<AcademicStudentHistoryItem>>(
            future: _history,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Column(
                  children: [
                    const Text('이력을 읽지 못했습니다.'),
                    TextButton(
                      onPressed: () =>
                          setState(() => _history = widget.api.history()),
                      child: const Text('다시 불러오기'),
                    ),
                  ],
                );
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.data!.isEmpty) {
                return const Center(child: Text('적용한 기준 이력이 없습니다.'));
              }
              return ListView(
                children: [
                  for (final item in snapshot.data!)
                    ExpansionTile(
                      title: Text(
                        '${item.createdAt.toLocal().toString().split('.').first} · ${item.count}개 요건${item.active ? ' · 현재 적용' : ''}',
                      ),
                      onExpansionChanged: (expanded) {
                        if (expanded) {
                          setState(
                            () => _snapshots.putIfAbsent(
                              item.id,
                              () => widget.api.historical(item.id),
                            ),
                          );
                        }
                      },
                      children: [
                        if (_snapshots[item.id] case final future?)
                          FutureBuilder<AcademicStudentRequirements>(
                            future: future,
                            builder: (context, data) {
                              if (data.hasError) {
                                return const Text('이 기준의 상세 내용을 읽지 못했습니다.');
                              }
                              if (!data.hasData) {
                                return const LinearProgressIndicator();
                              }
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  for (final doc in data.data!.documents) ...[
                                    Padding(
                                      padding: const EdgeInsets.all(12),
                                      child: Text(
                                        '${doc.name} · ${doc.revision}판',
                                      ),
                                    ),
                                    if (doc.kind == 'checklist')
                                      ...doc.lines.map(
                                        (i) => _response(doc, i),
                                      ),
                                    if (doc.kind == 'certification')
                                      ..._groups(doc, doc.groups),
                                    if (doc.kind == 'credit_table')
                                      AcademicCreditPreview(
                                        grid: creditGridFromAcademic(
                                          doc.content,
                                        ),
                                      ),
                                  ],
                                ],
                              );
                            },
                          ),
                      ],
                    ),
                ],
              );
            },
          ),
        ),
      ],
    ),
  );
}
