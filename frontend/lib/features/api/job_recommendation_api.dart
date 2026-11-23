import 'dart:convert';
import 'dart:typed_data';

import '../auth/auth_api.dart';
import 'job_analysis_models.dart';

class RecommendationDocument {
  const RecommendationDocument(this.filename, this.bytes);
  final String filename;
  final Uint8List bytes;
  Map<String, Object?> toJson() => {
    'filename': filename,
    'content_base64': base64Encode(bytes),
  };
}

enum RecommendationAcademicStage { year1, year2, year3, year4, graduate }

class JobRecommendationRequest {
  const JobRecommendationRequest({
    required this.keyword,
    required this.region,
    this.categoryCodes = const [],
    this.documents = const [],
    this.records = const [],
    this.academicStage,
    required this.consent,
  });
  final String keyword, region;
  final List<String> categoryCodes;
  final List<RecommendationDocument> documents;
  final List<PersonalEvidenceSelection> records;
  final bool consent;
  final RecommendationAcademicStage? academicStage;
  Map<String, Object?> toJson() => {
    'keyword': keyword,
    if (categoryCodes.isNotEmpty) 'category_codes': categoryCodes,
    'region': region,
    'documents': documents.map((d) => d.toJson()).toList(),
    'records': records.map((r) => r.toJson()).toList(),
    'external_processing_consent': consent,
    if (academicStage != null) 'academic_stage': academicStage!.name,
    'limit': 3,
  };
}

Map<String, dynamic> _map(Object? value) =>
    Map<String, dynamic>.from(value as Map);
List<T> _rows<T>(Object? value, T Function(Map<String, dynamic>) parse) =>
    List.unmodifiable(((value ?? const []) as List).map((v) => parse(_map(v))));
List<String> _strings(Object? value) =>
    List<String>.from((value ?? const []) as List);

List<String> _guidanceSentences(Object? value) =>
    value == null ? const [] : _strings(_map(value)['sentences']);

class JobCategory {
  JobCategory.fromJson(Map<String, dynamic> json)
    : code = json['code'] as String,
      name = json['name'] as String,
      children = _rows(json['children'], JobCategory.fromJson);

  final String code, name;
  final List<JobCategory> children;
}

class RecommendationCitation {
  RecommendationCitation.fromJson(Map<String, dynamic> json)
    : kind = json['kind'] as String,
      id = json['record_id'] as String,
      version = json['version'] as int,
      excerpt = json['excerpt'] as String;
  final String kind, id, excerpt;
  final int version;
}

class RecommendationComparison {
  RecommendationComparison.fromJson(Map<String, dynamic> json)
    : requirement = json['requirement'] as String,
      priority = json['priority'] as String,
      status = json['status'] as String,
      postingExcerpt = _map(json['posting_evidence'])['excerpt'] as String,
      explanation = json['explanation'] as String,
      evidence = _rows(
        json['personal_evidence'],
        RecommendationCitation.fromJson,
      );
  final String requirement, priority, status, postingExcerpt, explanation;
  final List<RecommendationCitation> evidence;
}

class RecommendationPosting {
  RecommendationPosting.fromJson(Map<String, dynamic> json)
    : source = json['source'] as String,
      id = json['source_id'] as String,
      title = json['title'] as String,
      company = json['company'] as String,
      url = json['url'] as String,
      location = json['location'] as String,
      expiresAt = DateTime.tryParse(json['expires_at'] as String? ?? ''),
      closingLabel = json['closing_label'] as String? ?? '확인 필요';
  final String source, id, title, company, url, location, closingLabel;

  /// Parsed `expires_at`; UTC when the server sent an offset, otherwise wall-clock time.
  final DateTime? expiresAt;
  String get key => '$source/$id';
}

class RecommendationItem {
  RecommendationItem.fromJson(Map<String, dynamic> json)
    : posting = RecommendationPosting.fromJson(_map(json['posting'])),
      status = json['analysis_status'] as String,
      scope = json['analysis_scope'] as String,
      comparisons = _rows(
        json['comparisons'],
        RecommendationComparison.fromJson,
      ),
      warnings = _strings(json['warnings']),
      guidanceSentences = _guidanceSentences(json['stage_guidance']),
      failureReason = json['failure_reason'] as String?;
  final RecommendationPosting posting;
  final String status, scope;

