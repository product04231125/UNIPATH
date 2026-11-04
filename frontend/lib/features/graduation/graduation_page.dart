import 'package:flutter/material.dart';

import '../../shared/widgets/feature_page.dart';
import '../../shared/widgets/surface_card.dart';
import '../planning/planning_profile_cta.dart';
import '../planning/planning_repository.dart';
import '../auth/school_workflow_session.dart';
import 'official_graduation_page.dart';

class GraduationPage extends StatelessWidget {
  const GraduationPage({super.key, this.planning, this.onOpenSettings});
  final PlanningRepository? planning;
  final VoidCallback? onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final session = SchoolWorkflowSession.maybeOf(context);
    if (session != null) {
      if (planning != null && planning!.isLoading) {
        return const FeaturePage(
          title: '졸업 요건',
          description: '학교가 검토한 규정과 승인 기록을 비교합니다.',
          body: [LinearProgressIndicator()],
        );
      }
      return OfficialGraduationPage(
        auth: session.auth,
        ownerId: session.identity.id,
        profile: planning == null || planning!.loadFailed
            ? null
            : planning!.profile,
        onOpenSettings: onOpenSettings,
      );
    }
    return FeaturePage(
      title: '졸업 요건',
      description: '학교 기준과 내 기록을 비교합니다.',
      body: [
        if (onOpenSettings != null)
          PlanningProfileSettingsCta(
            onOpenSettings: onOpenSettings!,
            need: PlanningProfileNeed.catalogSchool,
            profile: planning?.profile,
          ),
        const SurfaceCard(child: Text('학교 기준을 가져오는 API가 아직 연결되지 않았습니다.')),
      ],
    );
  }
}
