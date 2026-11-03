import 'package:flutter/material.dart';

import '../../shared/app_typography.dart';
import '../../shared/widgets/page_header.dart';
import '../../shared/widgets/surface_card.dart';
import '../../shared/widgets/content_scroll_view.dart';
import 'personal_graduation_workspace.dart';
import '../planning/planning_repository.dart';
import '../auth/school_workflow_session.dart';
import 'official_graduation_page.dart';

class GraduationPage extends StatefulWidget {
  const GraduationPage({super.key, this.planning});
  final PlanningRepository? planning;
  @override
  State<GraduationPage> createState() => _GraduationPageState();
}

class _GraduationPageState extends State<GraduationPage> {
  var _tab = '대학 공통';
  bool _personal = false;

  @override
  Widget build(BuildContext context) {
    if (_personal) {
      return PersonalGraduationWorkspace(
        planning: widget.planning,
        onBack: () => setState(() => _personal = false),
      );
    }
    final session = SchoolWorkflowSession.maybeOf(context);
    if (session != null) {
      final planning = widget.planning;
      if (planning != null && planning.isLoading) {
        return const ContentScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PageHeader(title: '학교 검토 자료 기준 졸업요건 감사'),
              LinearProgressIndicator(),
            ],
          ),
        );
      }
      return OfficialGraduationPage(
        auth: session.auth,
        ownerId: session.identity.id,
        profile: planning == null || planning.loadFailed
            ? null
            : planning.profile,
        onPersonal: () => setState(() => _personal = true),
      );
    }
    return ContentScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PageHeader(
            title: '졸업 요건',
            contextLabel: '학교 연동·공식 판정 API 미연결',
            actions: [
              OutlinedButton.icon(
                onPressed: () => setState(() => _personal = true),
                icon: const Icon(Icons.tune, size: 18),
                label: const Text('내 학교·학과 기준 설정'),
              ),
            ],
          ),
          SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '기준 선택',
                  style: TextStyle(
                    fontSize: AppTypography.section,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Text('학교 공식 졸업 판정이 아닙니다. 내 자료는 개인 기준 설정에서 입력하세요.'),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final value in ['대학 공통', '내 교육과정', '학과 기준'])
                      OutlinedButton(
                        onPressed: () => setState(() => _tab = value),
                        style: OutlinedButton.styleFrom(
                          backgroundColor: _tab == value
                              ? Theme.of(context).colorScheme.secondaryContainer
                              : null,
                        ),
                        child: Text(value),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const SurfaceCard(
            child: Text(
              '학교 기준을 가져오는 API가 아직 연결되지 않았습니다. 내 학교·학과 기준 설정에서 개인 자료를 기록하세요.',
            ),
          ),
        ],
      ),
    );
  }
}
