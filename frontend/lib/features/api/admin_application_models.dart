// GENERATED: scripts/export_admin_application_contracts.py.
abstract interface class AdminApplicationPayload {
  Map<String, Object?> toJson();
}

String _choice(Object? value, List<String> allowed) {
  if (value is! String || !allowed.contains(value)) {
    throw const FormatException('Unknown contract value');
  }
  return value;
}

class SchoolAdminApplicationCreate implements AdminApplicationPayload {
  const SchoolAdminApplicationCreate({
    required this.institutionId,
    required this.clientId,
    required this.position,
    required this.contactEmail,
    required this.reason,
  });
  final String institutionId;
  final String clientId;
  final String position;
  final String contactEmail;
  final String reason;
  factory SchoolAdminApplicationCreate.fromJson(Map<String, dynamic> value) =>
      SchoolAdminApplicationCreate(
        institutionId: value['institution_id'] as String,
        clientId: value['client_id'] as String,
        position: value['position'] as String,
        contactEmail: value['contact_email'] as String,
        reason: value['reason'] as String,
      );
  @override
  Map<String, Object?> toJson() => {
    'institution_id': institutionId,
    'client_id': clientId,
    'position': position,
    'contact_email': contactEmail,
    'reason': reason,
  };
}

class SchoolAdminApplicationCancel implements AdminApplicationPayload {
  const SchoolAdminApplicationCancel({required this.expectedVersion});
  final int expectedVersion;
  factory SchoolAdminApplicationCancel.fromJson(Map<String, dynamic> value) =>
      SchoolAdminApplicationCancel(
        expectedVersion: value['expected_version'] as int,
      );
  @override
  Map<String, Object?> toJson() => {'expected_version': expectedVersion};
}

class SchoolAdminApplicationReject implements AdminApplicationPayload {
  const SchoolAdminApplicationReject({
    required this.expectedVersion,
    required this.reviewNote,
  });
  final int expectedVersion;
  final String reviewNote;
  factory SchoolAdminApplicationReject.fromJson(Map<String, dynamic> value) =>
      SchoolAdminApplicationReject(
        expectedVersion: value['expected_version'] as int,
        reviewNote: value['review_note'] as String,
      );
  @override
  Map<String, Object?> toJson() => {
    'expected_version': expectedVersion,
    'review_note': reviewNote,
  };
}

class SchoolAdminApplicationApprove implements AdminApplicationPayload {
  const SchoolAdminApplicationApprove({
    required this.expectedVersion,
    required this.reviewNote,
    required this.expectedUserVersion,
    required this.identityVerified,
    required this.affiliationVerified,
  });
  final int expectedVersion;
  final String reviewNote;
  final int expectedUserVersion;
  final bool identityVerified;
  final bool affiliationVerified;
  factory SchoolAdminApplicationApprove.fromJson(Map<String, dynamic> value) =>
      SchoolAdminApplicationApprove(
        expectedVersion: value['expected_version'] as int,
        reviewNote: value['review_note'] as String,
        expectedUserVersion: value['expected_user_version'] as int,
        identityVerified: value['identity_verified'] as bool,
        affiliationVerified: value['affiliation_verified'] as bool,
      );
  @override
  Map<String, Object?> toJson() => {
    'expected_version': expectedVersion,
    'review_note': reviewNote,
    'expected_user_version': expectedUserVersion,
    'identity_verified': identityVerified,
    'affiliation_verified': affiliationVerified,
  };
}

