/// Client-facing roles for the isolated mock. Not an authentication contract.
enum AppRole { user, schoolAdmin, superAdmin }

extension AppRoleLabel on AppRole {
  String get label => switch (this) {
    AppRole.user => '학생',
    AppRole.schoolAdmin => '학교관리자',
    AppRole.superAdmin => '슈퍼관리자',
  };
}
