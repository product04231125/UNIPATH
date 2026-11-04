import 'package:flutter/material.dart';

import '../../shared/widgets/feature_page.dart';
import '../../shared/widgets/surface_card.dart';
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
        return const FeaturePage(
          title: '학교 검토 자료 기준 졸업요건 감사',
          description: '학교가 검토한 규정과 승인 기록을 비교합니다.',
          body: [LinearProgressIndicator()],
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
    return FeaturePage(
      title: '졸업 요건',
      description: '학교 기준과 내 기록을 비교합니다.',
      body: [
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: () => setState(() => _personal = true),
            icon: const Icon(Icons.tune, size: 18),
            label: const Text('내 학교·학과 기준 설정'),
          ),
        ),
        const SurfaceCard(child: Text('학교 기준을 가져오는 API가 아직 연결되지 않았습니다.')),
      ],
    );
  }
}
