import 'package:flutter/widgets.dart';

import 'personal_record_repository.dart';
import 'portfolio/portfolio_workspace_repository.dart';
import 'personal_workspace_importer.dart';

typedef PersonalRepositoryFactory = PersonalRecordRepository Function(
  PersonalRecordKind kind,
);

/// Factories belong to one mounted authenticated workspace, never a global
/// mutable account. Async forms retain their original repository and identity.
class PersonalRepositoryScope extends InheritedWidget {
  const PersonalRepositoryScope({
    super.key,
    required super.child,
    required this.records,
    required this.portfolio,
    this.importer,
  });
  final PersonalRepositoryFactory records;
  final PortfolioWorkspaceRepository Function() portfolio;
  final PersonalWorkspaceImporter? importer;
  static PersonalRepositoryScope? read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<PersonalRepositoryScope>();
  @override
  bool updateShouldNotify(PersonalRepositoryScope oldWidget) => false;
}
