// GENERATED: scripts/export_school_signup_contracts.py.
import 'admin_application_models.dart' show SchoolAdminApplicant;

abstract interface class SchoolSignupPayload {
  Map<String, Object?> toJson();
}

String _choice(Object? value, List<String> allowed) {
  if (value is! String || !allowed.contains(value)) {
    throw const FormatException('Unknown contract value');
  }
  return value;
}

class SignupNewInstitution implements SchoolSignupPayload {
  const SignupNewInstitution({
    required this.name,
    this.countryCode = "",
    this.officialUrl = "",
  });
  final String name;
  final String countryCode;
  final String officialUrl;
  factory SignupNewInstitution.fromJson(Map<String, dynamic> value) =>
      SignupNewInstitution(
        name: value['name'] as String,
        countryCode: value['country_code'] == null
            ? ""
            : value['country_code'] as String,
        officialUrl: value['official_url'] == null
            ? ""
            : value['official_url'] as String,
      );
  @override
  Map<String, Object?> toJson() => {
    'name': name,
    'country_code': countryCode,
    'official_url': officialUrl,
  };
}

class SchoolAdminSignupDetails implements SchoolSignupPayload {
  const SchoolAdminSignupDetails({
    required this.clientId,
    required this.schoolName,
    this.officialUrl = "",
    required this.position,
    required this.contactEmail,
    required this.reason,
  });
  final String clientId;
  final String schoolName;
  final String officialUrl;
  final String position;
  final String contactEmail;
  final String reason;
  factory SchoolAdminSignupDetails.fromJson(Map<String, dynamic> value) =>
      SchoolAdminSignupDetails(
        clientId: value['client_id'] as String,
        schoolName: value['school_name'] as String,
        officialUrl: value['official_url'] == null
            ? ""
            : value['official_url'] as String,
        position: value['position'] as String,
        contactEmail: value['contact_email'] as String,
        reason: value['reason'] as String,
      );
  @override
  Map<String, Object?> toJson() => {
    'client_id': clientId,
    'school_name': schoolName,
    'official_url': officialUrl,
    'position': position,
    'contact_email': contactEmail,
    'reason': reason,
  };
}

class SchoolAdminSignupApprove implements SchoolSignupPayload {
  const SchoolAdminSignupApprove({
    required this.expectedVersion,
    required this.reviewNote,
    required this.expectedUserVersion,
    required this.identityVerified,
    required this.affiliationVerified,
    this.institutionId,
    this.expectedInstitutionVersion,
    this.newInstitution,
  });
  final int expectedVersion;
  final String reviewNote;
  final int expectedUserVersion;
  final bool identityVerified;
  final bool affiliationVerified;
  final String? institutionId;
  final int? expectedInstitutionVersion;
  final SignupNewInstitution? newInstitution;
  factory SchoolAdminSignupApprove.fromJson(Map<String, dynamic> value) =>
      SchoolAdminSignupApprove(
        expectedVersion: value['expected_version'] as int,
        reviewNote: value['review_note'] as String,
        expectedUserVersion: value['expected_user_version'] as int,
        identityVerified: value['identity_verified'] as bool,
        affiliationVerified: value['affiliation_verified'] as bool,
        institutionId: value['institution_id'] == null
            ? null
            : value['institution_id'] as String,
        expectedInstitutionVersion:
            value['expected_institution_version'] == null
            ? null
            : value['expected_institution_version'] as int,
        newInstitution: value['new_institution'] == null
            ? null
            : SignupNewInstitution.fromJson(
                Map<String, dynamic>.from(value['new_institution'] as Map),
              ),
      );
  @override
  Map<String, Object?> toJson() => {
    'expected_version': expectedVersion,
    'review_note': reviewNote,
    'expected_user_version': expectedUserVersion,
    'identity_verified': identityVerified,
    'affiliation_verified': affiliationVerified,
    'institution_id': institutionId,
    'expected_institution_version': expectedInstitutionVersion,
    'new_institution': newInstitution?.toJson(),
  };
}

class SchoolAdminSignupView implements SchoolSignupPayload {
  const SchoolAdminSignupView({
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
    required this.schoolName,
    required this.officialUrl,
  });
  final String id;
  final String applicantId;
  final String? institutionId;
  final String? institutionName;
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
  final String schoolName;
  final String officialUrl;
  factory SchoolAdminSignupView.fromJson(Map<String, dynamic> value) =>
      SchoolAdminSignupView(
        id: value['id'] as String,
        applicantId: value['applicant_id'] as String,
        institutionId: value['institution_id'] == null
            ? null
            : value['institution_id'] as String,
        institutionName: value['institution_name'] == null
            ? null
            : value['institution_name'] as String,
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
        schoolName: value['school_name'] as String,
        officialUrl: value['official_url'] as String,
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
    'school_name': schoolName,
    'official_url': officialUrl,
  };
}

class SchoolAdminSignupReviewView implements SchoolSignupPayload {
  const SchoolAdminSignupReviewView({
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
    required this.schoolName,
    required this.officialUrl,
    required this.applicant,
  });
  final String id;
  final String applicantId;
  final String? institutionId;
  final String? institutionName;
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
  final String schoolName;
  final String officialUrl;
  final SchoolAdminApplicant applicant;
  factory SchoolAdminSignupReviewView.fromJson(Map<String, dynamic> value) =>
      SchoolAdminSignupReviewView(
        id: value['id'] as String,
        applicantId: value['applicant_id'] as String,
        institutionId: value['institution_id'] == null
            ? null
            : value['institution_id'] as String,
        institutionName: value['institution_name'] == null
            ? null
            : value['institution_name'] as String,
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
        schoolName: value['school_name'] as String,
        officialUrl: value['official_url'] as String,
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
    'school_name': schoolName,
    'official_url': officialUrl,
    'applicant': applicant.toJson(),
  };
}

class SchoolAdminSignupList implements SchoolSignupPayload {
  const SchoolAdminSignupList({required this.items, required this.nextCursor});
  final List<SchoolAdminSignupView> items;
  final String? nextCursor;
  factory SchoolAdminSignupList.fromJson(Map<String, dynamic> value) =>
      SchoolAdminSignupList(
        items: List.unmodifiable(
          (value['items'] as List).map(
            (v) => SchoolAdminSignupView.fromJson(
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

class SchoolAdminSignupReviewList implements SchoolSignupPayload {
  const SchoolAdminSignupReviewList({
    required this.items,
    required this.nextCursor,
  });
  final List<SchoolAdminSignupReviewView> items;
  final String? nextCursor;
  factory SchoolAdminSignupReviewList.fromJson(Map<String, dynamic> value) =>
      SchoolAdminSignupReviewList(
        items: List.unmodifiable(
          (value['items'] as List).map(
            (v) => SchoolAdminSignupReviewView.fromJson(
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
