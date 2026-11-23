import '../../shared/app_tones.dart';
import 'planning_repository.dart';

/// One color per event category across the calendar, week strip and lists.
extension PlanningEventCategoryTone on PlanningEventCategory {
  AppTone get tone => switch (this) {
    PlanningEventCategory.academic => AppTone.info,
    PlanningEventCategory.personal => AppTone.success,
    PlanningEventCategory.activity => AppTone.accent,
    PlanningEventCategory.deadline => AppTone.danger,
  };
}