class SchoolAdminApplicationView implements AdminApplicationPayload {
  const SchoolAdminApplicationView({
    required this.id,
    required this.applicantId,
    required this.institutionId,
    required this.institutionName,
    required this.clientId,
    required this.position,
    required this.contactEmail,
    required this.reason,
    required this.status,
    required this.version,
    required this.createdAt,
    required this.updatedAt,
    required this.reviewedBy,
    required this.reviewedAt,
    required this.reviewNote,
    required this.identityVerified,
    required this.affiliationVerified,
    required this.grantedScopeId,
  });
  final String id;
  final String applicantId;
  final String institutionId;
  final String institutionName;
  final String clientId;
  final String position;
  final String contactEmail;
  final String reason;
  final String status;
  final int version;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? reviewedBy;
  final DateTime? reviewedAt;
  final String reviewNote;
  final bool identityVerified;
  final bool affiliationVerified;
  final String? grantedScopeId;
  factory SchoolAdminApplicationView.fromJson(Map<String, dynamic> value) =>
      SchoolAdminApplicationView(
        id: value['id'] as String,
        applicantId: value['applicant_id'] as String,
        institutionId: value['institution_id'] as String,
        institutionName: value['institution_name'] as String,
        clientId: value['client_id'] as String,
        position: value['position'] as String,
        contactEmail: value['contact_email'] as String,
        reason: value['reason'] as String,
        status: _choice(value['status'], [
          "pending",
          "approved",
          "rejected",
          "cancelled",
        ]),
        version: value['version'] as int,
        createdAt: DateTime.parse(value['created_at'] as String),
        updatedAt: DateTime.parse(value['updated_at'] as String),
        reviewedBy: value['reviewed_by'] == null
            ? null
            : value['reviewed_by'] as String,
        reviewedAt: value['reviewed_at'] == null
            ? null
            : DateTime.parse(value['reviewed_at'] as String),
        reviewNote: value['review_note'] as String,
        identityVerified: value['identity_verified'] as bool,
        affiliationVerified: value['affiliation_verified'] as bool,
        grantedScopeId: value['granted_scope_id'] == null
            ? null
            : value['granted_scope_id'] as String,
      );
  @override
  Map<String, Object?> toJson() => {
    'id': id,
    'applicant_id': applicantId,
    'institution_id': institutionId,
    'institution_name': institutionName,
    'client_id': clientId,
    'position': position,
    'contact_email': contactEmail,
    'reason': reason,
    'status': status,
    'version': version,
    'created_at': createdAt.toUtc().toIso8601String(),
    'updated_at': updatedAt.toUtc().toIso8601String(),
    'reviewed_by': reviewedBy,
    'reviewed_at': reviewedAt?.toUtc().toIso8601String(),
    'review_note': reviewNote,
    'identity_verified': identityVerified,
    'affiliation_verified': affiliationVerified,
    'granted_scope_id': grantedScopeId,
  };
}

class SchoolAdminApplicant implements AdminApplicationPayload {
  const SchoolAdminApplicant({
    required this.id,
    required this.email,
    required this.displayName,
    required this.role,
    required this.accountStatus,
    required this.version,
  });
  final String id;
  final String email;
  final String displayName;
  final String role;
  final String accountStatus;
  final int version;
  factory SchoolAdminApplicant.fromJson(Map<String, dynamic> value) =>
      SchoolAdminApplicant(
        id: value['id'] as String,
        email: value['email'] as String,
        displayName: value['display_name'] as String,
        role: _choice(value['role'], ["user", "school_admin", "super_admin"]),
        accountStatus: _choice(value['account_status'], [
          "active",
          "suspended",
        ]),
        version: value['version'] as int,
      );
  @override
  Map<String, Object?> toJson() => {
    'id': id,
    'email': email,
    'display_name': displayName,
    'role': role,
    'account_status': accountStatus,
    'version': version,
  };
}

