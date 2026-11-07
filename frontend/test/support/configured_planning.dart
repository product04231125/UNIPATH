import 'package:university_path_frontend/features/planning/planning_repository.dart';

Future<void> seedConfiguredPlanning() async {
  final repository = PlanningRepository();
  await repository.load();
  await repository.saveProfile(
    const PlanningProfile(
      school: '합성 대학',
      department: '합성 학과',
      admissionYear: 2026,
    ),
  );
}
