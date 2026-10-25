import 'package:flutter/material.dart';

import '../../shared/widgets/anchored_select_field.dart';

import '../auth/app_role.dart';
import '../auth/school_workflow_session.dart';
import 'school_admin_applications_dialog.dart';
import 'school_signup_panel.dart';

/// The inbox contains only applications returned by the existing review API.
class SchoolAdminApplicationInbox extends StatefulWidget {
  const SchoolAdminApplicationInbox({super.key, this.schools = const []});
  final List<SelectOption<String>> schools;

  @override
  State<SchoolAdminApplicationInbox> createState() =>
      _SchoolAdminApplicationInboxState();
}

class _SchoolAdminApplicationInboxState
    extends State<SchoolAdminApplicationInbox> {
  bool _initial = false;

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
        const Text('등록 학교 권한 신청과 최초 가입·미등록 학교 신청을 구분해 심사합니다.'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ChoiceChip(
              label: const Text('등록 학교 권한 신청'),
              selected: !_initial,
              onSelected: (_) => setState(() => _initial = false),
            ),
            ChoiceChip(
              label: const Text('최초·미등록 학교 접수'),
              selected: _initial,
              onSelected: (_) => setState(() => _initial = true),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (_initial)
          SchoolSignupPanel(
            key: ValueKey(session.identity),
            auth: session.auth,
            ownerId: session.identity.id,
            admin: true,
            inline: true,
          )
        else
          SchoolAdminApplicationsDialog(
            key: ValueKey(session.identity),
            auth: session.auth,
            identity: session.identity,
            inline: true,
            reviewSchools: widget.schools,
          ),
      ],
    );
  }
}
