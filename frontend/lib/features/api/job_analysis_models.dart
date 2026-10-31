// GENERATED: scripts/export_job_analysis_contracts.py.
// Personal evidence is unverified. No persistence, network or UI effects.
abstract interface class JobAnalysisPayload {
  Map<String, Object?> toJson();
}

Object _constant(Object? value, Object expected) {
  if (value != expected) {
    throw const FormatException('Unexpected contract constant');
  }
  return expected;
}

String _choice(Object? value, List<String> allowed) {
  if (value is! String || !allowed.contains(value)) {
    throw const FormatException('Unknown contract value');
  }
  return value;
}

class PersonalEvidenceSelection implements JobAnalysisPayload {
  const PersonalEvidenceSelection({
    required this.kind,
    required this.recordId,
    required this.expectedVersion,
  });
  final String kind;
  final String recordId;
  final int expectedVersion;
  factory PersonalEvidenceSelection.fromJson(Map<String, dynamic> value) =>
      PersonalEvidenceSelection(
        kind: _choice(value['kind'], [
          "course",
          "activity",
          "experience",
          "credential",
          "achievement",
        ]),
        recordId: value['record_id'] as String,
        expectedVersion: value['expected_version'] as int,
      );
  @override
  Map<String, Object?> toJson() => {
    'kind': kind,
    'record_id': recordId,
    'expected_version': expectedVersion,
  };
}

class PersonalizationRequest implements JobAnalysisPayload {
  const PersonalizationRequest({this.records = const []});
  final List<PersonalEvidenceSelection> records;
  factory PersonalizationRequest.fromJson(Map<String, dynamic> value) =>
      PersonalizationRequest(
        records: value['records'] == null
            ? const []
            : List.unmodifiable(
                (value['records'] as List).map(
                  (v) => PersonalEvidenceSelection.fromJson(
                    Map<String, dynamic>.from(v as Map),
                  ),
                ),
              ),
      );
  @override
  Map<String, Object?> toJson() => {
    'records': records.map((v) => v.toJson()).toList(),
  };
}

class PersonalEvidence implements JobAnalysisPayload {
  const PersonalEvidence({
    required this.kind,
    required this.recordId,
    required this.version,
    this.origin = "personal",
    this.official = false,
    required this.title,
    required this.text,
    required this.truncated,
  });
  final String kind;
  final String recordId;
  final int version;
  final String origin;
  final bool official;
  final String title;
  final String text;
  final bool truncated;
  factory PersonalEvidence.fromJson(Map<String, dynamic> value) =>
      PersonalEvidence(
        kind: _choice(value['kind'], [
          "course",
          "activity",
          "experience",
          "credential",
          "achievement",
        ]),
        recordId: value['record_id'] as String,
        version: value['version'] as int,
        origin: value['origin'] == null
            ? "personal"
            : _constant(value['origin'], "personal") as String,
        official: value['official'] == null
            ? false
            : _constant(value['official'], false) as bool,
        title: value['title'] as String,
        text: value['text'] as String,
        truncated: value['truncated'] as bool,
      );
  @override
  Map<String, Object?> toJson() => {
    'kind': kind,
    'record_id': recordId,
    'version': version,
    'origin': origin,
    'official': official,
    'title': title,
    'text': text,
    'truncated': truncated,
  };
}

class PersonalizationContext implements JobAnalysisPayload {
  const PersonalizationContext({required this.records, this.official = false});
  final List<PersonalEvidence> records;
  final bool official;
  factory PersonalizationContext.fromJson(Map<String, dynamic> value) =>
      PersonalizationContext(
        records: List.unmodifiable(
          (value['records'] as List).map(
            (v) =>
                PersonalEvidence.fromJson(Map<String, dynamic>.from(v as Map)),
          ),
        ),
        official: value['official'] == null
            ? false
            : _constant(value['official'], false) as bool,
      );
  @override
  Map<String, Object?> toJson() => {
    'records': records.map((v) => v.toJson()).toList(),
    'official': official,
  };
}

class JobAnalysisRequest implements JobAnalysisPayload {
  const JobAnalysisRequest({
    this.records = const [],
    required this.postingText,
  });
  final List<PersonalEvidenceSelection> records;
  final String postingText;
  factory JobAnalysisRequest.fromJson(Map<String, dynamic> value) =>
      JobAnalysisRequest(
        records: value['records'] == null
            ? const []
            : List.unmodifiable(
                (value['records'] as List).map(
                  (v) => PersonalEvidenceSelection.fromJson(
                    Map<String, dynamic>.from(v as Map),
                  ),
                ),
              ),
        postingText: value['posting_text'] as String,
      );
  @override
  Map<String, Object?> toJson() => {
    'records': records.map((v) => v.toJson()).toList(),
    'posting_text': postingText,
  };
}

