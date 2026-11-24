import '../api/job_analysis_models.dart';
import '../api/job_recommendation_api.dart';
import '../api/student_api.dart';
import '../assistant/ai_record_catalog.dart';

/// One kind of activity the server suggests for the target job's gaps.
class ActivityRecommendation {
  ActivityRecommendation.fromJson(Map<String, dynamic> json)
    : kind = json['kind'] as String,
      kindLabel = json['kind_label'] as String? ?? '활동',
      title = json['title'] as String,
      reason = json['reason'] as String,
      requirements = List<String>.from(json['requirements'] as List? ?? []),
      keywords = List<String>.from(json['keywords'] as List? ?? []),
      sites = List<String>.from(json['sites'] as List? ?? []),
      deliverable = json['deliverable'] as String?,
      weeks = json['weeks'] as int?;
  final String kind, kindLabel, title, reason;
  final List<String> requirements, keywords, sites;
  final String? deliverable;
  final int? weeks;
}

class ActivitySite {
  ActivitySite.fromJson(Map<String, dynamic> json)
    : name = json['name'] as String,
      url = json['url'] as String;
  final String name, url;
}

class ActivityRecommendationResult {
  ActivityRecommendationResult.fromJson(this.raw)
    : status = raw['status'] as String,
      missingFields = List<String>.from(raw['missing_fields'] as List? ?? []),
      goalLabel = _map(raw['goal'])['label'] as String?,
      goalKeyword = _map(raw['goal'])['keyword'] as String? ?? '',
      regionLabel = raw['region_label'] as String?,
      gapCount = _map(raw['gap_basis'])['gaps'] as int? ?? 0,
      gapAnalyzedAt = DateTime.tryParse(
        _map(raw['gap_basis'])['analyzed_at'] as String? ?? '',
      ),
      recommendations = [
        for (final value in raw['recommendations'] as List? ?? const [])
          ActivityRecommendation.fromJson(_map(value)),
      ],
      summary = raw['summary'] as String?,
      internships = [
        for (final value in raw['internships'] as List? ?? const [])
          RecommendationPosting.fromJson(_map(value)),
      ],
      internshipSources = [
        for (final value in raw['internship_sources'] as List? ?? const [])
          RecommendationSource.fromJson(_map(value)),
      ],
      sites = {
        for (final entry in _map(raw['sites']).entries)
          entry.key: ActivitySite.fromJson(_map(entry.value)),
      },
      failureReason = raw['failure_reason'] as String?;

  static Map<String, dynamic> _map(Object? value) =>
      Map<String, dynamic>.from(value as Map? ?? const {});

  final Map<String, dynamic> raw;
  final String status;
  final List<String> missingFields;
  final String? goalLabel, regionLabel, summary, failureReason;
  final String goalKeyword;
  final int gapCount;
  final DateTime? gapAnalyzedAt;
  final List<ActivityRecommendation> recommendations;
  final List<RecommendationPosting> internships;
  final List<RecommendationSource> internshipSources;
  final Map<String, ActivitySite> sites;

  String get goalSummary =>
      [?goalLabel, if (goalKeyword.isNotEmpty) goalKeyword].join(' · ');
}

class ActivityRecommendationApi {
  const ActivityRecommendationApi(this.api);
  final StudentApi api;

  Future<ActivityRecommendationResult> recommend({
    required List<AiRecordOption> records,
    List<String> regions = const [],
    RecommendationAcademicStage? academicStage,
  }) async => ActivityRecommendationResult.fromJson(
    (await api.api.request('POST', 'me/activity-recommendations', {
      'records': [
        for (final r in records)
          PersonalEvidenceSelection(
            kind: r.kind,
            recordId: r.id,
            expectedVersion: r.version,
          ).toJson(),
      ],
      if (regions.isNotEmpty) 'regions': regions,
      if (academicStage != null) 'academic_stage': academicStage.name,
      'external_processing_consent': true,
    }))!,
  );
}