class SchoolAdminApplicationReviewView implements AdminApplicationPayload {
  const SchoolAdminApplicationReviewView({
    required this.id,
    required this.applicantId,
    required this.institutionId,
    required this.institutionName,
    required this.clientId,
    required this.position,
    required this.contactEmail,
    required this.reason,
    required this.status,
    required this.version,
    required this.createdAt,
    required this.updatedAt,
    required this.reviewedBy,
    required this.reviewedAt,
    required this.reviewNote,
    required this.identityVerified,
    required this.affiliationVerified,
    required this.grantedScopeId,
    required this.applicant,
  });
  final String id;
  final String applicantId;
  final String institutionId;
  final String institutionName;
  final String clientId;
  final String position;
  final String contactEmail;
  final String reason;
  final String status;
  final int version;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? reviewedBy;
  final DateTime? reviewedAt;
  final String reviewNote;
  final bool identityVerified;
  final bool affiliationVerified;
  final String? grantedScopeId;
  final SchoolAdminApplicant applicant;
  factory SchoolAdminApplicationReviewView.fromJson(
    Map<String, dynamic> value,
  ) => SchoolAdminApplicationReviewView(
    id: value['id'] as String,
    applicantId: value['applicant_id'] as String,
    institutionId: value['institution_id'] as String,
    institutionName: value['institution_name'] as String,
    clientId: value['client_id'] as String,
    position: value['position'] as String,
    contactEmail: value['contact_email'] as String,
    reason: value['reason'] as String,
    status: _choice(value['status'], [
      "pending",
      "approved",
      "rejected",
      "cancelled",
    ]),
    version: value['version'] as int,
    createdAt: DateTime.parse(value['created_at'] as String),
    updatedAt: DateTime.parse(value['updated_at'] as String),
    reviewedBy: value['reviewed_by'] == null
        ? null
        : value['reviewed_by'] as String,
    reviewedAt: value['reviewed_at'] == null
        ? null
        : DateTime.parse(value['reviewed_at'] as String),
    reviewNote: value['review_note'] as String,
    identityVerified: value['identity_verified'] as bool,
    affiliationVerified: value['affiliation_verified'] as bool,
    grantedScopeId: value['granted_scope_id'] == null
        ? null
        : value['granted_scope_id'] as String,
    applicant: SchoolAdminApplicant.fromJson(
      Map<String, dynamic>.from(value['applicant'] as Map),
    ),
  );
  @override
  Map<String, Object?> toJson() => {
    'id': id,
    'applicant_id': applicantId,
    'institution_id': institutionId,
    'institution_name': institutionName,
    'client_id': clientId,
    'position': position,
    'contact_email': contactEmail,
    'reason': reason,
    'status': status,
    'version': version,
    'created_at': createdAt.toUtc().toIso8601String(),
    'updated_at': updatedAt.toUtc().toIso8601String(),
    'reviewed_by': reviewedBy,
    'reviewed_at': reviewedAt?.toUtc().toIso8601String(),
    'review_note': reviewNote,
    'identity_verified': identityVerified,
    'affiliation_verified': affiliationVerified,
    'granted_scope_id': grantedScopeId,
    'applicant': applicant.toJson(),
  };
}

class SchoolAdminApplicationList implements AdminApplicationPayload {
  const SchoolAdminApplicationList({
    required this.items,
    required this.nextCursor,
  });
  final List<SchoolAdminApplicationView> items;
  final String? nextCursor;
  factory SchoolAdminApplicationList.fromJson(Map<String, dynamic> value) =>
      SchoolAdminApplicationList(
        items: List.unmodifiable(
          (value['items'] as List).map(
            (v) => SchoolAdminApplicationView.fromJson(
              Map<String, dynamic>.from(v as Map),
            ),
          ),
        ),
        nextCursor: value['next_cursor'] == null
            ? null
            : value['next_cursor'] as String,
      );
  @override
  Map<String, Object?> toJson() => {
    'items': items.map((v) => v.toJson()).toList(),
    'next_cursor': nextCursor,
  };
}

class SchoolAdminApplicationReviewList implements AdminApplicationPayload {
  const SchoolAdminApplicationReviewList({
    required this.items,
    required this.nextCursor,
  });
  final List<SchoolAdminApplicationReviewView> items;
  final String? nextCursor;
  factory SchoolAdminApplicationReviewList.fromJson(
    Map<String, dynamic> value,
  ) => SchoolAdminApplicationReviewList(
    items: List.unmodifiable(
      (value['items'] as List).map(
        (v) => SchoolAdminApplicationReviewView.fromJson(
          Map<String, dynamic>.from(v as Map),
        ),
      ),
    ),
    nextCursor: value['next_cursor'] == null
        ? null
        : value['next_cursor'] as String,
  );
  @override
  Map<String, Object?> toJson() => {
    'items': items.map((v) => v.toJson()).toList(),
    'next_cursor': nextCursor,
  };
}
