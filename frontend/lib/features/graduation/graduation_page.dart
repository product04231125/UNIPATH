import 'package:flutter/material.dart';

import '../../shared/widgets/feature_page.dart';
import '../../shared/widgets/surface_card.dart';
import '../planning/planning_profile_cta.dart';
import '../planning/planning_repository.dart';
import '../auth/school_workflow_session.dart';
import '../records/personal_repository_scope.dart';
import 'official_graduation_page.dart';
import 'personal_calculation_page.dart';

class GraduationPage extends StatelessWidget {
  const GraduationPage({super.key, this.planning, this.onOpenSettings});
  final PlanningRepository? planning;
  final VoidCallback? onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final session = SchoolWorkflowSession.maybeOf(context);
    if (session == null) {
      return FeaturePage(
        title: '졸업 요건',
        description: '설정한 학업 기준으로 요건을 확인합니다.',
        body: [
          if (onOpenSettings != null)
            PlanningProfileSettingsCta(
              onOpenSettings: onOpenSettings!,
              need: PlanningProfileNeed.configured,
              profile: planning?.profile,
            ),
          const SurfaceCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('학교 기준을 가져오는 API가 아직 연결되지 않았습니다.'),
              Wrap(spacing: 8, runSpacing: 8, children: [
                OutlinedButton(onPressed: null, child: Text('학교 기준 졸업 감사')),
                OutlinedButton(onPressed: null, child: Text('감사 이력 조회')),
                OutlinedButton(onPressed: null, child: Text('개인 기준 계산·이력')),
              ]),
            ]),
          ),
        ],
      );
    }
    final repo = planning;
    if (repo == null) {
      return OfficialGraduationPage(
        key: ValueKey((session.auth, session.identity.id)),
        auth: session.auth,
        ownerId: session.identity.id,
        profile: null,
        profileLoadFailed: false,
        onOpenSettings: onOpenSettings,
      );
    }
    return AnimatedBuilder(
      animation: repo,
      builder: (context, _) {
        if (repo.isLoading) {
          return const FeaturePage(
            title: '졸업 요건',
            description: '설정한 학업 기준으로 요건을 확인합니다.',
            body: [LinearProgressIndicator()],
          );
        }
        final failed = repo.loadFailed;
        if (failed) {
          return FeaturePage(
            title: '졸업 요건',
            description: '설정한 학업 기준으로 요건을 확인합니다.',
            body: [
              const Text('학업 프로필을 읽지 못했습니다. 다시 불러오거나 설정에서 확인하세요.'),
              TextButton(
                onPressed: repo.load,
                child: const Text('학업 프로필 다시 불러오기'),
              ),
              if (onOpenSettings != null)
                PlanningProfileSettingsCta(
                  onOpenSettings: onOpenSettings!,
                  need: PlanningProfileNeed.configured,
                  profile: null,
                ),
            ],
          );
        }
        final profile = repo.profile;
        if (profile.hasCatalogSchool) {
          return OfficialGraduationPage(
            key: ValueKey((session.auth, session.identity.id, 'official')),
            auth: session.auth,
            ownerId: session.identity.id,
            profile: profile,
            profileLoadFailed: failed,
            onOpenSettings: onOpenSettings,
          );
        }
        if (profile.isConfigured) {
          final calculations =
              PersonalRepositoryScope.read(context)?.calculations;
          if (calculations == null) {
            return FeaturePage(
              title: '졸업 요건',
              description: '설정한 개인 기준으로 계산합니다.',
              body: [
                const Text(
                  '개인 기준 계산을 열려면 로그인된 학생 작업 공간이 필요합니다.',
                ),
                if (onOpenSettings != null) ...[
                  const SizedBox(height: 12),
                  PlanningProfileSettingsCta(
                    onOpenSettings: onOpenSettings!,
                    need: PlanningProfileNeed.configured,
                    profile: profile,
                  ),
                ],
              ],
            );
          }
          return PersonalCalculationPage(
            key: ValueKey((session.identity.id, 'personal-calc')),
            controller: calculations,
            title: '졸업 요건',
            description: '설정한 개인 기준으로 계산합니다.',
            onOpenSettings: onOpenSettings,
          );
        }
        return FeaturePage(
          title: '졸업 요건',
          description: '설정한 학업 기준으로 요건을 확인합니다.',
          body: [
            if (onOpenSettings != null)
              PlanningProfileSettingsCta(
                onOpenSettings: onOpenSettings!,
                need: PlanningProfileNeed.configured,
                profile: profile,
              )
            else
              const Text('설정에서 학업 프로필을 등록하면 이 화면에서 사용합니다.'),
          ],
        );
      },
    );
  }
}