  /// Fixed server code for a failed comparison, e.g. `posting_quote`.
  final String? failureReason;
  final List<RecommendationComparison> comparisons;
  final List<String> warnings;
  final List<String> guidanceSentences;
}

class RecommendedJob {
  RecommendedJob.fromJson(Map<String, dynamic> json)
    : key = '${json['source']}/${json['source_id']}',
      requiredToCheck = json['required_to_check'] as int,
      type = json['recommendation_type'] as String?,
      notice = json['notice'] as String?,
      matched = _rows(
        json['matched_requirements'],
        RecommendationComparison.fromJson,
      );
  final String key;
  final int requiredToCheck;
  final String? type, notice;
  final List<RecommendationComparison> matched;

  bool get hasVerifiedEvidence => type == null || type == 'evidence_match';
}

class RecommendationDisplayCandidate {
  RecommendationDisplayCandidate.fromJson(Map<String, dynamic> json)
    : posting = RecommendationPosting.fromJson(_map(json['posting'])),
      type = json['display_type'] as String,
      status = json['analysis_status'] as String,
      notice = json['notice'] as String?,
      guidanceSentences = _guidanceSentences(json['stage_guidance']);

  final RecommendationPosting posting;
  final String type, status;
  final String? notice;
  final List<String> guidanceSentences;
}

class DocumentCitationLocation {
  DocumentCitationLocation.fromJson(Map<String, dynamic> json)
    : filename = json['filename'] as String,
      location = json['location'] as String,
      method = json['method'] as String;
  final String filename, location, method;
}

class RecommendationSource {
  RecommendationSource.fromJson(Map<String, dynamic> json)
    : source = json['source'] as String,
      status = json['status'] as String,
      failureReason = json['failure_reason'] as String?,
      reason = json['reason'] as String?;
  final String source, status;
  final String? failureReason, reason;
}

class JobRecommendationResponse {
  JobRecommendationResponse.fromJson(Map<String, dynamic> json)
    : raw = json,
      status = json['status'] as String,
      notice = json['notice'] as String? ?? '',
      occupationLabel =
          _map(json['query'] ?? const {})['occupation_label'] as String?,
      occupationCodes = _strings(
        _map(json['query'] ?? const {})['occupation_codes'],
      ),
      queryKeyword = _map(json['query'] ?? const {})['keyword'] as String?,
      searchNotice = json['search_notice'] as String?,
      categoryBrowseAvailable = json['category_browse_available'] == true,
      missingFields = _strings(json['missing_fields']),
      sources = _rows(json['sources'], RecommendationSource.fromJson),
      items = _rows(json['items'], RecommendationItem.fromJson),
      recommendations = _rows(json['recommendations'], RecommendedJob.fromJson),
      displayCandidates = json['display_candidates'] == null
          ? null
          : _rows(
              json['display_candidates'],
              RecommendationDisplayCandidate.fromJson,
            ),
      warnings = _strings(json['document_warnings']),
      locations = _map(
        json['document_locations'] ?? {},
      ).map((k, v) => MapEntry(k, DocumentCitationLocation.fromJson(_map(v))));

  /// The server's JSON, which is what a saved result keeps.
  final Map<String, dynamic> raw;
  final String status, notice;
  final String? occupationLabel, queryKeyword, searchNotice;
  final List<String> occupationCodes;

  /// No posting in the chosen category matched the detail words; the student may browse it.
  final bool categoryBrowseAvailable;
  final List<String> missingFields, warnings;
  final List<RecommendationSource> sources;
  final List<RecommendationItem> items;
  final List<RecommendedJob> recommendations;
  final List<RecommendationDisplayCandidate>? displayCandidates;
  final Map<String, DocumentCitationLocation> locations;
}

class JobRecommendationApi {
  const JobRecommendationApi(this.api);
  final ApiGateway api;

  Future<List<JobCategory>> loadCategories() async {
    final payload = await api.request('GET', 'me/job-categories');
    return _rows(payload?['categories'], JobCategory.fromJson);
  }

  Future<JobRecommendationResponse> recommend(
    JobRecommendationRequest request,
  ) async => JobRecommendationResponse.fromJson(
    (await api.request('POST', 'me/job-recommendations', request.toJson()))!,
  );
}
