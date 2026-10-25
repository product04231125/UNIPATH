import 'package:flutter/material.dart';

import '../../shared/widgets/anchored_select_field.dart';

import '../auth/app_role.dart';
import '../auth/school_workflow_session.dart';
import 'school_admin_applications_dialog.dart';

/// The inbox contains only applications returned by the existing review API.
class SchoolAdminApplicationInbox extends StatelessWidget {
  const SchoolAdminApplicationInbox({super.key, this.schools = const []});
  final List<SelectOption<String>> schools;

  @override
  Widget build(BuildContext context) {
    final session = SchoolWorkflowSession.maybeOf(context);
    if (session == null) {
      return const Text('실제 슈퍼관리자 계정으로 로그인하면 서버의 접수 목록을 확인할 수 있습니다.');
    }
    if (session.identity.role != AppRole.superAdmin) {
      return const Text('슈퍼관리자만 신청을 심사할 수 있습니다.');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          '현재 접수 목록에는 등록된 학교의 관리 권한 신청만 표시됩니다. 회원가입에서 작성한 최초 학교 신청은 아직 접수되지 않습니다.',
        ),
        const SizedBox(height: 16),
        SchoolAdminApplicationsDialog(
          key: ValueKey(session.identity),
          auth: session.auth,
          identity: session.identity,
          inline: true,
          reviewSchools: schools,
        ),
      ],
    );
  }
}
