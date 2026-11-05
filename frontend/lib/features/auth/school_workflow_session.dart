import 'package:flutter/widgets.dart';

import 'auth_api.dart';

/// Only real authenticated workspaces expose school workflow capabilities.
class SchoolWorkflowSession extends InheritedWidget {
  const SchoolWorkflowSession({
    super.key,
    required this.auth,
    required this.identity,
    required super.child,
  });
  final AuthApi auth;
  final AuthIdentity identity;
  static SchoolWorkflowSession? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SchoolWorkflowSession>();
  @override
  bool updateShouldNotify(SchoolWorkflowSession oldWidget) =>
      oldWidget.identity != identity || oldWidget.auth != auth;
}