class PostingEvidence implements JobAnalysisPayload {
  const PostingEvidence({
    required this.start,
    required this.end,
    required this.excerpt,
  });
  final int start;
  final int end;
  final String excerpt;
  factory PostingEvidence.fromJson(Map<String, dynamic> value) =>
      PostingEvidence(
        start: value['start'] as int,
        end: value['end'] as int,
        excerpt: value['excerpt'] as String,
      );
  @override
  Map<String, Object?> toJson() => {
    'start': start,
    'end': end,
    'excerpt': excerpt,
  };
}

class PersonalEvidenceCitation implements JobAnalysisPayload {
  const PersonalEvidenceCitation({
    required this.kind,
    required this.recordId,
    required this.version,
    required this.excerpt,
  });
  final String kind;
  final String recordId;
  final int version;
  final String excerpt;
  factory PersonalEvidenceCitation.fromJson(Map<String, dynamic> value) =>
      PersonalEvidenceCitation(
        kind: _choice(value['kind'], [
          "course",
          "activity",
          "experience",
          "credential",
          "achievement",
        ]),
        recordId: value['record_id'] as String,
        version: value['version'] as int,
        excerpt: value['excerpt'] as String,
      );
  @override
  Map<String, Object?> toJson() => {
    'kind': kind,
    'record_id': recordId,
    'version': version,
    'excerpt': excerpt,
  };
}

class JobRequirementComparison implements JobAnalysisPayload {
  const JobRequirementComparison({
    required this.requirementId,
    required this.priority,
    required this.requirement,
    required this.postingEvidence,
    required this.status,
    this.personalEvidence = const [],
    required this.explanation,
  });
  final String requirementId;
  final String priority;
  final String requirement;
  final PostingEvidence postingEvidence;
  final String status;
  final List<PersonalEvidenceCitation> personalEvidence;
  final String explanation;
  factory JobRequirementComparison.fromJson(Map<String, dynamic> value) =>
      JobRequirementComparison(
        requirementId: value['requirement_id'] as String,
        priority: _choice(value['priority'], ["required", "preferred"]),
        requirement: value['requirement'] as String,
        postingEvidence: PostingEvidence.fromJson(
          Map<String, dynamic>.from(value['posting_evidence'] as Map),
        ),
        status: _choice(value['status'], [
          "supported",
          "partially_supported",
          "insufficient_evidence",
        ]),
        personalEvidence: value['personal_evidence'] == null
            ? const []
            : List.unmodifiable(
                (value['personal_evidence'] as List).map(
                  (v) => PersonalEvidenceCitation.fromJson(
                    Map<String, dynamic>.from(v as Map),
                  ),
                ),
              ),
        explanation: value['explanation'] as String,
      );
  @override
  Map<String, Object?> toJson() => {
    'requirement_id': requirementId,
    'priority': priority,
    'requirement': requirement,
    'posting_evidence': postingEvidence.toJson(),
    'status': status,
    'personal_evidence': personalEvidence.map((v) => v.toJson()).toList(),
    'explanation': explanation,
  };
}

class JobAnalysisResponse implements JobAnalysisPayload {
  const JobAnalysisResponse({
    required this.analysisId,
    required this.status,
    required this.reason,
    this.official = false,
    this.comparisons = const [],
    this.missingFields = const [],
  });
  final String analysisId;
  final String status;
  final String reason;
  final bool official;
  final List<JobRequirementComparison> comparisons;
  final List<String> missingFields;
  factory JobAnalysisResponse.fromJson(Map<String, dynamic> value) =>
      JobAnalysisResponse(
        analysisId: value['analysis_id'] as String,
        status: _choice(value['status'], [
          "completed",
          "needs_user_input",
          "not_configured",
          "insufficient_evidence",
          "failed",
        ]),
        reason: _choice(value['reason'], [
          "compared_with_personal_evidence",
          "personal_records_required",
          "analyzer_not_configured",
          "no_requirements_found",
          "analysis_failed",
        ]),
        official: value['official'] == null
            ? false
            : _constant(value['official'], false) as bool,
        comparisons: value['comparisons'] == null
            ? const []
            : List.unmodifiable(
                (value['comparisons'] as List).map(
                  (v) => JobRequirementComparison.fromJson(
                    Map<String, dynamic>.from(v as Map),
                  ),
                ),
              ),
        missingFields: value['missing_fields'] == null
            ? const []
            : List.unmodifiable(
                (value['missing_fields'] as List).map(
                  (v) => _constant(v, "records") as String,
                ),
              ),
      );
  @override
  Map<String, Object?> toJson() => {
    'analysis_id': analysisId,
    'status': status,
    'reason': reason,
    'official': official,
    'comparisons': comparisons.map((v) => v.toJson()).toList(),
    'missing_fields': missingFields.map((v) => v).toList(),
  };
}
