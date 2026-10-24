import 'package:flutter/material.dart';

import '../../shared/widgets/input_dialog.dart';
import '../records/official_sources_dialog.dart';
import 'app_role.dart';
import 'school_workflow_session.dart';

class SchoolWorkflowActions extends StatelessWidget {
  const SchoolWorkflowActions({super.key});
  @override
  Widget build(BuildContext context) {
    final session = SchoolWorkflowSession.maybeOf(context);
    if (session == null) return const SizedBox.shrink();
    final admin = session.identity.role != AppRole.user;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        OutlinedButton.icon(
          icon: const Icon(Icons.picture_as_pdf_outlined),
          label: Text(admin ? '학교 발급 원본 검토' : '학교 발급 PDF 제출·이력'),
          onPressed: () => showInputDialog<void>(
            context: context,
            builder: (_) => OfficialSourcesDialog(
              auth: session.auth,
              ownerId: session.identity.id,
              admin: admin,
            ),
          ),
        ),
      ],
    );
  }
}
