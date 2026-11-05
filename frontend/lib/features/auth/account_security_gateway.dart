/// All operations belong to one captured owner and login generation.
/// A session check does not prove that an uncertain mutation did or did not run.
enum AccountSessionStatus { active, expired, changed }

enum AccountSecurityOutcome {
  passwordChanged,
  allSessionsEnded,
  expired,
  changed,
}

abstract class AccountSecurityGateway {
  Future<void> changePassword({
    required String oldPassword,
    required String newPassword,
  });
  Future<void> logoutAll();
  Future<AccountSessionStatus> checkSession();
}
