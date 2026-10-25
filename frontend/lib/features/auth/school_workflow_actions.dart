import 'package:flutter/material.dart';

import '../../shared/widgets/input_dialog.dart';
import '../records/official_sources_dialog.dart';
import '../records/official_records_dialog.dart';
import '../graduation/school_document_search_dialog.dart';
import '../admin/school_knowledge_review_dialog.dart';
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
        if (admin)
          OutlinedButton.icon(
            icon: const Icon(Icons.rate_review_outlined),
            label: const Text('학교 문서 근거 검토'),
            onPressed: () => showInputDialog<void>(
              context: context,
              builder: (_) => SchoolKnowledgeReviewDialog(
                auth: session.auth,
                ownerId: session.identity.id,
              ),
            ),
          ),
        OutlinedButton.icon(
          icon: const Icon(Icons.manage_search),
          label: const Text('학교 문서 검색·근거'),
          onPressed: () => showInputDialog<void>(
            context: context,
            builder: (_) => SchoolDocumentSearchDialog(
              auth: session.auth,
              ownerId: session.identity.id,
            ),
          ),
        ),
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
        OutlinedButton.icon(
          icon: const Icon(Icons.fact_check_outlined),
          label: Text(admin ? '학교 확인 학생 기록 검토' : '학교 확인 학생 기록'),
          onPressed: () => showInputDialog<void>(
            context: context,
            builder: (_) => OfficialRecordsDialog(
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
