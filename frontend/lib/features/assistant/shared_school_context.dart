import '../planning/planning_repository.dart';
import 'assistant_api.dart';
import 'assistant_conversation.dart';

SchoolQueryContext schoolContext(PlanningProfile profile) => SchoolQueryContext(
  institution: profile.school.trim().isEmpty ? null : profile.school.trim(),
  department: profile.department.trim().isEmpty
      ? null
      : profile.department.trim(),
  admissionYear: profile.admissionYear,
  track: profile.track,
);

/// Synchronizes only confirmed, successfully saved profile values, not messages.
class SharedSchoolContext {
  SharedSchoolContext(this.repository, this.conversation) {
    repository.addListener(_sync);
    _sync();
  }
  final PlanningRepository repository;
  final AssistantConversation conversation;
  void _sync() {
    if (!repository.isLoading && !repository.loadFailed) {
      conversation.setContext(schoolContext(repository.profile));
    }
  }

  Future<void> save(SchoolQueryContext value) => repository.saveSchoolContext(
    school: value.institution,
    department: value.department,
    admissionYear: value.admissionYear,
    track: value.track,
  );
  void dispose() => repository.removeListener(_sync);
}
